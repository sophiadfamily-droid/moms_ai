import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/life_context/life_context_provenance.dart';
import 'package:moms_ai/models/life_context/memory_context.dart';
import 'package:moms_ai/models/memory_lifecycle_state.dart';
import 'package:moms_ai/models/memory_sync.dart';
import 'package:moms_ai/services/memory_library_service.dart';
import 'package:moms_ai/services/memory_sync_cloud_repository.dart';
import 'package:moms_ai/services/memory_sync_local_repository.dart';
import 'package:moms_ai/services/memory_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final now = DateTime.utc(2026, 7, 23, 12);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('bibliothèque classe, filtre et explique sans identifiant technique',
      () async {
    final harness = await _harness(now, [
      _memory(now, id: 'active'),
      _memory(now, id: 'proposal', state: MemoryLifecycleState.proposed),
      _memory(now, id: 'archive', state: MemoryLifecycleState.archived),
    ]);
    final snapshot = await harness.service.load();
    expect(snapshot.memories.map((item) => item.memoryId),
        ['proposal', 'active', 'archive']);
    expect(snapshot.filtered(MemoryLibraryFilter.historical), hasLength(1));
    final explanation = harness.service.explain(
      snapshot.memories[1],
      syncStatus: snapshot.syncStatus,
    );
    expect(explanation.origin, contains('conversation'));
    expect(explanation.planningUse, contains('jamais'));
    expect(explanation.origin, isNot(contains('active')));
  });

  test('correction garde ID, provenance et fait N vers N+1', () async {
    final harness = await _harness(now, [_memory(now)]);
    final result =
        await harness.service.correct(memoryId: 'memory-1', text: 'Corrigé');
    expect(result.status, MemoryLibraryActionStatus.synced);
    final memory = (await harness.service.load()).memories.single;
    expect(memory.memoryId, 'memory-1');
    expect(memory.memoryRevision, 2);
    expect(memory.provenance, LifeContextSourceType.memory);
    expect(memory.text, 'Corrigé');
    expect(memory.history.single.action, MemoryHistoryAction.corrected);
  });

  test('contenu vide, période invalide et domaine structuré sont refusés',
      () async {
    final harness = await _harness(now, [
      _memory(now),
      _memory(now, id: 'structured', structuredDomain: 'event'),
    ]);
    expect(
      (await harness.service.correct(memoryId: 'memory-1', text: '')).status,
      MemoryLibraryActionStatus.invalid,
    );
    expect(
      (await harness.service.correct(
        memoryId: 'memory-1',
        text: 'ok',
        validFrom: now,
        validUntil: now.subtract(const Duration(days: 1)),
      ))
          .status,
      MemoryLibraryActionStatus.invalid,
    );
    expect(
      (await harness.service.delete('structured')).status,
      MemoryLibraryActionStatus.protectedDomain,
    );
  });

  test('confirmation, rejet, report, archivage et restauration sont fermés',
      () async {
    final harness = await _harness(now, [
      _memory(now, id: 'confirm', state: MemoryLifecycleState.proposed),
      _memory(now, id: 'reject', state: MemoryLifecycleState.proposed),
      _memory(now, id: 'archive'),
    ]);
    expect((await harness.service.confirm('confirm')).status,
        MemoryLibraryActionStatus.synced);
    expect((await harness.service.reject('reject')).status,
        MemoryLibraryActionStatus.synced);
    expect((await harness.service.postpone('reject')).status,
        MemoryLibraryActionStatus.synced);
    expect((await harness.service.archive('archive')).status,
        MemoryLibraryActionStatus.synced);
    expect((await harness.service.restore('archive')).status,
        MemoryLibraryActionStatus.synced);
  });

  test('suppression crée un tombstone sans contenu ni cascade', () async {
    final harness = await _harness(now, [_memory(now)]);
    expect((await harness.service.delete('memory-1')).status,
        MemoryLibraryActionStatus.synced);
    final memory = (await harness.service.load()).memories.single;
    expect(memory.tombstone, isTrue);
    expect(memory.lifecycleStatus, MemoryLifecycleState.deleted);
    expect(memory.text, '[supprimé]');
    expect(memory.history, hasLength(1));
    expect(
      (await harness.service.restore('memory-1')).status,
      MemoryLibraryActionStatus.invalid,
    );
  });

  test('santé respecte le consentement mais la suppression reste autorisée',
      () async {
    final harness = await _harness(now, [_memory(now, health: true)]);
    expect(
      (await harness.service.correct(memoryId: 'memory-1', text: 'x')).status,
      MemoryLibraryActionStatus.blockedByPolicy,
    );
    expect((await harness.service.delete('memory-1')).status,
        MemoryLibraryActionStatus.synced);
  });

  test('suppression globale est renforcée, paginée et reprenable', () async {
    final harness = await _harness(
      now,
      List.generate(25, (index) => _memory(now, id: 'm-$index')),
    );
    expect(
      (await harness.service.deleteAllPage(confirmation: 'non')).status,
      MemoryLibraryActionStatus.invalid,
    );
    final first = await harness.service.deleteAllPage(
      confirmation: MemoryLibraryService.deleteAllConfirmation,
    );
    expect(first.status, MemoryLibraryActionStatus.synced);
    expect(first.nextCursor, isNotNull);
    final second = await harness.service.deleteAllPage(
      confirmation: MemoryLibraryService.deleteAllConfirmation,
      afterMemoryId: first.nextCursor,
    );
    expect(second.nextCursor, isNull);
    expect(
      (await harness.service.load()).memories.where((item) => !item.tombstone),
      isEmpty,
    );
  });

  test('historique est strictement borné', () {
    final memory = _memory(now).copyWith(
      history: List.generate(
        RevisionedMemory.maxHistoryEntries,
        (_) => MemoryHistoryEntry(
          action: MemoryHistoryAction.corrected,
          at: now,
          source: LifeContextSourceType.currentInstruction,
        ),
      ),
    );
    expect(memory.history, hasLength(50));
    expect(
      () => RevisionedMemory(
        memoryId: 'x',
        accountScopeId: 'account-a',
        memoryRevision: 1,
        lifecycleStatus: MemoryLifecycleState.active,
        confirmationStatus: MemoryConfirmationStatus.confirmed,
        provenance: LifeContextSourceType.memory,
        sensitivity: LifeContextSensitivity.standard,
        category: 'preference',
        isHealth: false,
        text: 'x',
        normalizedText: 'x',
        createdAt: now,
        updatedAt: now,
        lastMutationId: 'x',
        history: [...memory.history, memory.history.first],
      ),
      throwsA(isA<MemorySyncException>()),
    );
  });
}

final class _Harness {
  const _Harness(this.service);
  final MemoryLibraryService service;
}

Future<_Harness> _harness(
  DateTime now,
  List<RevisionedMemory> memories,
) async {
  final preferences = await SharedPreferences.getInstance();
  final cloud = _Cloud(memories: memories);
  final service = MemoryLibraryService(
    sync: MemorySyncService(
      local: MemorySyncLocalRepository(preferences),
      cloud: cloud,
      currentScope: () => 'account-a',
      now: () => now,
    ),
    currentScope: () => 'account-a',
    now: () => now,
  );
  return _Harness(service);
}

RevisionedMemory _memory(
  DateTime now, {
  String id = 'memory-1',
  MemoryLifecycleState state = MemoryLifecycleState.active,
  String? structuredDomain,
  bool health = false,
}) =>
    RevisionedMemory(
      memoryId: id,
      accountScopeId: 'account-a',
      memoryRevision: 1,
      lifecycleStatus: state,
      confirmationStatus: state == MemoryLifecycleState.proposed
          ? MemoryConfirmationStatus.unconfirmed
          : MemoryConfirmationStatus.confirmed,
      provenance: LifeContextSourceType.memory,
      sensitivity: health
          ? LifeContextSensitivity.sensitive
          : LifeContextSensitivity.standard,
      category: health ? 'health' : 'preference',
      isHealth: health,
      text: 'Souvenir $id',
      normalizedText: 'souvenir $id',
      createdAt: now,
      updatedAt: now,
      structuredDomain: structuredDomain,
      structuredReferenceId:
          structuredDomain == null ? null : 'structured-reference',
      lastMutationId: 'create-$id',
    );

final class _Cloud implements MemorySyncCloudRepository {
  _Cloud({List<RevisionedMemory> memories = const []})
      : memories = [...memories];

  final List<RevisionedMemory> memories;
  RevisionedMemoryPolicy? policy;

  @override
  Future<RevisionedMemoryPolicy?> readPolicy(String accountScopeId) async =>
      policy;

  @override
  Future<List<RevisionedMemory>> readMemoryPage(
    String accountScopeId, {
    int limit = 100,
    String? afterMemoryId,
  }) async {
    final sorted = [...memories]
      ..sort((left, right) => left.memoryId.compareTo(right.memoryId));
    return sorted
        .where((memory) =>
            afterMemoryId == null ||
            memory.memoryId.compareTo(afterMemoryId) > 0)
        .take(limit)
        .toList();
  }

  @override
  Future<RevisionedMemory?> readMemory(
    String accountScopeId,
    String memoryId,
  ) async =>
      memories.where((memory) => memory.memoryId == memoryId).firstOrNull;

  @override
  Future<MemoryCloudWriteResult> createMemory(
    RevisionedMemory memory,
  ) async {
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
    final index =
        memories.indexWhere((item) => item.memoryId == memory.memoryId);
    if (index < 0 || memories[index].memoryRevision != expectedRevision) {
      return const MemoryCloudWriteResult(
        MemoryCloudWriteStatus.revisionConflict,
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
  }) =>
      createPolicy(policy: policy);
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
