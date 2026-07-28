import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/life_context/life_context_provenance.dart';
import 'package:moms_ai/models/life_context/memory_context.dart';
import 'package:moms_ai/models/memory_lifecycle_state.dart';
import 'package:moms_ai/models/memory_policy.dart';
import 'package:moms_ai/models/memory_sync.dart';
import 'package:moms_ai/services/memory_sync_cloud_repository.dart';
import 'package:moms_ai/services/memory_sync_local_repository.dart';
import 'package:moms_ai/services/memory_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final now = DateTime.utc(2026, 7, 23, 12);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('nouvel appareil et réinstallation restaurent policy et memories',
      () async {
    final cloud = _Cloud(
      policy: _policy(now),
      memories: [_memory(now)],
    );
    final service = await _service(cloud, now: now);
    final first = await service.bootstrap();
    expect(first.restoredFromCloud, isTrue);
    expect(first.state.memories.single.memoryId, 'memory-1');
    expect(first.state.policy?.policyRevision, 1);

    final restarted = await service.bootstrap();
    expect(restarted.state.memories.single.memoryId, 'memory-1');
    expect(restarted.state.syncStatus, MemorySyncStatus.synced);
  });

  test('hors ligne conserve le dernier cache valide', () async {
    final cloud = _Cloud(
      policy: _policy(now),
      memories: [_memory(now)],
    );
    final service = await _service(cloud, now: now);
    await service.bootstrap();
    cloud.unavailable = true;
    final result = await service.bootstrap();
    expect(result.state.memories, hasLength(1));
    expect(result.state.syncStatus, MemorySyncStatus.unavailable);
  });

  test('bootstrap reprend une mutation durable après redémarrage', () async {
    final local = await _local();
    await local.save(
      MemorySyncLocalState(
        accountScopeId: 'account-a',
        policy: _policy(now),
        memories: [_memory(now, mutationId: 'memory-create')],
        mutations: [
          _mutation(
            now,
            id: 'memory-1',
            mutationId: 'memory-create',
          ),
        ],
        syncStatus: MemorySyncStatus.pending,
      ),
    );
    final cloud = _Cloud(policy: _policy(now));
    final restarted = MemorySyncService(
      local: local,
      cloud: cloud,
      currentScope: () => 'account-a',
      now: () => now,
    );

    final result = await restarted.bootstrap();
    final second = await restarted.bootstrap();

    expect(result.state.mutations, isEmpty);
    expect(result.state.syncStatus, MemorySyncStatus.synced);
    expect(second.state.mutations, isEmpty);
    expect(cloud.memories, hasLength(1));
    expect(cloud.memoryWrites, 1);
  });

  test('politique est révisionnée et mutation idempotente', () async {
    final cloud = _Cloud();
    final service = await _service(cloud, now: now);
    await service.queuePolicy(
      policy: MemoryPolicy.restrictiveDefault(
        accountScopeId: 'account-a',
        changedAt: now,
      ),
      mutationId: 'policy-create',
    );
    var state = await service.synchronize();
    expect(state.syncStatus, MemorySyncStatus.synced);
    expect(cloud.policy?.policyRevision, 1);

    state = await service.synchronize();
    expect(state.syncStatus, MemorySyncStatus.synced);
    expect(cloud.policy?.policyRevision, 1);
  });

  test('pause et santé désactivée bloquent les mutations en attente', () async {
    final cloud = _Cloud(policy: _policy(now, paused: true));
    final local = await _local();
    await local.save(
      MemorySyncLocalState(
        accountScopeId: 'account-a',
        policy: _policy(now, paused: true),
        memories: [
          _memory(now, mutationId: 'general'),
          _memory(now, id: 'health', mutationId: 'health', health: true),
        ],
        mutations: [
          _mutation(now, id: 'memory-1', mutationId: 'general'),
          _mutation(
            now,
            id: 'health',
            mutationId: 'health',
            health: true,
          ),
        ],
      ),
    );
    final service = MemorySyncService(
      local: local,
      cloud: cloud,
      currentScope: () => 'account-a',
      now: () => now,
    );
    final state = await service.synchronize();
    expect(
      state.mutations.map((item) => item.state).toSet(),
      {MemoryMutationState.blockedByPolicy},
    );
    expect(cloud.memoryWrites, 0);
  });

  test('révision obsolète devient conflit explicite sans overwrite', () async {
    final cloud = _Cloud(memories: [_memory(now, revision: 2)]);
    final local = await _local();
    await local.save(
      MemorySyncLocalState(
        accountScopeId: 'account-a',
        policy: _policy(now),
        memories: [_memory(now, revision: 2, mutationId: 'update-local')],
        mutations: [
          _mutation(
            now,
            id: 'memory-1',
            mutationId: 'update-local',
            expectedRevision: 1,
            type: MemoryMutationType.updateMemory,
          ),
        ],
      ),
    );
    final service = MemorySyncService(
      local: local,
      cloud: cloud,
      currentScope: () => 'account-a',
      now: () => now,
    );
    final state = await service.synchronize();
    expect(state.syncStatus, MemorySyncStatus.conflict);
    expect(state.conflicts.single.type, MemoryConflictType.revisionConflict);
    expect(cloud.memories.single.lastMutationId, 'remote');
  });

  test('retry est exponentiel, borné et sans sleep réel', () async {
    final retry = const MemoryRetryPolicy(
      maxAttempts: 5,
      baseDelay: Duration(seconds: 5),
      maxDelay: Duration(seconds: 30),
    );
    expect(retry.delayFor(1), const Duration(seconds: 5));
    expect(retry.delayFor(4), const Duration(seconds: 30));
    expect(() => retry.delayFor(6), throwsA(isA<MemorySyncException>()));
  });

  test('expiration est déterministe à la limite et ne supprime rien', () {
    final memory = _memory(now).copyWith(
      lifecycleStatus: MemoryLifecycleState.expired,
    );
    expect(memory.isExpiredAt(now), isTrue);
    expect(memory.tombstone, isFalse);
  });

  test('expiration active passe par un observateur avant la file M.3',
      () async {
    final local = await _local();
    await local.save(
      MemorySyncLocalState(
        accountScopeId: 'account-a',
        memories: [
          _memory(now).copyWith(expiresAt: now),
        ],
      ),
    );
    var observed = false;
    var dispatched = false;
    final service = MemorySyncService(
      local: local,
      cloud: _Cloud(),
      currentScope: () => 'account-a',
      now: () => now,
      expirationObserver: ({
        required current,
        required updated,
        required mutation,
        required dispatch,
      }) async {
        observed = true;
        expect(dispatched, isFalse);
        expect(mutation.mutationId, 'expire:memory-1:1');
        expect(updated.lifecycleStatus, MemoryLifecycleState.expired);
        await dispatch();
        dispatched = true;
      },
    );
    final state = await service.materializeExpirations();
    expect(observed, isTrue);
    expect(dispatched, isTrue);
    expect(state.mutations.single.type, MemoryMutationType.expireMemory);
  });

  test('file, reçus, cache et comptes sont strictement bornés', () async {
    expect(
      () => MemorySyncLocalState(
        accountScopeId: 'account-a',
        mutations: List.generate(
          MemorySyncLocalState.maxMutations + 1,
          (index) => _mutation(
            now,
            id: 'memory-$index',
            mutationId: 'mutation-$index',
          ),
        ),
      ),
      throwsA(isA<MemorySyncException>()),
    );
    final local = await _local();
    await local.save(MemorySyncLocalState(accountScopeId: 'account-a'));
    expect(await local.load('account-b'), isNull);
  });

  test('pagination est bornée et ordonnée', () async {
    final cloud = _Cloud(
      memories: List.generate(
        120,
        (index) => _memory(now, id: 'm-${index.toString().padLeft(3, '0')}'),
      ),
    );
    final page = await cloud.readMemoryPage('account-a', limit: 100);
    expect(page, hasLength(100));
    expect(page.first.memoryId, 'm-000');
    expect(page.last.memoryId, 'm-099');
  });
}

Future<MemorySyncLocalRepository> _local() async =>
    MemorySyncLocalRepository(await SharedPreferences.getInstance());

Future<MemorySyncService> _service(_Cloud cloud,
        {required DateTime now}) async =>
    MemorySyncService(
      local: await _local(),
      cloud: cloud,
      currentScope: () => 'account-a',
      now: () => now,
    );

RevisionedMemoryPolicy _policy(DateTime now, {bool paused = false}) =>
    RevisionedMemoryPolicy(
      policy: MemoryPolicy(
        accountScopeId: 'account-a',
        generalMode:
            paused ? MemoryGeneralMode.paused : MemoryGeneralMode.askEveryTime,
        healthMode: MemoryHealthMode.disabled,
        healthConsentGranted: false,
        changedAt: now,
        changeSource: MemoryPolicyChangeSource.explicitUserSetting,
      ),
      policyRevision: 1,
      createdAt: now,
      updatedAt: now,
      lastMutationId: 'policy-remote',
    );

RevisionedMemory _memory(
  DateTime now, {
  String id = 'memory-1',
  int revision = 1,
  String mutationId = 'remote',
  bool health = false,
}) =>
    RevisionedMemory(
      memoryId: id,
      accountScopeId: 'account-a',
      memoryRevision: revision,
      lifecycleStatus: MemoryLifecycleState.active,
      confirmationStatus: MemoryConfirmationStatus.confirmed,
      provenance: LifeContextSourceType.memory,
      sensitivity: health
          ? LifeContextSensitivity.sensitive
          : LifeContextSensitivity.standard,
      category: health ? 'health' : 'preference',
      isHealth: health,
      text: 'bounded',
      normalizedText: 'bounded',
      createdAt: now,
      updatedAt: now,
      lastMutationId: mutationId,
    );

MemorySyncMutation _mutation(
  DateTime now, {
  required String id,
  required String mutationId,
  int expectedRevision = 0,
  bool health = false,
  MemoryMutationType type = MemoryMutationType.createMemory,
}) =>
    MemorySyncMutation(
      mutationId: mutationId,
      accountScopeId: 'account-a',
      type: type,
      targetId: id,
      expectedRevision: expectedRevision,
      createdAt: now,
      observedGeneralMode: MemoryGeneralMode.askEveryTime,
      observedHealthMode: MemoryHealthMode.disabled,
      isHealth: health,
      provenance: LifeContextSourceType.memory,
    );

final class _Cloud implements MemorySyncCloudRepository {
  _Cloud({
    this.policy,
    List<RevisionedMemory> memories = const [],
  }) : memories = [...memories]
          ..sort((a, b) => a.memoryId.compareTo(b.memoryId));

  RevisionedMemoryPolicy? policy;
  final List<RevisionedMemory> memories;
  bool unavailable = false;
  int memoryWrites = 0;

  @override
  Future<RevisionedMemoryPolicy?> readPolicy(String scope) async {
    if (unavailable) throw const MemorySyncException('unavailable');
    return policy;
  }

  @override
  Future<List<RevisionedMemory>> readMemoryPage(
    String scope, {
    int limit = 50,
    String? afterMemoryId,
  }) async {
    if (unavailable) throw const MemorySyncException('unavailable');
    final start = afterMemoryId == null
        ? 0
        : memories.indexWhere((item) => item.memoryId == afterMemoryId) + 1;
    return memories.skip(start).take(limit).toList();
  }

  @override
  Future<RevisionedMemory?> readMemory(String scope, String memoryId) async =>
      memories.where((item) => item.memoryId == memoryId).firstOrNull;

  @override
  Future<MemoryCloudWriteResult> createMemory(RevisionedMemory memory) async {
    memoryWrites++;
    final existing =
        memories.where((item) => item.memoryId == memory.memoryId).firstOrNull;
    if (existing != null) {
      return existing.lastMutationId == memory.lastMutationId
          ? MemoryCloudWriteResult(
              MemoryCloudWriteStatus.idempotentSuccess,
              memory: existing,
            )
          : const MemoryCloudWriteResult(
              MemoryCloudWriteStatus.revisionConflict,
            );
    }
    memories.add(memory);
    return MemoryCloudWriteResult(
      MemoryCloudWriteStatus.success,
      memory: memory,
    );
  }

  @override
  Future<MemoryCloudWriteResult> updateMemory({
    required RevisionedMemory memory,
    required int expectedRevision,
  }) async {
    memoryWrites++;
    final index =
        memories.indexWhere((item) => item.memoryId == memory.memoryId);
    if (index < 0) {
      return const MemoryCloudWriteResult(MemoryCloudWriteStatus.notFound);
    }
    if (memories[index].memoryRevision != expectedRevision) {
      return MemoryCloudWriteResult(
        MemoryCloudWriteStatus.revisionConflict,
        memory: memories[index],
      );
    }
    memories[index] = memory;
    return MemoryCloudWriteResult(
      MemoryCloudWriteStatus.success,
      memory: memory,
    );
  }

  @override
  Future<MemoryCloudWriteResult> createPolicy({
    required RevisionedMemoryPolicy policy,
  }) async {
    if (this.policy != null) {
      return const MemoryCloudWriteResult(
        MemoryCloudWriteStatus.revisionConflict,
      );
    }
    this.policy = policy;
    return MemoryCloudWriteResult(
      MemoryCloudWriteStatus.success,
      policy: policy,
    );
  }

  @override
  Future<MemoryCloudWriteResult> updatePolicy({
    required RevisionedMemoryPolicy policy,
    required int expectedRevision,
  }) async {
    if (this.policy?.policyRevision != expectedRevision) {
      return MemoryCloudWriteResult(
        MemoryCloudWriteStatus.revisionConflict,
        policy: this.policy,
      );
    }
    this.policy = policy;
    return MemoryCloudWriteResult(
      MemoryCloudWriteStatus.success,
      policy: policy,
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
