import '../models/life_context/life_context_provenance.dart';
import '../models/life_context/memory_context.dart';
import '../models/memory_lifecycle_state.dart';
import '../models/memory_policy.dart';
import '../models/memory_sync.dart';
import 'memory_sync_cloud_repository.dart';
import 'memory_sync_local_repository.dart';

final class MemoryRetryPolicy {
  const MemoryRetryPolicy({
    this.maxAttempts = 5,
    this.baseDelay = const Duration(seconds: 5),
    this.maxDelay = const Duration(minutes: 5),
  });

  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;

  Duration delayFor(int attempt) {
    if (attempt < 1 || attempt > maxAttempts) {
      throw const MemorySyncException('invalid_memory_retry_attempt');
    }
    final multiplier = 1 << (attempt - 1);
    final milliseconds = baseDelay.inMilliseconds * multiplier;
    return Duration(
      milliseconds: milliseconds > maxDelay.inMilliseconds
          ? maxDelay.inMilliseconds
          : milliseconds,
    );
  }
}

final class MemoryBootstrapResult {
  const MemoryBootstrapResult(this.state, {this.restoredFromCloud = false});
  final MemorySyncLocalState state;
  final bool restoredFromCloud;
}

typedef MemoryExpirationObserver = Future<void> Function({
  required RevisionedMemory current,
  required RevisionedMemory updated,
  required MemorySyncMutation mutation,
  required Future<void> Function() dispatch,
});

final class MemorySyncService {
  MemorySyncService({
    required MemorySyncLocalRepository local,
    required MemorySyncCloudRepository cloud,
    required String? Function() currentScope,
    this.now = DateTime.now,
    this.retryPolicy = const MemoryRetryPolicy(),
    this.expirationObserver,
  })  : _local = local,
        _cloud = cloud,
        _currentScope = currentScope;

  static const maximumBootstrapItems = 500;
  static const pageSize = 100;

  final MemorySyncLocalRepository _local;
  final MemorySyncCloudRepository _cloud;
  final String? Function() _currentScope;
  final DateTime Function() now;
  final MemoryRetryPolicy retryPolicy;
  final MemoryExpirationObserver? expirationObserver;

  Future<MemoryBootstrapResult> bootstrap() async {
    final scope = _scope();
    final local = await _local.load(scope);
    try {
      final remotePolicy = await _cloud.readPolicy(scope);
      final memories = <RevisionedMemory>[];
      String? cursor;
      while (memories.length < maximumBootstrapItems) {
        final page = await _cloud.readMemoryPage(
          scope,
          limit: pageSize,
          afterMemoryId: cursor,
        );
        memories.addAll(page);
        if (page.length < pageSize) break;
        cursor = page.last.memoryId;
      }
      final pendingTargets = (local?.mutations ?? const <MemorySyncMutation>[])
          .map((mutation) => mutation.targetId)
          .toSet();
      final memoriesById = {
        for (final memory in memories) memory.memoryId: memory,
      };
      for (final memory in local?.memories ?? const <RevisionedMemory>[]) {
        if (pendingTargets.contains(memory.memoryId)) {
          memoriesById[memory.memoryId] = memory;
        }
      }
      final mergedMemories = memoriesById.values.toList()
        ..sort((left, right) => left.memoryId.compareTo(right.memoryId));
      var policy = _safePolicy(local?.policy, remotePolicy, scope);
      if (pendingTargets.contains('memoryPolicy') && local?.policy != null) {
        policy = local!.policy;
      }
      final state = MemorySyncLocalState(
        accountScopeId: scope,
        policy: policy,
        memories: mergedMemories,
        mutations: local?.mutations ?? const [],
        conflicts: local?.conflicts ?? const [],
        receipts: local?.receipts ?? const [],
        syncStatus: MemorySyncStatus.synced,
        lastBootstrapAt: now().toUtc(),
      );
      await _local.save(state);
      return MemoryBootstrapResult(
        state,
        restoredFromCloud: local == null && mergedMemories.isNotEmpty,
      );
    } on Object {
      if (local != null) {
        return MemoryBootstrapResult(
          local.copyWith(syncStatus: MemorySyncStatus.unavailable),
        );
      }
      final state = MemorySyncLocalState(
        accountScopeId: scope,
        syncStatus: MemorySyncStatus.unavailable,
      );
      return MemoryBootstrapResult(state);
    }
  }

  Future<MemorySyncLocalState> enqueue(MemorySyncMutation mutation) async {
    final scope = _scope();
    if (mutation.accountScopeId != scope) {
      throw const MemorySyncException('memory_account_mismatch');
    }
    final state =
        await _local.load(scope) ?? MemorySyncLocalState(accountScopeId: scope);
    return _local.enqueue(state, mutation);
  }

  Future<MemorySyncLocalState> queueMemoryChange({
    required RevisionedMemory current,
    required RevisionedMemory updated,
    required MemoryMutationType type,
    required String mutationId,
    Map<String, Object?> patch = const {},
  }) async {
    final scope = _scope();
    if (current.accountScopeId != scope ||
        updated.accountScopeId != scope ||
        current.memoryId != updated.memoryId ||
        updated.memoryRevision != current.memoryRevision + 1 ||
        updated.lastMutationId != mutationId) {
      throw const MemorySyncException('invalid_memory_change');
    }
    var state =
        await _local.load(scope) ?? MemorySyncLocalState(accountScopeId: scope);
    final index =
        state.memories.indexWhere((item) => item.memoryId == current.memoryId);
    if (index < 0 ||
        state.memories[index].memoryRevision != current.memoryRevision) {
      throw const MemorySyncException('memory_revision_conflict');
    }
    final memories = [...state.memories]..[index] = updated;
    state = state.copyWith(
      memories: memories,
      syncStatus: MemorySyncStatus.pending,
    );
    await _local.save(state);
    return _local.enqueue(
      state,
      MemorySyncMutation(
        mutationId: mutationId,
        accountScopeId: scope,
        type: type,
        targetId: current.memoryId,
        expectedRevision: current.memoryRevision,
        createdAt: now().toUtc(),
        observedGeneralMode:
            state.policy?.policy.generalMode ?? MemoryGeneralMode.askEveryTime,
        observedHealthMode:
            state.policy?.policy.healthMode ?? MemoryHealthMode.disabled,
        isHealth: current.isHealth,
        provenance: LifeContextSourceType.memory,
        patch: patch,
      ),
    );
  }

  Future<MemorySyncLocalState> queuePolicy({
    required MemoryPolicy policy,
    required String mutationId,
  }) async {
    final scope = _scope();
    if (policy.accountScopeId != scope) {
      throw const MemorySyncException('memory_account_mismatch');
    }
    final state =
        await _local.load(scope) ?? MemorySyncLocalState(accountScopeId: scope);
    final previous = state.policy;
    final revision = (previous?.policyRevision ?? 0) + 1;
    final timestamp = now().toUtc();
    final revisioned = RevisionedMemoryPolicy(
      policy: policy,
      policyRevision: revision,
      createdAt: previous?.createdAt ?? timestamp,
      updatedAt: timestamp,
      explicitHealthConsentAt: policy.healthConsentGranted
          ? previous?.explicitHealthConsentAt ?? timestamp
          : null,
      lastMutationId: mutationId,
    );
    final withPolicy = state.copyWith(
      policy: revisioned,
      syncStatus: MemorySyncStatus.pending,
    );
    await _local.save(withPolicy);
    return _local.enqueue(
      withPolicy,
      MemorySyncMutation(
        mutationId: mutationId,
        accountScopeId: scope,
        type: MemoryMutationType.changePolicy,
        targetId: 'memoryPolicy',
        expectedRevision: previous?.policyRevision ?? 0,
        createdAt: timestamp,
        observedGeneralMode: policy.generalMode,
        observedHealthMode: policy.healthMode,
        isHealth: false,
        provenance: LifeContextSourceType.profile,
      ),
    );
  }

  Future<MemorySyncLocalState> materializeExpirations() async {
    final scope = _scope();
    var state =
        await _local.load(scope) ?? MemorySyncLocalState(accountScopeId: scope);
    final timestamp = now().toUtc();
    final memories = [...state.memories];
    for (var index = 0; index < memories.length; index++) {
      final memory = memories[index];
      if (!memory.isExpiredAt(timestamp) ||
          memory.lifecycleStatus == MemoryLifecycleState.expired ||
          memory.tombstone) {
        continue;
      }
      final mutationId = 'expire:${memory.memoryId}:${memory.memoryRevision}';
      memories[index] = memory.copyWith(
        memoryRevision: memory.memoryRevision + 1,
        lifecycleStatus: MemoryLifecycleState.expired,
        confirmationStatus: MemoryConfirmationStatus.obsolete,
        updatedAt: timestamp,
        lastMutationId: mutationId,
        history: ([
          ...memory.history,
          MemoryHistoryEntry(
            action: MemoryHistoryAction.expired,
            at: timestamp,
            source: LifeContextSourceType.memory,
          ),
        ].reversed.take(RevisionedMemory.maxHistoryEntries).toList()
          ..sort((left, right) => left.at.compareTo(right.at))),
      );
      final updated = memories[index];
      final mutation = MemorySyncMutation(
        mutationId: mutationId,
        accountScopeId: scope,
        type: MemoryMutationType.expireMemory,
        targetId: memory.memoryId,
        expectedRevision: memory.memoryRevision,
        createdAt: timestamp,
        observedGeneralMode:
            state.policy?.policy.generalMode ?? MemoryGeneralMode.askEveryTime,
        observedHealthMode:
            state.policy?.policy.healthMode ?? MemoryHealthMode.disabled,
        isHealth: memory.isHealth,
        provenance: LifeContextSourceType.memory,
      );
      Future<void> dispatch() async {
        state = state.copyWith(memories: memories);
        await _local.save(state);
        state = await _local.enqueue(state, mutation);
      }

      final observer = expirationObserver;
      if (observer == null) {
        await dispatch();
      } else {
        await observer(
          current: memory,
          updated: updated,
          mutation: mutation,
          dispatch: dispatch,
        );
      }
    }
    return state;
  }

  Future<MemorySyncLocalState> synchronize() async {
    final scope = _scope();
    var state =
        await _local.load(scope) ?? MemorySyncLocalState(accountScopeId: scope);
    final policy = state.policy?.policy ??
        MemoryPolicy.restrictiveDefault(
          accountScopeId: scope,
          changedAt: now().toUtc(),
        );
    final queue = [...state.mutations];
    final receipts = [...state.receipts];
    final conflicts = [...state.conflicts];

    for (var index = 0; index < queue.length; index++) {
      var mutation = queue[index];
      if (!_eligible(mutation, policy)) {
        queue[index] = mutation.copyWith(
          state: MemoryMutationState.blockedByPolicy,
        );
        continue;
      }
      if (mutation.nextRetryAt != null &&
          now().toUtc().isBefore(mutation.nextRetryAt!)) {
        continue;
      }
      mutation = mutation.copyWith(
        attempt: mutation.attempt + 1,
        state: MemoryMutationState.sending,
      );
      queue[index] = mutation;
      await _local.save(state.copyWith(mutations: queue));
      final result = await _send(state, mutation);
      switch (result.status) {
        case MemoryCloudWriteStatus.success:
        case MemoryCloudWriteStatus.idempotentSuccess:
          queue[index] = mutation.copyWith(
            state: MemoryMutationState.completed,
          );
          receipts.add(mutation.mutationId);
        case MemoryCloudWriteStatus.revisionConflict:
        case MemoryCloudWriteStatus.mutationMismatch:
          queue[index] = mutation.copyWith(
            state: MemoryMutationState.blockedByConflict,
          );
          conflicts.add(
            MemorySyncConflict(
              id: mutation.mutationId,
              targetId: mutation.targetId,
              mutationId: mutation.mutationId,
              expectedRevision: mutation.expectedRevision,
              remoteRevision: result.memory?.memoryRevision ??
                  result.policy?.policyRevision,
              type: mutation.type == MemoryMutationType.changePolicy
                  ? MemoryConflictType.policyConflict
                  : MemoryConflictType.revisionConflict,
              createdAt: now().toUtc(),
            ),
          );
        case MemoryCloudWriteStatus.unavailable:
          queue[index] = mutation.attempt >= retryPolicy.maxAttempts
              ? mutation.copyWith(state: MemoryMutationState.abandoned)
              : mutation.copyWith(
                  state: MemoryMutationState.retryScheduled,
                  nextRetryAt: now().toUtc().add(
                        retryPolicy.delayFor(mutation.attempt),
                      ),
                );
        case MemoryCloudWriteStatus.notFound:
        case MemoryCloudWriteStatus.scopeMismatch:
        case MemoryCloudWriteStatus.invalid:
          queue[index] = mutation.copyWith(
            state: MemoryMutationState.abandoned,
          );
      }
    }

    final retained = queue
        .where((item) => item.state != MemoryMutationState.completed)
        .take(MemorySyncLocalState.maxMutations)
        .toList();
    state = state.copyWith(
      mutations: retained,
      conflicts: conflicts.take(MemorySyncLocalState.maxConflicts).toList(),
      receipts: receipts.reversed
          .take(MemorySyncLocalState.maxReceipts)
          .toList()
          .reversed
          .toList(),
      syncStatus: conflicts.isNotEmpty
          ? MemorySyncStatus.conflict
          : retained.isEmpty
              ? MemorySyncStatus.synced
              : MemorySyncStatus.pending,
    );
    await _local.save(state);
    return state;
  }

  Future<MemorySyncLocalState> resolveConflict({
    required String conflictId,
    required MemoryConflictResolution resolution,
  }) async {
    final scope = _scope();
    var state =
        await _local.load(scope) ?? MemorySyncLocalState(accountScopeId: scope);
    final conflict =
        state.conflicts.where((item) => item.id == conflictId).firstOrNull;
    if (conflict == null) {
      throw const MemorySyncException('memory_conflict_not_found');
    }
    final conflicts =
        state.conflicts.where((item) => item.id != conflictId).toList();
    final mutations = [...state.mutations];
    final memories = [...state.memories];
    final index = mutations.indexWhere(
      (item) => item.mutationId == conflict.mutationId,
    );
    if (index >= 0) {
      switch (resolution) {
        case MemoryConflictResolution.keepRemote:
        case MemoryConflictResolution.discardLocalMutation:
        case MemoryConflictResolution.cancelExpiredMutation:
          mutations.removeAt(index);
        case MemoryConflictResolution.retryAgainstLatest:
          if (mutations[index].type == MemoryMutationType.changePolicy) {
            throw const MemorySyncException(
              'memory_policy_conflict_requires_user_resolution',
            );
          }
          final remote = await _cloud.readMemory(
            scope,
            mutations[index].targetId,
          );
          if (remote == null || remote.tombstone || remote.isExpiredAt(now())) {
            throw const MemorySyncException(
              'memory_conflict_requires_user_resolution',
            );
          }
          mutations[index] = mutations[index].copyWith(
            expectedRevision: remote.memoryRevision,
            state: MemoryMutationState.queued,
            clearNextRetry: true,
          );
          final memoryIndex = memories.indexWhere(
            (item) => item.memoryId == remote.memoryId,
          );
          if (memoryIndex < 0) {
            throw const MemorySyncException('memory_local_target_not_found');
          }
          memories[memoryIndex] = memories[memoryIndex].copyWith(
            memoryRevision: remote.memoryRevision + 1,
          );
        case MemoryConflictResolution.requireUserResolution:
        case MemoryConflictResolution.applyNonConflictingPatch:
          throw const MemorySyncException(
            'memory_conflict_requires_user_resolution',
          );
      }
    }
    state = state.copyWith(
      conflicts: conflicts,
      mutations: mutations,
      memories: memories,
      syncStatus: mutations.isEmpty
          ? MemorySyncStatus.synced
          : MemorySyncStatus.pending,
    );
    await _local.save(state);
    if (resolution == MemoryConflictResolution.retryAgainstLatest) {
      return synchronize();
    }
    return state;
  }

  Future<MemoryCloudWriteResult> _send(
    MemorySyncLocalState state,
    MemorySyncMutation mutation,
  ) async {
    if (mutation.type == MemoryMutationType.changePolicy) {
      final policy = state.policy;
      if (policy == null || policy.lastMutationId != mutation.mutationId) {
        return const MemoryCloudWriteResult(MemoryCloudWriteStatus.invalid);
      }
      return mutation.expectedRevision == 0
          ? _cloud.createPolicy(policy: policy)
          : _cloud.updatePolicy(
              policy: policy,
              expectedRevision: mutation.expectedRevision,
            );
    }
    final memory = state.memories
        .where((item) => item.memoryId == mutation.targetId)
        .firstOrNull;
    if (memory == null || memory.lastMutationId != mutation.mutationId) {
      return const MemoryCloudWriteResult(MemoryCloudWriteStatus.invalid);
    }
    return mutation.type == MemoryMutationType.createMemory
        ? _cloud.createMemory(memory)
        : _cloud.updateMemory(
            memory: memory,
            expectedRevision: mutation.expectedRevision,
          );
  }

  bool _eligible(MemorySyncMutation mutation, MemoryPolicy policy) {
    if (mutation.type == MemoryMutationType.changePolicy) return true;
    if (policy.generalMode == MemoryGeneralMode.paused &&
        mutation.type == MemoryMutationType.createMemory) {
      return false;
    }
    if (mutation.isHealth &&
        mutation.type != MemoryMutationType.deleteMemory &&
        mutation.type != MemoryMutationType.archiveMemory &&
        mutation.type != MemoryMutationType.rejectMemory &&
        (policy.healthMode == MemoryHealthMode.disabled ||
            (policy.healthMode == MemoryHealthMode.enabled &&
                !policy.healthConsentGranted))) {
      return false;
    }
    if (mutation.observedGeneralMode == MemoryGeneralMode.askEveryTime &&
        policy.generalMode == MemoryGeneralMode.automatic &&
        mutation.type == MemoryMutationType.createMemory) {
      return false;
    }
    return true;
  }

  RevisionedMemoryPolicy? _safePolicy(
    RevisionedMemoryPolicy? local,
    RevisionedMemoryPolicy? remote,
    String scope,
  ) {
    if (remote == null) return local;
    if (local == null || remote.policyRevision >= local.policyRevision) {
      return remote;
    }
    // A stale conflict stays restrictive locally and never rewrites cloud.
    return RevisionedMemoryPolicy(
      policy: MemoryPolicy.restrictiveDefault(
        accountScopeId: scope,
        changedAt: now().toUtc(),
      ),
      policyRevision: remote.policyRevision,
      createdAt: remote.createdAt,
      updatedAt: remote.updatedAt,
      lastMutationId: remote.lastMutationId,
    );
  }

  String _scope() {
    final scope = _currentScope()?.trim() ?? '';
    if (scope.isEmpty) {
      throw const MemorySyncException('memory_sync_unauthenticated');
    }
    return scope;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
