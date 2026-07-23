import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/revisioned_domain_models.dart';
import 'package:moms_ai/models/revisioned_sync_protocol.dart';
import 'package:moms_ai/models/shopping_item_model.dart';
import 'package:moms_ai/models/task_model.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/services/revisioned_domain_sync_service.dart';
import 'package:moms_ai/services/revisioned_offline_journal.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const scope = 'account-a';
  final instant = DateTime.utc(2026, 7, 23, 10);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Y.1 common revision protocol', () {
    test('Task create starts at revision one and retry is idempotent',
        () async {
      final cloud = _TaskCloud();
      final service = TaskRevisionSyncService(
        cloud: cloud,
        now: () => instant,
      );
      final mutation = _taskMutation(
        id: 'task-1',
        mutationId: 'mutation-1',
        expectedRevision: 0,
        type: TaskMutationType.createTask,
        instant: instant,
      );

      final first = await service.apply(scope, mutation);
      final retry = await cloud.create(mutation, scope);

      expect(first.isRealSuccess, isTrue);
      expect(first.value?.revision, 1);
      expect(retry.status, RevisionedCloudWriteStatus.idempotent);
      expect(cloud.values.single.lastMutationId, 'mutation-1');
    });

    test('Task update is exactly N to N+1 and stale update conflicts',
        () async {
      final cloud = _TaskCloud();
      final service = TaskRevisionSyncService(
        cloud: cloud,
        now: () => instant,
      );
      await service.apply(
        scope,
        _taskMutation(
          id: 'task-1',
          mutationId: 'create',
          expectedRevision: 0,
          type: TaskMutationType.createTask,
          instant: instant,
        ),
      );
      final update = _taskMutation(
        id: 'task-1',
        mutationId: 'update',
        expectedRevision: 1,
        type: TaskMutationType.completeTask,
        instant: instant,
        done: true,
      );

      final result = await service.apply(scope, update);
      final stale = await cloud.update(
        _taskMutation(
          id: 'task-1',
          mutationId: 'stale',
          expectedRevision: 1,
          type: TaskMutationType.updateTask,
          instant: instant,
        ),
        scope,
      );

      expect(result.value?.revision, 2);
      expect(result.value?.task.isDone, isTrue);
      expect(stale.status, RevisionedCloudWriteStatus.revisionConflict);
    });

    test('Task tombstone prevents an older mutation from resurrecting it',
        () async {
      final cloud = _TaskCloud();
      final service = TaskRevisionSyncService(
        cloud: cloud,
        now: () => instant,
      );
      await service.apply(
        scope,
        _taskMutation(
          id: 'task-1',
          mutationId: 'create',
          expectedRevision: 0,
          type: TaskMutationType.createTask,
          instant: instant,
        ),
      );
      await service.apply(
        scope,
        _taskMutation(
          id: 'task-1',
          mutationId: 'delete',
          expectedRevision: 1,
          type: TaskMutationType.deleteTask,
          instant: instant,
        ),
      );

      final stale = await cloud.update(
        _taskMutation(
          id: 'task-1',
          mutationId: 'old-offline',
          expectedRevision: 1,
          type: TaskMutationType.updateTask,
          instant: instant,
        ),
        scope,
      );

      expect(cloud.values.single.isTombstone, isTrue);
      expect(stale.status, RevisionedCloudWriteStatus.revisionConflict);
    });

    test('Shopping retry cannot double-add and deletion cannot resurrect',
        () async {
      final cloud = _ShoppingCloud();
      final service = ShoppingRevisionSyncService(
        cloud: cloud,
        now: () => instant,
      );
      final add = _shoppingMutation(
        mutationId: 'add',
        expectedRevision: 0,
        type: ShoppingMutationType.addItem,
        instant: instant,
      );
      await service.apply(scope, add);
      expect((await cloud.create(add, scope)).status,
          RevisionedCloudWriteStatus.idempotent);
      await service.apply(
        scope,
        _shoppingMutation(
          mutationId: 'remove',
          expectedRevision: 1,
          type: ShoppingMutationType.removeItem,
          instant: instant,
        ),
      );
      final stale = await cloud.update(
        _shoppingMutation(
          mutationId: 'stale',
          expectedRevision: 1,
          type: ShoppingMutationType.updateItem,
          instant: instant,
        ),
        scope,
      );

      expect(cloud.values.single.isTombstone, isTrue);
      expect(stale.status, RevisionedCloudWriteStatus.revisionConflict);
    });

    test('Profile rejects HumanModel-owned fields', () {
      expect(
        () => ProfileMutation(
          mutationId: 'profile-1',
          targetId: RevisionedProfileState.entityId,
          expectedRevision: 1,
          createdAt: instant,
          attempt: 0,
          nextRetryAt: null,
          state: RevisionedMutationState.queued,
          type: ProfileMutationType.updateProfileFields,
          changedFields: {'firstName'},
          profile: _profile(),
        ),
        throwsFormatException,
      );
    });

    test('Profile keeps unknown legacy fields without exporting human fields',
        () {
      final state = RevisionedProfileState(
        accountScopeId: scope,
        profile: _profile(
          legacy: const {'futurePreference': 'retained'},
        ),
        revision: 1,
        createdAt: instant,
        updatedAt: instant,
        lastMutationId: 'profile-create',
      );

      final json = state.toJson();
      final payload = json['payload'] as Map<String, dynamic>;
      expect(payload['futurePreference'], 'retained');
      expect(payload, isNot(contains('firstName')));
      expect(payload, isNot(contains('children')));
      expect(json['accountScopeId'], scope);
    });
  });

  group('Y.1 bounded offline journal', () {
    test('persists in stable order and remains account scoped', () async {
      const journal = RevisionedOfflineJournal();
      await journal.enqueue(
        accountScopeId: scope,
        domain: RevisionedSyncDomain.task,
        mutation: _taskMutation(
          id: 'task-1',
          mutationId: 'first',
          expectedRevision: 0,
          type: TaskMutationType.createTask,
          instant: instant,
        ),
      );
      await journal.enqueue(
        accountScopeId: scope,
        domain: RevisionedSyncDomain.task,
        mutation: _taskMutation(
          id: 'task-2',
          mutationId: 'second',
          expectedRevision: 0,
          type: TaskMutationType.createTask,
          instant: instant,
        ),
      );

      final restored = await journal.load(
        accountScopeId: scope,
        domain: RevisionedSyncDomain.task,
      );
      final other = await journal.load(
        accountScopeId: 'account-b',
        domain: RevisionedSyncDomain.task,
      );

      expect(
        restored.mutations.map((value) => value.mutationId),
        ['first', 'second'],
      );
      expect(other.mutations, isEmpty);
    });

    test('same mutationId is queued once and receipts are bounded', () async {
      const journal = RevisionedOfflineJournal();
      final mutation = _taskMutation(
        id: 'task-1',
        mutationId: 'same',
        expectedRevision: 0,
        type: TaskMutationType.createTask,
        instant: instant,
      );
      await journal.enqueue(
        accountScopeId: scope,
        domain: RevisionedSyncDomain.task,
        mutation: mutation,
      );
      await journal.enqueue(
        accountScopeId: scope,
        domain: RevisionedSyncDomain.task,
        mutation: mutation,
      );

      final state = await journal.load(
        accountScopeId: scope,
        domain: RevisionedSyncDomain.task,
      );
      expect(state.mutations, hasLength(1));
      expect(RevisionedJournalState.maxAttempts, 5);
      expect(RevisionedJournalState.maxReceipts, 200);
      expect(RevisionedJournalState.maxConflicts, 100);
    });

    test('conversation retry guard blocks Pause without losing mutation',
        () async {
      final cloud = _TaskCloud()..unavailable = true;
      var guardCalls = 0;
      final service = TaskRevisionSyncService(
        cloud: cloud,
        retryGuard: (reference) async {
          guardCalls++;
          return false;
        },
      );
      final mutation = _taskMutation(
        id: 'task-1',
        mutationId: 'pending-action',
        expectedRevision: 0,
        type: TaskMutationType.createTask,
        instant: instant,
        reference: const RevisionedActionReference(
          actionType: 'createTask',
          pendingActionId: 'pending-1',
          policyMode: 'suggestions',
          policyVersion: 1,
          sessionGeneration: 2,
          origin: 'explicitUserConfirmation',
        ),
      );
      final queued = await service.apply(scope, mutation);
      cloud.unavailable = false;
      final retry = await service.retry(scope, mutation.mutationId);

      expect(queued.status, RevisionedCloudWriteStatus.unavailable);
      expect(retry.status, RevisionedCloudWriteStatus.unavailable);
      expect(guardCalls, 1);
      expect(cloud.values, isEmpty);
    });
  });
}

TaskMutation _taskMutation({
  required String id,
  required String mutationId,
  required int expectedRevision,
  required TaskMutationType type,
  required DateTime instant,
  bool done = false,
  RevisionedActionReference? reference,
}) =>
    TaskMutation(
      mutationId: mutationId,
      targetId: id,
      expectedRevision: expectedRevision,
      createdAt: instant,
      attempt: 0,
      nextRetryAt: null,
      state: RevisionedMutationState.queued,
      actionReference: reference,
      type: type,
      task: TaskModel(
        id: id,
        title: 'Tâche',
        category: 'Perso',
        isDone: done,
        createdAt: instant,
      ),
    );

ShoppingMutation _shoppingMutation({
  required String mutationId,
  required int expectedRevision,
  required ShoppingMutationType type,
  required DateTime instant,
}) =>
    ShoppingMutation(
      mutationId: mutationId,
      targetId: 'item-1',
      expectedRevision: expectedRevision,
      createdAt: instant,
      attempt: 0,
      nextRetryAt: null,
      state: RevisionedMutationState.queued,
      type: type,
      item: ShoppingItemModel(
        id: 'item-1',
        title: 'Lait',
        isBought: false,
        createdAt: instant,
      ),
    );

UserProfile _profile({Map<String, dynamic> legacy = const {}}) => UserProfile(
      legacyExtensions: legacy,
      firstName: 'Legacy only',
      familyStatus: '',
      workStatus: 'Salariée',
      partnerName: '',
      wantsNotifications: true,
      children: const [],
      planningStyle: 'Souple',
    );

final class _TaskCloud implements RevisionedTaskCloudRepository {
  final values = <RevisionedTask>[];
  bool unavailable = false;

  @override
  Future<List<RevisionedTask>> load({int limit = 100}) async =>
      values.take(limit).toList();

  @override
  Future<RevisionedCloudWriteResult<RevisionedTask>> create(
    TaskMutation mutation,
    String accountScopeId,
  ) async {
    if (unavailable) throw StateError('offline');
    final existing =
        values.where((value) => value.entityId == mutation.targetId);
    if (existing.isNotEmpty) {
      return RevisionedCloudWriteResult(
        existing.single.lastMutationId == mutation.mutationId
            ? RevisionedCloudWriteStatus.idempotent
            : RevisionedCloudWriteStatus.revisionConflict,
        value: existing.single,
      );
    }
    final value = RevisionedTask(
      accountScopeId: accountScopeId,
      entityId: mutation.targetId,
      task: mutation.task,
      revision: 1,
      createdAt: mutation.createdAt,
      updatedAt: mutation.createdAt,
      lastMutationId: mutation.mutationId,
    );
    values.add(value);
    return RevisionedCloudWriteResult(
      RevisionedCloudWriteStatus.success,
      value: value,
    );
  }

  @override
  Future<RevisionedCloudWriteResult<RevisionedTask>> update(
    TaskMutation mutation,
    String accountScopeId,
  ) async {
    if (unavailable) throw StateError('offline');
    final index =
        values.indexWhere((value) => value.entityId == mutation.targetId);
    if (index < 0) {
      return const RevisionedCloudWriteResult(
        RevisionedCloudWriteStatus.notFound,
      );
    }
    final existing = values[index];
    if (existing.lastMutationId == mutation.mutationId) {
      return RevisionedCloudWriteResult(
        RevisionedCloudWriteStatus.idempotent,
        value: existing,
      );
    }
    if (existing.revision != mutation.expectedRevision ||
        existing.isTombstone) {
      return RevisionedCloudWriteResult(
        RevisionedCloudWriteStatus.revisionConflict,
        value: existing,
      );
    }
    final updated = existing.copyWith(
      task: mutation.task,
      revision: existing.revision + 1,
      updatedAt: mutation.createdAt,
      lastMutationId: mutation.mutationId,
      isTombstone: mutation.type == TaskMutationType.deleteTask ||
          mutation.type == TaskMutationType.archiveTask,
    );
    values[index] = updated;
    return RevisionedCloudWriteResult(
      RevisionedCloudWriteStatus.success,
      value: updated,
    );
  }
}

final class _ShoppingCloud implements RevisionedShoppingCloudRepository {
  final values = <RevisionedShoppingItem>[];

  @override
  Future<List<RevisionedShoppingItem>> load({int limit = 100}) async =>
      values.take(limit).toList();

  @override
  Future<RevisionedCloudWriteResult<RevisionedShoppingItem>> create(
    ShoppingMutation mutation,
    String accountScopeId,
  ) async {
    final existing =
        values.where((value) => value.entityId == mutation.targetId);
    if (existing.isNotEmpty) {
      return RevisionedCloudWriteResult(
        existing.single.lastMutationId == mutation.mutationId
            ? RevisionedCloudWriteStatus.idempotent
            : RevisionedCloudWriteStatus.revisionConflict,
        value: existing.single,
      );
    }
    final value = RevisionedShoppingItem(
      accountScopeId: accountScopeId,
      entityId: mutation.targetId,
      item: mutation.item,
      revision: 1,
      createdAt: mutation.createdAt,
      updatedAt: mutation.createdAt,
      lastMutationId: mutation.mutationId,
    );
    values.add(value);
    return RevisionedCloudWriteResult(
      RevisionedCloudWriteStatus.success,
      value: value,
    );
  }

  @override
  Future<RevisionedCloudWriteResult<RevisionedShoppingItem>> update(
    ShoppingMutation mutation,
    String accountScopeId,
  ) async {
    final index =
        values.indexWhere((value) => value.entityId == mutation.targetId);
    if (index < 0) {
      return const RevisionedCloudWriteResult(
        RevisionedCloudWriteStatus.notFound,
      );
    }
    final existing = values[index];
    if (existing.lastMutationId == mutation.mutationId) {
      return RevisionedCloudWriteResult(
        RevisionedCloudWriteStatus.idempotent,
        value: existing,
      );
    }
    if (existing.revision != mutation.expectedRevision ||
        existing.isTombstone) {
      return RevisionedCloudWriteResult(
        RevisionedCloudWriteStatus.revisionConflict,
        value: existing,
      );
    }
    final updated = RevisionedShoppingItem(
      accountScopeId: accountScopeId,
      entityId: existing.entityId,
      item: mutation.item,
      revision: existing.revision + 1,
      createdAt: existing.createdAt,
      updatedAt: mutation.createdAt,
      lastMutationId: mutation.mutationId,
      isTombstone: mutation.type == ShoppingMutationType.removeItem ||
          mutation.type == ShoppingMutationType.clearList,
      clearGeneration: mutation.clearGeneration,
    );
    values[index] = updated;
    return RevisionedCloudWriteResult(
      RevisionedCloudWriteStatus.success,
      value: updated,
    );
  }
}
