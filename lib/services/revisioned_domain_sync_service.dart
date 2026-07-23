import '../models/revisioned_domain_models.dart';
import '../models/revisioned_sync_protocol.dart';
import 'revisioned_domain_local_repository.dart';
import 'revisioned_offline_journal.dart';

typedef RevisionedActionRetryGuard = Future<bool> Function(
  RevisionedActionReference reference,
);

abstract interface class RevisionedTaskCloudRepository {
  Future<List<RevisionedTask>> load({int limit = 100});
  Future<RevisionedCloudWriteResult<RevisionedTask>> create(
    TaskMutation mutation,
    String accountScopeId,
  );
  Future<RevisionedCloudWriteResult<RevisionedTask>> update(
    TaskMutation mutation,
    String accountScopeId,
  );
}

abstract interface class RevisionedShoppingCloudRepository {
  Future<List<RevisionedShoppingItem>> load({int limit = 100});
  Future<RevisionedCloudWriteResult<RevisionedShoppingItem>> create(
    ShoppingMutation mutation,
    String accountScopeId,
  );
  Future<RevisionedCloudWriteResult<RevisionedShoppingItem>> update(
    ShoppingMutation mutation,
    String accountScopeId,
  );
}

abstract interface class RevisionedProfileCloudRepository {
  Future<RevisionedProfileState?> load();
  Future<RevisionedCloudWriteResult<RevisionedProfileState>> create(
    ProfileMutation mutation,
    String accountScopeId,
  );
  Future<RevisionedCloudWriteResult<RevisionedProfileState>> update(
    ProfileMutation mutation,
    String accountScopeId,
  );
}

final class RevisionedSyncResult<T> {
  const RevisionedSyncResult({
    required this.status,
    this.value,
    this.conflict,
  });

  final RevisionedCloudWriteStatus status;
  final T? value;
  final RevisionedConflict? conflict;

  bool get isRealSuccess =>
      status == RevisionedCloudWriteStatus.success ||
      status == RevisionedCloudWriteStatus.idempotent;
}

final class TaskRevisionSyncService {
  const TaskRevisionSyncService({
    required RevisionedTaskCloudRepository cloud,
    RevisionedDomainLocalRepository local =
        const RevisionedDomainLocalRepository(),
    RevisionedOfflineJournal journal = const RevisionedOfflineJournal(),
    RevisionedActionRetryGuard? retryGuard,
    DateTime Function()? now,
  })  : _cloud = cloud,
        _local = local,
        _journal = journal,
        _retryGuard = retryGuard,
        _now = now;

  final RevisionedTaskCloudRepository _cloud;
  final RevisionedDomainLocalRepository _local;
  final RevisionedOfflineJournal _journal;
  final RevisionedActionRetryGuard? _retryGuard;
  final DateTime Function()? _now;

  Future<List<RevisionedTask>> bootstrap(String scope) async {
    final local = await _local.loadTasks(scope);
    try {
      final cloud = await _cloud.load();
      final merged = _mergeTaskState(local, cloud);
      await _local.saveTasks(scope, merged);
      return merged;
    } on Object {
      return local;
    }
  }

  Future<RevisionedSyncResult<RevisionedTask>> apply(
    String scope,
    TaskMutation mutation,
  ) async {
    _validateMutation(scope, mutation);
    final local = await _local.loadTasks(scope);
    final current = local.where((item) => item.entityId == mutation.targetId);
    final existing = current.isEmpty ? null : current.single;
    if (mutation.type == TaskMutationType.createTask) {
      if (mutation.expectedRevision != 0 || existing != null) {
        return _conflict(scope, mutation, existing?.revision ?? 0);
      }
    } else if (existing == null ||
        existing.revision != mutation.expectedRevision ||
        existing.isTombstone) {
      return _conflict(scope, mutation, existing?.revision ?? 0);
    }
    final now = (_now ?? DateTime.now)().toUtc();
    final proposed = existing == null
        ? RevisionedTask(
            accountScopeId: scope,
            entityId: mutation.targetId,
            task: mutation.task,
            revision: 1,
            createdAt: now,
            updatedAt: now,
            lastMutationId: mutation.mutationId,
            syncStatus: RevisionedSyncStatus.queued,
          )
        : existing.copyWith(
            task: mutation.task,
            revision: existing.revision + 1,
            updatedAt: now,
            lastMutationId: mutation.mutationId,
            syncStatus: RevisionedSyncStatus.queued,
            isTombstone: mutation.type == TaskMutationType.deleteTask ||
                mutation.type == TaskMutationType.archiveTask,
          );
    await _local.saveTasks(scope, [
      ...local.where((item) => item.entityId != mutation.targetId),
      proposed,
    ]);
    await _journal.enqueue(
      accountScopeId: scope,
      domain: RevisionedSyncDomain.task,
      mutation: mutation,
    );
    return _send(scope, mutation);
  }

  Future<RevisionedSyncResult<RevisionedTask>> retry(
    String scope,
    String mutationId,
  ) async {
    final state = await _journal.load(
      accountScopeId: scope,
      domain: RevisionedSyncDomain.task,
    );
    final matches =
        state.mutations.where((item) => item.mutationId == mutationId);
    if (matches.isEmpty) {
      return const RevisionedSyncResult(
        status: RevisionedCloudWriteStatus.notFound,
      );
    }
    final mutation = matches.single as TaskMutation;
    if (mutation.attempt >= RevisionedJournalState.maxAttempts) {
      return const RevisionedSyncResult(
        status: RevisionedCloudWriteStatus.unavailable,
      );
    }
    final actionReference = mutation.actionReference;
    if (actionReference != null &&
        (_retryGuard == null || !await _retryGuard(actionReference))) {
      return const RevisionedSyncResult(
        status: RevisionedCloudWriteStatus.unavailable,
      );
    }
    final retried = _withAttempt(mutation, mutation.attempt + 1);
    await _journal.replace(
      state.copyWith(
        mutations: state.mutations
            .map((item) => item.mutationId == mutationId ? retried : item)
            .toList(),
      ),
    );
    return _send(scope, retried as TaskMutation);
  }

  Future<RevisionedSyncResult<RevisionedTask>> _send(
    String scope,
    TaskMutation mutation,
  ) async {
    try {
      final result = mutation.type == TaskMutationType.createTask
          ? await _cloud.create(mutation, scope)
          : await _cloud.update(mutation, scope);
      if (result.status == RevisionedCloudWriteStatus.success ||
          result.status == RevisionedCloudWriteStatus.idempotent) {
        await _complete(scope, mutation.mutationId, result.value!);
        return RevisionedSyncResult(status: result.status, value: result.value);
      }
      if (result.status == RevisionedCloudWriteStatus.revisionConflict ||
          result.status == RevisionedCloudWriteStatus.mutationConflict) {
        return _conflict(scope, mutation, result.value?.revision ?? 0);
      }
      return RevisionedSyncResult(status: result.status, value: result.value);
    } on Object {
      return const RevisionedSyncResult(
        status: RevisionedCloudWriteStatus.unavailable,
      );
    }
  }

  Future<void> _complete(
    String scope,
    String mutationId,
    RevisionedTask remote,
  ) async {
    final local = await _local.loadTasks(scope);
    await _local.saveTasks(scope, [
      ...local.where((item) => item.entityId != remote.entityId),
      remote,
    ]);
    final journal = await _journal.load(
      accountScopeId: scope,
      domain: RevisionedSyncDomain.task,
    );
    await _journal.replace(
      journal.copyWith(
        mutations: journal.mutations
            .where((item) => item.mutationId != mutationId)
            .toList(),
        receipts: [...journal.receipts, mutationId]
            .take(RevisionedJournalState.maxReceipts)
            .toList(),
      ),
    );
  }

  Future<RevisionedSyncResult<RevisionedTask>> _conflict(
    String scope,
    TaskMutation mutation,
    int remoteRevision,
  ) async {
    final conflict = RevisionedConflict(
      conflictId: 'task:${mutation.mutationId}',
      domain: RevisionedSyncDomain.task,
      targetId: mutation.targetId,
      mutationId: mutation.mutationId,
      expectedRevision: mutation.expectedRevision,
      remoteRevision: remoteRevision,
      type: mutation.type == TaskMutationType.completeTask ||
              mutation.type == TaskMutationType.reopenTask
          ? RevisionedConflictType.completionConflict
          : RevisionedConflictType.revisionConflict,
      createdAt: (_now ?? DateTime.now)().toUtc(),
      allowedResolutions: const [
        RevisionedConflictResolution.keepRemote,
        RevisionedConflictResolution.discardLocalMutation,
        RevisionedConflictResolution.requireUserResolution,
      ],
    );
    final journal = await _journal.load(
      accountScopeId: scope,
      domain: RevisionedSyncDomain.task,
    );
    await _journal.replace(
      journal.copyWith(
        conflicts: [...journal.conflicts, conflict]
            .take(RevisionedJournalState.maxConflicts)
            .toList(),
      ),
    );
    return RevisionedSyncResult(
      status: RevisionedCloudWriteStatus.revisionConflict,
      conflict: conflict,
    );
  }

  void _validateMutation(String scope, TaskMutation mutation) {
    if (scope.trim().isEmpty ||
        mutation.targetId != mutation.task.id ||
        mutation.mutationId.trim().isEmpty ||
        mutation.expectedRevision < 0) {
      throw const FormatException('invalid_task_mutation');
    }
  }
}

List<RevisionedTask> _mergeTaskState(
  List<RevisionedTask> local,
  List<RevisionedTask> cloud,
) {
  final merged = {for (final item in local) item.entityId: item};
  for (final remote in cloud) {
    final localValue = merged[remote.entityId];
    if (localValue == null ||
        remote.revision >= localValue.revision &&
            localValue.syncStatus == RevisionedSyncStatus.synced) {
      merged[remote.entityId] = remote;
    }
  }
  final values = merged.values.toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return values.take(RevisionedDomainLocalRepository.maxEntities).toList();
}

final class ShoppingRevisionSyncService {
  const ShoppingRevisionSyncService({
    required RevisionedShoppingCloudRepository cloud,
    RevisionedDomainLocalRepository local =
        const RevisionedDomainLocalRepository(),
    RevisionedOfflineJournal journal = const RevisionedOfflineJournal(),
    RevisionedActionRetryGuard? retryGuard,
    DateTime Function()? now,
  })  : _cloud = cloud,
        _local = local,
        _journal = journal,
        _retryGuard = retryGuard,
        _now = now;

  final RevisionedShoppingCloudRepository _cloud;
  final RevisionedDomainLocalRepository _local;
  final RevisionedOfflineJournal _journal;
  final RevisionedActionRetryGuard? _retryGuard;
  final DateTime Function()? _now;

  Future<List<RevisionedShoppingItem>> bootstrap(String scope) async {
    final local = await _local.loadShopping(scope);
    try {
      final cloud = await _cloud.load();
      final merged = {for (final item in local) item.entityId: item};
      for (final remote in cloud) {
        final current = merged[remote.entityId];
        if (current == null ||
            remote.revision >= current.revision &&
                current.syncStatus == RevisionedSyncStatus.synced) {
          merged[remote.entityId] = remote;
        }
      }
      final result = merged.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      final bounded =
          result.take(RevisionedDomainLocalRepository.maxEntities).toList();
      await _local.saveShopping(scope, bounded);
      return bounded;
    } on Object {
      return local;
    }
  }

  Future<RevisionedSyncResult<RevisionedShoppingItem>> apply(
    String scope,
    ShoppingMutation mutation,
  ) async {
    if (scope.trim().isEmpty ||
        mutation.targetId != mutation.item.id ||
        mutation.mutationId.trim().isEmpty ||
        mutation.expectedRevision < 0) {
      throw const FormatException('invalid_shopping_mutation');
    }
    final local = await _local.loadShopping(scope);
    final matches = local.where((item) => item.entityId == mutation.targetId);
    final existing = matches.isEmpty ? null : matches.single;
    if (mutation.type == ShoppingMutationType.addItem) {
      if (mutation.expectedRevision != 0 || existing != null) {
        return _conflict(scope, mutation, existing?.revision ?? 0);
      }
    } else if (existing == null ||
        existing.revision != mutation.expectedRevision ||
        existing.isTombstone ||
        mutation.clearGeneration < existing.clearGeneration) {
      return _conflict(scope, mutation, existing?.revision ?? 0);
    }
    final now = (_now ?? DateTime.now)().toUtc();
    final proposed = RevisionedShoppingItem(
      accountScopeId: scope,
      entityId: mutation.targetId,
      item: mutation.item,
      revision: existing == null ? 1 : existing.revision + 1,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      lastMutationId: mutation.mutationId,
      syncStatus: RevisionedSyncStatus.queued,
      isTombstone: mutation.type == ShoppingMutationType.removeItem ||
          mutation.type == ShoppingMutationType.clearList,
      clearGeneration: mutation.clearGeneration,
    );
    await _local.saveShopping(scope, [
      ...local.where((item) => item.entityId != mutation.targetId),
      proposed,
    ]);
    await _journal.enqueue(
      accountScopeId: scope,
      domain: RevisionedSyncDomain.shopping,
      mutation: mutation,
    );
    return _send(scope, mutation);
  }

  Future<RevisionedSyncResult<RevisionedShoppingItem>> retry(
    String scope,
    String mutationId,
  ) async {
    final journal = await _journal.load(
      accountScopeId: scope,
      domain: RevisionedSyncDomain.shopping,
    );
    final found =
        journal.mutations.where((item) => item.mutationId == mutationId);
    if (found.isEmpty) {
      return const RevisionedSyncResult(
        status: RevisionedCloudWriteStatus.notFound,
      );
    }
    final mutation = found.single as ShoppingMutation;
    final actionReference = mutation.actionReference;
    if (mutation.attempt >= RevisionedJournalState.maxAttempts ||
        actionReference != null &&
            (_retryGuard == null || !await _retryGuard(actionReference))) {
      return const RevisionedSyncResult(
        status: RevisionedCloudWriteStatus.unavailable,
      );
    }
    final retried = _withAttempt(mutation, mutation.attempt + 1);
    await _journal.replace(
      journal.copyWith(
        mutations: journal.mutations
            .map((item) => item.mutationId == mutationId ? retried : item)
            .toList(),
      ),
    );
    return _send(scope, retried as ShoppingMutation);
  }

  Future<RevisionedSyncResult<RevisionedShoppingItem>> _send(
    String scope,
    ShoppingMutation mutation,
  ) async {
    try {
      final result = mutation.type == ShoppingMutationType.addItem
          ? await _cloud.create(mutation, scope)
          : await _cloud.update(mutation, scope);
      if (result.status == RevisionedCloudWriteStatus.success ||
          result.status == RevisionedCloudWriteStatus.idempotent) {
        final local = await _local.loadShopping(scope);
        await _local.saveShopping(scope, [
          ...local.where((item) => item.entityId != result.value!.entityId),
          result.value!,
        ]);
        await _completeJournal(
          scope,
          RevisionedSyncDomain.shopping,
          mutation.mutationId,
        );
        return RevisionedSyncResult(status: result.status, value: result.value);
      }
      if (result.status == RevisionedCloudWriteStatus.revisionConflict ||
          result.status == RevisionedCloudWriteStatus.mutationConflict) {
        return _conflict(scope, mutation, result.value?.revision ?? 0);
      }
      return RevisionedSyncResult(status: result.status, value: result.value);
    } on Object {
      return const RevisionedSyncResult(
        status: RevisionedCloudWriteStatus.unavailable,
      );
    }
  }

  Future<RevisionedSyncResult<RevisionedShoppingItem>> _conflict(
    String scope,
    ShoppingMutation mutation,
    int remoteRevision,
  ) async {
    final conflict = RevisionedConflict(
      conflictId: 'shopping:${mutation.mutationId}',
      domain: RevisionedSyncDomain.shopping,
      targetId: mutation.targetId,
      mutationId: mutation.mutationId,
      expectedRevision: mutation.expectedRevision,
      remoteRevision: remoteRevision,
      type: mutation.type == ShoppingMutationType.removeItem ||
              mutation.type == ShoppingMutationType.clearList
          ? RevisionedConflictType.listConflict
          : RevisionedConflictType.revisionConflict,
      createdAt: (_now ?? DateTime.now)().toUtc(),
      allowedResolutions: const [
        RevisionedConflictResolution.keepRemote,
        RevisionedConflictResolution.discardLocalMutation,
        RevisionedConflictResolution.requireUserResolution,
      ],
    );
    final journal = await _journal.load(
      accountScopeId: scope,
      domain: RevisionedSyncDomain.shopping,
    );
    await _journal.replace(
      journal.copyWith(
        conflicts: [...journal.conflicts, conflict]
            .take(RevisionedJournalState.maxConflicts)
            .toList(),
      ),
    );
    return RevisionedSyncResult(
      status: RevisionedCloudWriteStatus.revisionConflict,
      conflict: conflict,
    );
  }

  Future<void> _completeJournal(
    String scope,
    RevisionedSyncDomain domain,
    String mutationId,
  ) async {
    final journal = await _journal.load(accountScopeId: scope, domain: domain);
    await _journal.replace(
      journal.copyWith(
        mutations: journal.mutations
            .where((item) => item.mutationId != mutationId)
            .toList(),
        receipts: [...journal.receipts, mutationId]
            .take(RevisionedJournalState.maxReceipts)
            .toList(),
      ),
    );
  }
}

RevisionedDomainMutation _withAttempt(
  RevisionedDomainMutation mutation,
  int attempt,
) =>
    switch (mutation) {
      TaskMutation() => TaskMutation(
          mutationId: mutation.mutationId,
          targetId: mutation.targetId,
          expectedRevision: mutation.expectedRevision,
          createdAt: mutation.createdAt,
          attempt: attempt,
          nextRetryAt: mutation.nextRetryAt,
          state: RevisionedMutationState.sending,
          actionReference: mutation.actionReference,
          type: mutation.type,
          task: mutation.task,
        ),
      ShoppingMutation() => ShoppingMutation(
          mutationId: mutation.mutationId,
          targetId: mutation.targetId,
          expectedRevision: mutation.expectedRevision,
          createdAt: mutation.createdAt,
          attempt: attempt,
          nextRetryAt: mutation.nextRetryAt,
          state: RevisionedMutationState.sending,
          actionReference: mutation.actionReference,
          type: mutation.type,
          item: mutation.item,
          clearGeneration: mutation.clearGeneration,
        ),
      ProfileMutation() => ProfileMutation(
          mutationId: mutation.mutationId,
          targetId: mutation.targetId,
          expectedRevision: mutation.expectedRevision,
          createdAt: mutation.createdAt,
          attempt: attempt,
          nextRetryAt: mutation.nextRetryAt,
          state: RevisionedMutationState.sending,
          actionReference: mutation.actionReference,
          type: mutation.type,
          changedFields: mutation.changedFields,
          profile: mutation.profile,
        ),
    };

final class ProfileRevisionSyncService {
  const ProfileRevisionSyncService({
    required RevisionedProfileCloudRepository cloud,
    RevisionedDomainLocalRepository local =
        const RevisionedDomainLocalRepository(),
    RevisionedOfflineJournal journal = const RevisionedOfflineJournal(),
    RevisionedActionRetryGuard? retryGuard,
    DateTime Function()? now,
  })  : _cloud = cloud,
        _local = local,
        _journal = journal,
        _retryGuard = retryGuard,
        _now = now;

  final RevisionedProfileCloudRepository _cloud;
  final RevisionedDomainLocalRepository _local;
  final RevisionedOfflineJournal _journal;
  final RevisionedActionRetryGuard? _retryGuard;
  final DateTime Function()? _now;

  Future<RevisionedProfileState?> bootstrap(String scope) async {
    final local = await _local.loadProfile(scope);
    try {
      final remote = await _cloud.load();
      if (remote == null) return local;
      if (local == null ||
          remote.revision >= local.revision &&
              local.syncStatus == RevisionedSyncStatus.synced) {
        await _local.saveProfile(scope, remote);
        return remote;
      }
      return local;
    } on Object {
      return local;
    }
  }

  Future<RevisionedSyncResult<RevisionedProfileState>> apply(
    String scope,
    ProfileMutation mutation,
  ) async {
    ProfileFieldOwnership.validatePatch(mutation.changedFields);
    if (scope.trim().isEmpty ||
        mutation.targetId != RevisionedProfileState.entityId ||
        mutation.mutationId.trim().isEmpty ||
        mutation.expectedRevision < 0) {
      throw const FormatException('invalid_profile_mutation');
    }
    final current = await _local.loadProfile(scope);
    if (current == null && mutation.expectedRevision != 0 ||
        current != null && current.revision != mutation.expectedRevision) {
      return _conflict(scope, mutation, current?.revision ?? 0);
    }
    final now = (_now ?? DateTime.now)().toUtc();
    final proposed = RevisionedProfileState(
      accountScopeId: scope,
      profile: mutation.profile,
      revision: current == null ? 1 : current.revision + 1,
      createdAt: current?.createdAt ?? now,
      updatedAt: now,
      lastMutationId: mutation.mutationId,
      syncStatus: RevisionedSyncStatus.queued,
      legacyExtensions: {
        ...?current?.legacyExtensions,
        ...mutation.profile.legacyExtensions,
      },
    );
    await _local.saveProfile(scope, proposed);
    await _journal.enqueue(
      accountScopeId: scope,
      domain: RevisionedSyncDomain.profile,
      mutation: mutation,
    );
    return _send(scope, mutation);
  }

  Future<RevisionedSyncResult<RevisionedProfileState>> retry(
    String scope,
    String mutationId,
  ) async {
    final journal = await _journal.load(
      accountScopeId: scope,
      domain: RevisionedSyncDomain.profile,
    );
    final found =
        journal.mutations.where((item) => item.mutationId == mutationId);
    if (found.isEmpty) {
      return const RevisionedSyncResult(
        status: RevisionedCloudWriteStatus.notFound,
      );
    }
    final mutation = found.single as ProfileMutation;
    final actionReference = mutation.actionReference;
    if (mutation.attempt >= RevisionedJournalState.maxAttempts ||
        actionReference != null &&
            (_retryGuard == null || !await _retryGuard(actionReference))) {
      return const RevisionedSyncResult(
        status: RevisionedCloudWriteStatus.unavailable,
      );
    }
    final retried = _withAttempt(mutation, mutation.attempt + 1);
    await _journal.replace(
      journal.copyWith(
        mutations: journal.mutations
            .map((item) => item.mutationId == mutationId ? retried : item)
            .toList(),
      ),
    );
    return _send(scope, retried as ProfileMutation);
  }

  Future<RevisionedSyncResult<RevisionedProfileState>> _send(
    String scope,
    ProfileMutation mutation,
  ) async {
    try {
      final result = mutation.expectedRevision == 0
          ? await _cloud.create(mutation, scope)
          : await _cloud.update(mutation, scope);
      if (result.status == RevisionedCloudWriteStatus.success ||
          result.status == RevisionedCloudWriteStatus.idempotent) {
        await _local.saveProfile(scope, result.value!);
        final journal = await _journal.load(
          accountScopeId: scope,
          domain: RevisionedSyncDomain.profile,
        );
        await _journal.replace(
          journal.copyWith(
            mutations: journal.mutations
                .where((item) => item.mutationId != mutation.mutationId)
                .toList(),
            receipts: [...journal.receipts, mutation.mutationId]
                .take(RevisionedJournalState.maxReceipts)
                .toList(),
          ),
        );
        return RevisionedSyncResult(status: result.status, value: result.value);
      }
      if (result.status == RevisionedCloudWriteStatus.revisionConflict ||
          result.status == RevisionedCloudWriteStatus.mutationConflict) {
        return _conflict(scope, mutation, result.value?.revision ?? 0);
      }
      return RevisionedSyncResult(status: result.status, value: result.value);
    } on Object {
      return const RevisionedSyncResult(
        status: RevisionedCloudWriteStatus.unavailable,
      );
    }
  }

  Future<RevisionedSyncResult<RevisionedProfileState>> _conflict(
    String scope,
    ProfileMutation mutation,
    int remoteRevision,
  ) async {
    final conflict = RevisionedConflict(
      conflictId: 'profile:${mutation.mutationId}',
      domain: RevisionedSyncDomain.profile,
      targetId: mutation.targetId,
      mutationId: mutation.mutationId,
      expectedRevision: mutation.expectedRevision,
      remoteRevision: remoteRevision,
      type: RevisionedConflictType.profileFieldConflict,
      createdAt: (_now ?? DateTime.now)().toUtc(),
      allowedResolutions: const [
        RevisionedConflictResolution.keepRemote,
        RevisionedConflictResolution.discardLocalMutation,
        RevisionedConflictResolution.requireUserResolution,
      ],
    );
    final journal = await _journal.load(
      accountScopeId: scope,
      domain: RevisionedSyncDomain.profile,
    );
    await _journal.replace(
      journal.copyWith(
        conflicts: [...journal.conflicts, conflict]
            .take(RevisionedJournalState.maxConflicts)
            .toList(),
      ),
    );
    return RevisionedSyncResult(
      status: RevisionedCloudWriteStatus.revisionConflict,
      conflict: conflict,
    );
  }
}
