import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/identity/entity_id_generator.dart';
import '../../core/identity/uuid_v7_entity_id_generator.dart';
import '../../models/human/human_model.dart';
import '../../models/human/human_model_persistence.dart';
import '../../models/user_profile.dart';
import '../../repositories/human/firestore_human_model_repository.dart';
import '../../repositories/human/human_model_cloud_repository.dart';
import '../auth_service.dart';
import 'human_model_local_repository.dart';
import 'legacy_user_profile_human_adapter.dart';
import 'legacy_user_profile_reconciliation_service.dart';

final class HumanProfileProjection {
  const HumanProfileProjection({
    required this.schemaVersion,
    required this.personCount,
    required this.currentHouseholdCount,
    required this.currentResponsibilityCount,
  });

  final int schemaVersion;
  final int personCount;
  final int currentHouseholdCount;
  final int currentResponsibilityCount;

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'personCount': personCount,
        'currentHouseholdCount': currentHouseholdCount,
        'currentResponsibilityCount': currentResponsibilityCount,
      };
}

final class HumanModelService {
  static final ValueNotifier<int> modelVersion = ValueNotifier<int>(0);

  static void notifyModelChanged() {
    modelVersion.value++;
  }

  HumanModelService({
    HumanModelLocalRepository? localRepository,
    @Deprecated('Use localRepository') HumanModelLocalRepository? repository,
    HumanModelCloudRepository? cloudRepository,
    LegacyUserProfileHumanAdapter legacyAdapter =
        const LegacyUserProfileHumanAdapter(),
    LegacyUserProfileReconciliationService reconciliationService =
        const LegacyUserProfileReconciliationService(),
    EntityIdGenerator idGenerator = const UuidV7EntityIdGenerator(),
  })  : _localRepository = localRepository ??
            repository ??
            (throw ArgumentError.notNull('localRepository')),
        _cloudRepository = cloudRepository,
        _legacyAdapter = legacyAdapter,
        _reconciliationService = reconciliationService,
        _idGenerator = idGenerator;

  final HumanModelLocalRepository _localRepository;
  final HumanModelCloudRepository? _cloudRepository;
  final LegacyUserProfileHumanAdapter _legacyAdapter;
  final LegacyUserProfileReconciliationService _reconciliationService;
  final EntityIdGenerator _idGenerator;
  Future<void> _operationTail = Future.value();

  static Future<HumanModelService> createProduction() async {
    final preferences = await SharedPreferences.getInstance();
    return HumanModelService(
      localRepository: HumanModelLocalRepository(preferences),
      cloudRepository: FirestoreHumanModelRepository(
        firestore: FirebaseFirestore.instance,
        currentUid: () => AuthService.currentUserId,
      ),
    );
  }

  static Future<HumanModelService> createLocal() async {
    final preferences = await SharedPreferences.getInstance();
    return HumanModelService(
      localRepository: HumanModelLocalRepository(preferences),
    );
  }

  Future<HumanModel?> load(String accountScopeId) =>
      _localRepository.load(accountScopeId);

  Future<HumanModelLocalState?> loadState(String accountScopeId) =>
      _localRepository.loadState(accountScopeId);

  Future<HumanModel> loadOrMigrate({
    required String accountScopeId,
    required UserProfile legacyProfile,
    Map<String, Object?>? legacyProfileJson,
  }) async {
    final result = await bootstrap(
      accountScopeId: accountScopeId,
      legacyProfile: legacyProfile,
      legacyProfileJson: legacyProfileJson,
    );
    final model = result.state?.model;
    if (model == null) {
      throw HumanModelException(
        result.errorCode ?? 'human_model_initialization_failure',
      );
    }
    return model;
  }

  Future<HumanModelBootstrapResult> bootstrap({
    required String accountScopeId,
    UserProfile? legacyProfile,
    Map<String, Object?>? legacyProfileJson,
  }) {
    return _serialized(() async {
      HumanModelLocalState? local;
      try {
        local = await _localRepository.loadState(accountScopeId);
      } on HumanModelException catch (error) {
        return HumanModelBootstrapResult(
          status: HumanModelBootstrapStatus.failure,
          errorCode: error.code,
        );
      }

      final cloud = _cloudRepository;
      if (cloud == null) {
        if (local != null) {
          return HumanModelBootstrapResult(
            status: HumanModelBootstrapStatus.localFallback,
            state: local,
          );
        }
        if (legacyProfile == null) {
          return const HumanModelBootstrapResult(
            status: HumanModelBootstrapStatus.absent,
          );
        }
        final state = await _migrateLocally(
          accountScopeId: accountScopeId,
          legacyProfile: legacyProfile,
          legacyProfileJson: legacyProfileJson,
        );
        return HumanModelBootstrapResult(
          status: HumanModelBootstrapStatus.localFallback,
          state: state,
        );
      }

      RevisionedHumanModel? remote;
      try {
        remote = await cloud.read(accountScopeId);
      } on HumanModelException catch (error) {
        if (local != null) {
          return HumanModelBootstrapResult(
            status: HumanModelBootstrapStatus.localFallback,
            state: local.copyWith(
              syncStatus: HumanModelSyncStatus.pendingUpload,
            ),
            errorCode: error.code,
          );
        }
        return HumanModelBootstrapResult(
          status: HumanModelBootstrapStatus.failure,
          errorCode: error.code,
        );
      }

      if (remote != null) {
        return _adoptAndReconcile(
          remote: remote,
          legacyProfile: legacyProfile,
          legacyProfileJson: legacyProfileJson,
        );
      }

      if (local == null) {
        if (legacyProfile == null) {
          return const HumanModelBootstrapResult(
            status: HumanModelBootstrapStatus.absent,
          );
        }
        local = await _migrateLocally(
          accountScopeId: accountScopeId,
          legacyProfile: legacyProfile,
          legacyProfileJson: legacyProfileJson,
        );
      }

      final mutationId = local.lastMutationId ?? _idGenerator.generate();
      final create = await cloud.createIfAbsent(
        model: local.model,
        mutationId: mutationId,
        creationSource: local.knownCloudRevision == null
            ? 'legacyOrLocalMigration'
            : 'canonicalRestore',
      );
      if (create.isSuccess) {
        final state = _syncedState(create.value!);
        await _localRepository.saveState(state);
        return HumanModelBootstrapResult(
          status: local.knownCloudRevision == null
              ? HumanModelBootstrapStatus.migratedLegacyProfile
              : HumanModelBootstrapStatus.uploadedLocalModel,
          state: state,
        );
      }
      if (create.status == HumanModelWriteStatus.alreadyExists) {
        final winner = await cloud.read(accountScopeId);
        if (winner == null) {
          return HumanModelBootstrapResult(
            status: HumanModelBootstrapStatus.conflict,
            state: local.copyWith(
              syncStatus: HumanModelSyncStatus.remoteChanged,
              lastMutationId: mutationId,
            ),
            errorCode: 'human_model_creation_race',
          );
        }
        return _adoptAndReconcile(
          remote: winner,
          legacyProfile: legacyProfile,
          legacyProfileJson: legacyProfileJson,
        );
      }

      final pending = local.copyWith(
        syncStatus: HumanModelSyncStatus.pendingUpload,
        lastMutationId: mutationId,
      );
      await _localRepository.saveState(pending);
      return HumanModelBootstrapResult(
        status: create.status == HumanModelWriteStatus.revisionConflict
            ? HumanModelBootstrapStatus.conflict
            : HumanModelBootstrapStatus.localFallback,
        state: pending,
        errorCode: create.status.name,
      );
    });
  }

  Future<HumanModelWriteResult> saveCanonical({
    required HumanModel proposed,
    required int expectedRevision,
    required String mutationId,
    DateTime? createdAt,
  }) {
    return _serialized(() async {
      proposed.validate();
      final pendingMutation = PendingHumanModelMutation(
        mutationId: mutationId,
        expectedRevision: expectedRevision,
        proposed: proposed,
        createdAt: createdAt ?? DateTime.now().toUtc(),
      );
      final current = await _localRepository.loadState(
        proposed.accountScopeId,
      );
      if (current == null) {
        return const HumanModelWriteResult.status(
          HumanModelWriteStatus.notFound,
        );
      }
      if (current.knownCloudRevision != expectedRevision) {
        return const HumanModelWriteResult.status(
          HumanModelWriteStatus.revisionConflict,
        );
      }
      final pendingState = current.copyWith(
        model: proposed,
        syncStatus: HumanModelSyncStatus.pendingUpload,
        lastMutationId: mutationId,
        pendingMutation: pendingMutation,
      );
      await _localRepository.saveState(pendingState);

      final cloud = _cloudRepository;
      if (cloud == null) {
        return const HumanModelWriteResult.status(
          HumanModelWriteStatus.unavailable,
        );
      }
      final result = await cloud.update(
        model: proposed,
        expectedRevision: expectedRevision,
        mutationId: mutationId,
      );
      if (result.isSuccess) {
        await _localRepository.saveState(_syncedState(result.value!));
      } else if (result.status == HumanModelWriteStatus.revisionConflict) {
        await _localRepository.saveState(
          pendingState.copyWith(syncStatus: HumanModelSyncStatus.remoteChanged),
        );
      }
      return result;
    });
  }

  Future<void> save(HumanModel model) => _localRepository.save(model);

  HumanPerson? person(HumanModel model, String personId) =>
      model.personById(personId);

  List<HumanRelationship> activeRelationships(
    HumanModel model,
    DateTime at,
  ) =>
      model.activeRelationships(at);

  List<HumanHousehold> activeHouseholds(HumanModel model, DateTime at) =>
      model.activeHouseholds(at);

  List<HumanResponsibility> activeResponsibilities(
    HumanModel model,
    DateTime at,
  ) =>
      model.activeResponsibilities(at);

  HumanProfileProjection project(HumanModel model, DateTime at) {
    return HumanProfileProjection(
      schemaVersion: model.schemaVersion,
      personCount: model.persons.length,
      currentHouseholdCount: model.activeHouseholds(at).length,
      currentResponsibilityCount: model.activeResponsibilities(at).length,
    );
  }

  Future<HumanModelLocalState> _migrateLocally({
    required String accountScopeId,
    required UserProfile legacyProfile,
    Map<String, Object?>? legacyProfileJson,
  }) async {
    final migrated = _legacyAdapter.migrate(
      profile: legacyProfile,
      legacyProfile: legacyProfileJson ?? legacyProfile.toJson(),
      accountScopeId: accountScopeId,
      idGenerator: _idGenerator,
    );
    final state = HumanModelLocalState(
      model: migrated,
      syncStatus: HumanModelSyncStatus.pendingUpload,
      migrationStatus: HumanModelMigrationStatus.complete,
    );
    await _localRepository.saveState(state);
    return state;
  }

  HumanModelLocalState _syncedState(RevisionedHumanModel revisioned) =>
      HumanModelLocalState(
        model: revisioned.model,
        knownCloudRevision: revisioned.modelRevision,
        syncStatus: HumanModelSyncStatus.synced,
        lastMutationId: revisioned.lastMutationId,
        migrationStatus: revisioned.migrationStatus,
      );

  Future<HumanModelBootstrapResult> _adoptAndReconcile({
    required RevisionedHumanModel remote,
    required UserProfile? legacyProfile,
    required Map<String, Object?>? legacyProfileJson,
  }) async {
    final canonical = _syncedState(remote);
    if (legacyProfile == null) {
      await _localRepository.saveState(canonical);
      return HumanModelBootstrapResult(
        status: HumanModelBootstrapStatus.restoredFromCloud,
        state: canonical,
      );
    }
    final reconciliation = _reconciliationService.reconcile(
      current: remote.model,
      legacyProfile: legacyProfile,
      rawLegacyProfile: legacyProfileJson,
      idGenerator: _idGenerator,
    );
    if (reconciliation.status == LegacyHumanReconciliationStatus.unchanged) {
      await _localRepository.saveState(canonical);
      return HumanModelBootstrapResult(
        status: HumanModelBootstrapStatus.restoredFromCloud,
        state: canonical,
      );
    }
    final mutationId = _idGenerator.generate();
    final pendingMutation = PendingHumanModelMutation(
      mutationId: mutationId,
      expectedRevision: remote.modelRevision,
      proposed: reconciliation.proposed,
      createdAt: DateTime.now().toUtc(),
    );
    if (reconciliation.status ==
        LegacyHumanReconciliationStatus.needsConfirmation) {
      final pending = canonical.copyWith(
        syncStatus: HumanModelSyncStatus.remoteChanged,
        lastMutationId: mutationId,
        pendingMutation: pendingMutation,
      );
      await _localRepository.saveState(pending);
      return HumanModelBootstrapResult(
        status: HumanModelBootstrapStatus.conflict,
        state: pending,
        errorCode: 'human_legacy_reconciliation_required',
      );
    }
    final result = await _cloudRepository!.update(
      model: reconciliation.proposed,
      expectedRevision: remote.modelRevision,
      mutationId: mutationId,
    );
    if (result.isSuccess) {
      final updated = _syncedState(result.value!);
      await _localRepository.saveState(updated);
      return HumanModelBootstrapResult(
        status: HumanModelBootstrapStatus.restoredFromCloud,
        state: updated,
      );
    }
    final pending = canonical.copyWith(
      syncStatus: result.status == HumanModelWriteStatus.revisionConflict
          ? HumanModelSyncStatus.remoteChanged
          : HumanModelSyncStatus.pendingUpload,
      lastMutationId: mutationId,
      pendingMutation: pendingMutation,
    );
    await _localRepository.saveState(pending);
    return HumanModelBootstrapResult(
      status: result.status == HumanModelWriteStatus.revisionConflict
          ? HumanModelBootstrapStatus.conflict
          : HumanModelBootstrapStatus.localFallback,
      state: pending,
      errorCode: result.status.name,
    );
  }

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final completion = _operationTail.then((_) => operation());
    _operationTail = completion.then<void>((_) {}, onError: (_) {});
    return completion;
  }
}
