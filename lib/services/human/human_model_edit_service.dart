import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/identity/entity_id_generator.dart';
import '../../core/identity/uuid_v7_entity_id_generator.dart';
import '../../models/human/human_model.dart';
import '../../models/human/human_model_persistence.dart';
import '../../models/user_profile.dart';
import '../../models/action_autonomy_policy.dart';
import '../../models/action_ledger.dart';
import '../action_autonomy_policy_service.dart';
import '../action_ledger_repository.dart';
import '../action_ledger_service.dart';
import '../auth_service.dart';
import '../storage_service.dart';
import 'human_model_service.dart';
import 'human_model_user_profile_projection_service.dart';
import 'legacy_user_profile_reconciliation_service.dart';

enum HumanModelEditStatus {
  success,
  validationFailure,
  revisionConflict,
  networkUnavailable,
  pendingSync,
  needsConfirmation,
  notFound,
  cancelled,
  storageFailure,
  unknown,
}

final class HumanModelEditResult {
  const HumanModelEditResult({
    required this.status,
    this.state,
    this.draft,
  });

  final HumanModelEditStatus status;
  final HumanModelLocalState? state;
  final HumanModel? draft;

  bool get isSuccess => status == HumanModelEditStatus.success;
}

final class HumanModelEditService {
  HumanModelEditService({
    required HumanModelService humanModelService,
    ActionLedgerService? ledger,
    Future<ActionAutonomyPolicy> Function()? policyLoader,
    EntityIdGenerator idGenerator = const UuidV7EntityIdGenerator(),
  })  : _humanModelService = humanModelService,
        _ledger = ledger,
        _policyLoader = policyLoader,
        _idGenerator = idGenerator;

  static Future<HumanModelEditService> createProduction() async {
    final policy = await ActionAutonomyPolicyService.local(
      currentAccountScopeId: () => AuthService.currentUserId,
    );
    return HumanModelEditService(
      humanModelService: await HumanModelService.createProduction(),
      ledger: ActionLedgerService(
        local: const LocalActionLedgerRepository(),
        cloud: FirestoreActionLedgerRepository(
          firestore: FirebaseFirestore.instance,
          currentUid: () => AuthService.currentUserId,
        ),
        currentScope: () => AuthService.currentUserId,
      ),
      policyLoader: policy.load,
    );
  }

  final HumanModelService _humanModelService;
  final ActionLedgerService? _ledger;
  final Future<ActionAutonomyPolicy> Function()? _policyLoader;
  final EntityIdGenerator _idGenerator;

  Future<HumanModelLocalState?> load(String accountScopeId) =>
      _humanModelService.loadState(accountScopeId);

  Future<UserProfile> persistLegacyProjection({
    required HumanModel model,
    required UserProfile legacy,
  }) async {
    final projected = const HumanModelUserProfileProjectionService().project(
      model: model,
      legacy: legacy,
    );
    return StorageService.saveUserProfile(projected);
  }

  Future<HumanModelEditResult> commitLegacyProfile({
    required String accountScopeId,
    required UserProfile profile,
  }) =>
      commit(
        accountScopeId: accountScopeId,
        resolvePendingProposal: true,
        transform: (current) => const LegacyUserProfileReconciliationService()
            .applyExplicitProfileEdit(
          current: current,
          profile: profile,
          idGenerator: _idGenerator,
        ),
      );

  Future<HumanModelEditResult> commit({
    required String accountScopeId,
    required HumanModel Function(HumanModel current) transform,
    bool resolvePendingProposal = false,
  }) async {
    HumanModelLocalState? current;
    try {
      current = await _humanModelService.loadState(accountScopeId);
    } on Object {
      return const HumanModelEditResult(
        status: HumanModelEditStatus.storageFailure,
      );
    }
    if (current == null || current.knownCloudRevision == null) {
      return HumanModelEditResult(
        status: current == null
            ? HumanModelEditStatus.notFound
            : HumanModelEditStatus.networkUnavailable,
        state: current,
      );
    }
    if (current.pendingMutation != null &&
        current.syncStatus != HumanModelSyncStatus.synced &&
        !resolvePendingProposal) {
      return HumanModelEditResult(
        status: HumanModelEditStatus.needsConfirmation,
        state: current,
      );
    }

    late final HumanModel proposed;
    try {
      proposed = transform(current.model);
      proposed.validate();
    } on HumanModelException {
      return HumanModelEditResult(
        status: HumanModelEditStatus.validationFailure,
        state: current,
      );
    } on Object {
      return HumanModelEditResult(
        status: HumanModelEditStatus.unknown,
        state: current,
      );
    }

    try {
      final mutationId = _idGenerator.generate();
      final ledger = _ledger;
      ActionLedgerEntry? ledgerEntry;
      if (ledger != null) {
        final policy = await _policyLoader!();
        ledgerEntry = await ledger.begin(
          mutationId: mutationId,
          actionType: ActionType.updatePerson,
          domain: ActionLedgerDomain.humanModel,
          origin: ActionOrigin.explicitUserRequest,
          riskLevel: ActionRiskLevel.sensitiveMutation,
          policyMode: policy.mode,
          policyVersion: policy.schemaVersion,
          target: ActionTargetReference(
            domain: ActionLedgerDomain.humanModel,
            entityType: 'humanModel',
            entityId: 'human-model',
            operationType: 'updateHumanModel',
            revisionBefore: current.knownCloudRevision!,
            tombstoneBefore: false,
            patchType: 'humanModelTypedEdit',
            undoStrategy: ActionUndoStrategy.manualHumanModelResolution,
          ),
          undoCapability: const ActionUndoCapability(
            type: ActionUndoCapabilityType.unsupportedDomain,
            strategy: ActionUndoStrategy.manualHumanModelResolution,
            reasonCode: 'undo_human_model_requires_resolution',
            confirmationRequired: true,
            currentRevisionRequired: true,
            domain: ActionLedgerDomain.humanModel,
            riskLevel: ActionRiskLevel.sensitiveMutation,
          ),
          correlationId: 'ledger-$mutationId',
          provenance: 'human_model_edit_service',
        );
        ledgerEntry = await ledger.markDispatching(
          ledgerEntry,
          transitionMutationId: '$mutationId:dispatch',
        );
      }
      final result = await _humanModelService.saveCanonical(
        proposed: proposed,
        expectedRevision: current.knownCloudRevision!,
        mutationId: mutationId,
      );
      final mapped = await _mapWriteResult(result, accountScopeId, proposed);
      if (mapped.status == HumanModelEditStatus.success ||
          mapped.status == HumanModelEditStatus.pendingSync) {
        HumanModelService.notifyModelChanged();
      }
      if (ledgerEntry != null) {
        await ledger!.recordResult(
          ledgerEntry,
          outcome: switch (mapped.status) {
            HumanModelEditStatus.success => ActionOutcome.completed,
            HumanModelEditStatus.pendingSync ||
            HumanModelEditStatus.networkUnavailable =>
              ActionOutcome.pendingSync,
            HumanModelEditStatus.revisionConflict => ActionOutcome.conflict,
            _ => ActionOutcome.validationFailure,
          },
          transitionMutationId: '$mutationId:result',
          resultRevision: mapped.state?.knownCloudRevision,
        );
      }
      return mapped;
    } on Object {
      return HumanModelEditResult(
        status: HumanModelEditStatus.storageFailure,
        state: current,
        draft: proposed,
      );
    }
  }

  HumanPerson newPerson(
    String accountScopeId, {
    String? displayName,
    DateTime? birthDate,
  }) =>
      HumanPerson(
        id: _idGenerator.generate(),
        accountScopeId: accountScopeId,
        displayName: _optional(displayName),
        evidence: _confirmedEvidence,
        customFields: {
          if (birthDate != null)
            'birthDate': birthDate.toUtc().toIso8601String(),
        },
      );

  HumanRelationship newRelationship({
    required String accountScopeId,
    required String sourcePersonId,
    required String targetPersonId,
    required String type,
    String? customType,
    HumanRecordStatus status = HumanRecordStatus.active,
    HumanValidityPeriod validity = const HumanValidityPeriod(),
  }) =>
      HumanRelationship(
        id: _idGenerator.generate(),
        accountScopeId: accountScopeId,
        sourcePersonId: sourcePersonId,
        targetPersonId: targetPersonId,
        type: type,
        customType: _optional(customType),
        status: status,
        validity: validity,
        evidence: _confirmedEvidence,
      );

  HumanHousehold newHousehold(
    String accountScopeId, {
    String? displayName,
    HouseholdStatus status = HouseholdStatus.primary,
    HumanValidityPeriod validity = const HumanValidityPeriod(),
  }) =>
      HumanHousehold(
        id: _idGenerator.generate(),
        accountScopeId: accountScopeId,
        displayName: _optional(displayName),
        status: status,
        validity: validity,
        evidence: _confirmedEvidence,
      );

  HumanHouseholdMembership newMembership({
    required String accountScopeId,
    required String householdId,
    required String personId,
    required String role,
    String? customRole,
    HumanValidityPeriod validity = const HumanValidityPeriod(),
  }) =>
      HumanHouseholdMembership(
        id: _idGenerator.generate(),
        accountScopeId: accountScopeId,
        householdId: householdId,
        personId: personId,
        role: role,
        customRole: _optional(customRole),
        validity: validity,
        evidence: _confirmedEvidence,
      );

  HumanResidence newResidence({
    required String accountScopeId,
    required String label,
    List<String> householdIds = const [],
    List<String> personIds = const [],
    ResidenceStatus status = ResidenceStatus.primary,
    HumanValidityPeriod validity = const HumanValidityPeriod(),
  }) =>
      HumanResidence(
        id: _idGenerator.generate(),
        accountScopeId: accountScopeId,
        label: label.trim(),
        householdIds: householdIds,
        personIds: personIds,
        status: status,
        validity: validity,
        evidence: _confirmedEvidence,
      );

  HumanResponsibility newResponsibility({
    required String accountScopeId,
    required String responsiblePersonId,
    required String subjectPersonId,
    required String type,
    String? customType,
    String? scope,
    HumanRecordStatus status = HumanRecordStatus.active,
    HumanValidityPeriod validity = const HumanValidityPeriod(),
  }) =>
      HumanResponsibility(
        id: _idGenerator.generate(),
        accountScopeId: accountScopeId,
        responsiblePersonId: responsiblePersonId,
        subjectPersonId: subjectPersonId,
        type: type,
        customType: _optional(customType),
        scope: _optional(scope),
        status: status,
        validity: validity,
        evidence: _confirmedEvidence,
      );

  Future<HumanModelEditResult> resolveLegacyProposal({
    required String accountScopeId,
    required bool accepted,
  }) async {
    HumanModelLocalState? current;
    try {
      current = await _humanModelService.loadState(accountScopeId);
    } on Object {
      return const HumanModelEditResult(
        status: HumanModelEditStatus.storageFailure,
      );
    }
    final pending = current?.pendingMutation;
    if (current == null || pending == null) {
      return HumanModelEditResult(
        status: HumanModelEditStatus.notFound,
        state: current,
      );
    }
    final proposal = pending.proposed;
    final model = accepted
        ? proposal
        : current.model.copyWith(
            legacyProfile: {
              ...proposal.legacyProfile,
              HumanLegacyReconciliationMarker.field:
                  HumanLegacyReconciliationMarker.forModel(proposal),
            },
          );
    return commit(
      accountScopeId: accountScopeId,
      transform: (_) => model,
      resolvePendingProposal: true,
    );
  }

  Future<HumanModelEditResult> _mapWriteResult(
    HumanModelWriteResult result,
    String accountScopeId,
    HumanModel proposed,
  ) async {
    if (result.status == HumanModelWriteStatus.revisionConflict) {
      await _humanModelService.bootstrap(accountScopeId: accountScopeId);
    }
    final state = await _humanModelService.loadState(accountScopeId);
    final status = switch (result.status) {
      HumanModelWriteStatus.success => HumanModelEditStatus.success,
      HumanModelWriteStatus.revisionConflict =>
        HumanModelEditStatus.revisionConflict,
      HumanModelWriteStatus.notFound => HumanModelEditStatus.notFound,
      HumanModelWriteStatus.unavailable => state?.pendingMutation == null
          ? HumanModelEditStatus.networkUnavailable
          : HumanModelEditStatus.pendingSync,
      HumanModelWriteStatus.invalidModel =>
        HumanModelEditStatus.validationFailure,
      HumanModelWriteStatus.persistenceFailure =>
        HumanModelEditStatus.storageFailure,
      HumanModelWriteStatus.scopeMismatch =>
        HumanModelEditStatus.storageFailure,
      HumanModelWriteStatus.alreadyExists => HumanModelEditStatus.unknown,
    };
    return HumanModelEditResult(
      status: status,
      state: state,
      draft: status == HumanModelEditStatus.revisionConflict ? proposed : null,
    );
  }

  String? _optional(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}

const _confirmedEvidence = HumanEvidence(
  source: HumanInformationSource.explicitUserInput,
  confirmation: HumanConfirmationStatus.confirmed,
);
