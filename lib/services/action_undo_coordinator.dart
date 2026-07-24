import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/identity/uuid_v7_entity_id_generator.dart';
import '../models/action_autonomy_policy.dart';
import '../models/action_confirmation.dart';
import '../models/action_ledger.dart';
import 'action_confirmation_coordinator.dart';
import 'action_autonomy_policy_service.dart';
import 'action_ledger_repository.dart';
import 'action_ledger_service.dart';
import 'action_undo_adapters.dart';
import 'auth_service.dart';
import 'revisioned_cloud_repositories.dart';
import 'revisioned_domain_sync_service.dart';
import 'memory_library_service.dart';

final class ActionUndoCoordinator {
  ActionUndoCoordinator({
    required ActionLedgerRepository repository,
    required Future<ActionAutonomyPolicy> Function() policyLoader,
    required String? Function() currentScope,
    required Iterable<ActionUndoAdapter> adapters,
    DateTime Function()? now,
    String Function()? idGenerator,
    ActionConfirmationCoordinator? confirmationCoordinator,
  })  : _repository = repository,
        _policyLoader = policyLoader,
        _currentScope = currentScope,
        _adapters = Map.unmodifiable({
          for (final adapter in adapters) adapter.domain: adapter,
        }),
        _now = now ?? DateTime.now,
        _idGenerator = idGenerator ?? const UuidV7EntityIdGenerator().generate {
    _confirmationCoordinator = confirmationCoordinator ??
        ActionConfirmationCoordinator(
          idGenerator: _idGenerator,
          policyLoader: _policyLoader,
          currentAccountScopeId: _currentScope,
          now: _now,
        );
  }

  final ActionLedgerRepository _repository;
  final Future<ActionAutonomyPolicy> Function() _policyLoader;
  final String? Function() _currentScope;
  final Map<ActionLedgerDomain, ActionUndoAdapter> _adapters;
  final DateTime Function() _now;
  final String Function() _idGenerator;
  late final ActionConfirmationCoordinator _confirmationCoordinator;
  final Map<String, ActionConfirmation> _confirmationsByLedgerEntry = {};
  final Map<String, String> _undoMutationIds = {};

  ActionConfirmation? confirmationFor(String ledgerEntryId) =>
      _confirmationsByLedgerEntry[ledgerEntryId];

  static Future<ActionUndoCoordinator> production() async {
    const local = LocalActionLedgerRepository();
    final cloud = FirestoreActionLedgerRepository(
      firestore: FirebaseFirestore.instance,
      currentUid: () => AuthService.currentUserId,
    );
    final ledger = ActionLedgerService(
      local: local,
      cloud: cloud,
      currentScope: () => AuthService.currentUserId,
    );
    final policy = await ActionAutonomyPolicyService.local(
      currentAccountScopeId: () => AuthService.currentUserId,
    );
    final memoryLibrary = await MemoryLibraryService.production();
    return ActionUndoCoordinator(
      repository: local,
      policyLoader: policy.load,
      currentScope: () => AuthService.currentUserId,
      adapters: [
        EventActionUndoAdapter(ledger: ledger),
        TaskActionUndoAdapter(
          sync: TaskRevisionSyncService(
            cloud: const FirestoreRevisionedTaskRepository(),
          ),
          ledger: ledger,
        ),
        ShoppingActionUndoAdapter(
          sync: ShoppingRevisionSyncService(
            cloud: const FirestoreRevisionedShoppingRepository(),
          ),
          ledger: ledger,
        ),
        ProfileActionUndoAdapter(
          sync: ProfileRevisionSyncService(
            cloud: const FirestoreRevisionedProfileRepository(),
          ),
          ledger: ledger,
        ),
        MemoryActionUndoAdapter(
          library: memoryLibrary,
          ledger: ledger,
        ),
      ],
    );
  }

  Future<ActionUndoResult> request(
    String ledgerEntryId, {
    ActionConfirmationResponseChoice? responseChoice,
  }) async {
    final scopeId = _currentScope();
    if (scopeId == null || scopeId.isEmpty) {
      throw const FormatException('action_undo_auth_required');
    }
    final entry = await _repository.findById(scopeId, ledgerEntryId);
    if (entry == null) {
      throw const FormatException('action_undo_entry_not_found');
    }
    if (entry.undoCapability.type != ActionUndoCapabilityType.reversible &&
        entry.undoCapability.type !=
            ActionUndoCapabilityType.conditionallyReversible) {
      return ActionUndoResult(
        type: ActionUndoResultType.notSupported,
        capability: entry.undoCapability,
        reasonCode: 'undo_capability_not_supported',
      );
    }
    final policy = await _policyLoader();
    final adapter = _adapters[entry.actionDomain];
    if (adapter == null) {
      return ActionUndoResult(
        type: ActionUndoResultType.notSupported,
        capability: entry.undoCapability,
        reasonCode: 'undo_domain_not_supported',
      );
    }
    if (entry.undoCapability.confirmationRequired) {
      var confirmation = _confirmationsByLedgerEntry[ledgerEntryId];
      if (confirmation == null ||
          confirmation.state == ActionConfirmationState.blockedByPolicy) {
        final undoMutationId =
            _undoMutationIds.putIfAbsent(ledgerEntryId, _idGenerator);
        final scope = ActionConfirmationScope(
          type: entry.riskLevel == ActionRiskLevel.destructive
              ? ActionConfirmationScopeType.confirmDestructiveMutation
              : ActionConfirmationScopeType.executeExactMutation,
          targetId: entry.targetReference.entityId,
          operation: 'undo:${entry.targetReference.operationType}',
          expectedRevision: entry.resultRevision ?? entry.expectedRevision,
          fields: const [],
        );
        final issued = _confirmationCoordinator.issueWithPolicy(
          ActionConfirmationProposal(
            accountScopeId: scopeId,
            sessionGeneration: entry.sessionGeneration ?? 0,
            actionPendingId: ledgerEntryId,
            ledgerEntryId: ledgerEntryId,
            actionType: entry.actionType,
            actionDomain: entry.actionDomain,
            actionOrigin: ActionOrigin.explicitUserRequest,
            riskLevel: entry.riskLevel,
            scope: scope,
            requirements: [
              ActionConfirmationRequirement(
                source: ActionConfirmationRequirementSource.explicitProductRule,
                code: 'undo_confirmation_required',
                scope: scope.type,
                requiresFreshConfirmation: true,
                requiresSeparateConfirmation: false,
                policyVersionObserved: policy.schemaVersion,
              ),
              if (policy.mode == ActionAutonomyMode.suggestions)
                ActionConfirmationRequirement(
                  source: ActionConfirmationRequirementSource
                      .autonomySuggestionsMode,
                  code: 'autonomy_suggestions_confirmation',
                  scope: scope.type,
                  requiresFreshConfirmation: true,
                  requiresSeparateConfirmation: false,
                  policyVersionObserved: policy.schemaVersion,
                ),
            ],
            mutationId: undoMutationId,
            policyMode: policy.mode,
            policyVersion: policy.schemaVersion,
            presentation: const ActionConfirmationPresentation(
              title: 'Annuler cette action',
              summary: 'Appliquer la mutation inverse prévue.',
              consequence:
                  'Les changements plus récents ne seront jamais écrasés.',
            ),
            provenance: 'action_undo_coordinator',
            validity: const Duration(minutes: 5),
          ),
          policy: policy,
        );
        confirmation = issued.confirmation;
        _confirmationsByLedgerEntry[ledgerEntryId] = confirmation;
        if (responseChoice == null) {
          return ActionUndoResult(
            type: issued.type == ActionConfirmationResultType.blockedByPolicy
                ? ActionUndoResultType.blockedByPolicy
                : ActionUndoResultType.confirmationRequired,
            capability: entry.undoCapability,
            reasonCode: issued.reasonCode,
          );
        }
      }
      if (responseChoice == null) {
        return ActionUndoResult(
          type: ActionUndoResultType.confirmationRequired,
          capability: entry.undoCapability,
          reasonCode: 'undo_confirmation_required',
        );
      }
      final choice = responseChoice;
      final response = await _confirmationCoordinator.respond(
        response: ActionConfirmationResponse(
          responseId: _idGenerator(),
          confirmationId: confirmation.confirmationId,
          sessionGeneration: entry.sessionGeneration ?? 0,
          respondedAt: _now().toUtc(),
          choice: choice,
          actionFingerprint: confirmation.actionFingerprint,
        ),
        currentSessionGeneration: entry.sessionGeneration ?? 0,
        c3Validator: (_) => true,
        domainValidator: (_) => true,
        revisionValidator: (_) =>
            (entry.resultRevision ?? entry.expectedRevision) ==
            confirmation!.confirmationScope.expectedRevision,
      );
      _confirmationsByLedgerEntry[ledgerEntryId] = response.confirmation;
      if (choice != ActionConfirmationResponseChoice.accept) {
        return ActionUndoResult(
          type: ActionUndoResultType.notSupported,
          capability: entry.undoCapability,
          reasonCode: response.reasonCode,
        );
      }
      if (!response.dispatchAllowed) {
        return ActionUndoResult(
          type: response.type == ActionConfirmationResultType.blockedByPolicy
              ? ActionUndoResultType.blockedByPolicy
              : ActionUndoResultType.expired,
          capability: entry.undoCapability,
          reasonCode: response.reasonCode,
        );
      }
    }
    final result = await adapter.execute(
      source: entry,
      request: ActionUndoRequest(
        undoMutationId:
            _undoMutationIds.putIfAbsent(ledgerEntryId, _idGenerator),
        sourceLedgerEntryId: entry.ledgerEntryId,
        accountScopeId: scopeId,
        currentRevision: entry.resultRevision ?? -1,
        policyMode: policy.mode,
        policyVersion: policy.schemaVersion,
        confirmed: !entry.undoCapability.confirmationRequired ||
            _confirmationsByLedgerEntry[ledgerEntryId]?.state ==
                ActionConfirmationState.consumed,
        requestedAt: _now().toUtc(),
      ),
      policyAllowsMutation: policy.mode != ActionAutonomyMode.paused,
      domainPolicyAllowsMutation: true,
    );
    final confirmation = _confirmationsByLedgerEntry[ledgerEntryId];
    if (result.type == ActionUndoResultType.ready && confirmation != null) {
      _confirmationCoordinator.complete(
        confirmation.confirmationId,
        completedAt: _now().toUtc(),
      );
    }
    return result;
  }
}
