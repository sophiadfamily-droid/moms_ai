import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/identity/entity_id_generator.dart';
import '../core/identity/entity_identity.dart';
import '../core/identity/entity_matcher.dart';
import '../core/identity/uuid_v7_entity_id_generator.dart';
import '../models/task_model.dart';
import '../models/revisioned_domain_models.dart';
import '../models/revisioned_sync_protocol.dart';
import '../models/life_context/life_context_domains.dart';
import 'auth_service.dart';
import 'app_diagnostics.dart';
import 'revisioned_cloud_repositories.dart';
import 'revisioned_domain_sync_service.dart';
import 'revisioned_domain_local_repository.dart';
import 'revisioned_offline_journal.dart';
import 'revisioned_action_ledger_observer.dart';

class TaskService {
  static const String tasksKey = "tasks";

  static final EntityMatcher<TaskModel> _taskMatcher = EntityMatcher(
    idOf: (task) => task.id,
    legacyEquals: (first, second) => first == second,
  );

  static final ValueNotifier<int> tasksVersion = ValueNotifier<int>(0);
  static final TaskRevisionSyncService _sync = TaskRevisionSyncService(
    cloud: const FirestoreRevisionedTaskRepository(),
  );

  static void notifyTasksChanged() {
    tasksVersion.value++;
  }

  static Future<void> saveTasks(List<TaskModel> tasks) async {
    final prefs = await SharedPreferences.getInstance();
    final scope = _currentAccountScope();

    final List<String> encoded =
        tasks.map((task) => jsonEncode(task.toJson())).toList();

    if (scope == null) {
      await prefs.setStringList(tasksKey, encoded);
    }

    try {
      if (scope != null) await _reconcileRevisioned(scope, tasks);
    } catch (_) {
      AppDiagnostics.record(
        component: 'task_storage',
        step: 'cloud_sync',
        code: AppErrorCode.syncFailure,
      );
    }

    notifyTasksChanged();
  }

  static Future<List<TaskModel>> getTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final scope = _currentAccountScope();

    final data = scope == null ? prefs.getStringList(tasksKey) : null;

    final localTasks = data == null
        ? <TaskModel>[]
        : data.map((task) {
            return TaskModel.fromJson(jsonDecode(task));
          }).toList();

    try {
      final cloudTasks = scope == null
          ? const <RevisionedTask>[]
          : await _sync.bootstrap(scope);
      final active = cloudTasks
          .where((value) => !value.isTombstone)
          .map((value) => value.task)
          .toList(growable: false);

      if (scope != null) {
        return active;
      }
    } catch (_) {
      AppDiagnostics.record(
        component: 'task_storage',
        step: 'cloud_load',
        code: AppErrorCode.syncFailure,
      );
    }

    return localTasks;
  }

  /// Read-only, account-bound source for Life Context projections.
  ///
  /// The legacy local task cache is not account-scoped, so it is never exposed
  /// through this boundary.
  static Future<List<TaskModel>> getTasksForLifeContext(
    String accountScopeId,
  ) async {
    if (accountScopeId.trim().isEmpty ||
        _currentAccountScope() != accountScopeId) {
      throw const FormatException('task_account_scope_mismatch');
    }
    return _sync.bootstrap(accountScopeId).then(
          (values) => values
              .where((value) => !value.isTombstone)
              .map((value) => value.task)
              .toList(growable: false),
        );
  }

  static Future<TaskLifeContextSyncMetadata> getTaskSyncMetadataForLifeContext(
      String accountScopeId) async {
    if (accountScopeId.trim().isEmpty ||
        _currentAccountScope() != accountScopeId) {
      throw const FormatException('task_account_scope_mismatch');
    }
    const local = RevisionedDomainLocalRepository();
    const journal = RevisionedOfflineJournal();
    final values = await local.loadTasks(accountScopeId);
    final journalState = await journal.load(
      accountScopeId: accountScopeId,
      domain: RevisionedSyncDomain.task,
    );
    final hasConflict = journalState.conflicts.isNotEmpty;
    final pendingCount = journalState.mutations.length;
    final syncStatus = hasConflict
        ? 'conflict'
        : pendingCount > 0
            ? 'pending'
            : 'synced';
    return TaskLifeContextSyncMetadata(
      revision: values.fold<int>(
        0,
        (maximum, value) => value.revision > maximum ? value.revision : maximum,
      ),
      syncStatus: syncStatus,
      pendingCount: pendingCount,
      hasConflict: hasConflict,
      itemSyncStatuses: Map.unmodifiable({
        for (final value in values) value.entityId: value.syncStatus.name,
      }),
    );
  }

  static Future<void> addTask(
    TaskModel task, {
    EntityIdGenerator idGenerator = const UuidV7EntityIdGenerator(),
  }) async {
    final tasks = await getTasks();
    tasks.add(_withIdForCreation(task, idGenerator));
    await saveTasks(tasks);
  }

  static TaskModel _withIdForCreation(
    TaskModel task,
    EntityIdGenerator idGenerator,
  ) {
    if (EntityIdentity.isValid(task.id)) return task;
    final generatedId = idGenerator.generate();
    return task.copyWith(id: generatedId);
  }

  static bool areSameTask(TaskModel first, TaskModel second) {
    return _taskMatcher.matches(first, second);
  }

  static Future<void> updateTasks(List<TaskModel> tasks) async {
    await saveTasks(tasks);
  }

  static Future<void> clearTasks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(tasksKey);

    try {
      final scope = _currentAccountScope();
      if (scope != null) await _reconcileRevisioned(scope, const []);
    } catch (_) {
      AppDiagnostics.record(
        component: 'task_storage',
        step: 'cloud_clear',
        code: AppErrorCode.syncFailure,
      );
    }

    notifyTasksChanged();
  }

  static Future<void> _reconcileRevisioned(
    String scope,
    List<TaskModel> proposed,
  ) async {
    final current = await _sync.bootstrap(scope);
    final currentById = {
      for (final value in current) value.entityId: value,
    };
    final proposedById = {
      for (final task in proposed)
        if (EntityIdentity.isValid(task.id)) task.id!: task,
    };
    const mutationIds = UuidV7EntityIdGenerator();
    for (final entry in proposedById.entries) {
      final existing = currentById[entry.key];
      if (existing == null) {
        final mutation = TaskMutation(
          mutationId: mutationIds.generate(),
          targetId: entry.key,
          expectedRevision: 0,
          createdAt: DateTime.now().toUtc(),
          attempt: 0,
          nextRetryAt: null,
          state: RevisionedMutationState.queued,
          type: TaskMutationType.createTask,
          task: entry.value,
        );
        await RevisionedActionLedgerObserver.task(
          scope,
          mutation,
          () => _sync.apply(scope, mutation),
        );
      } else if (!existing.isTombstone &&
          jsonEncode(existing.task.toJson()) !=
              jsonEncode(entry.value.toJson())) {
        final type = existing.task.isDone == entry.value.isDone
            ? TaskMutationType.updateTask
            : entry.value.isDone
                ? TaskMutationType.completeTask
                : TaskMutationType.reopenTask;
        final mutation = TaskMutation(
          mutationId: mutationIds.generate(),
          targetId: entry.key,
          expectedRevision: existing.revision,
          createdAt: DateTime.now().toUtc(),
          attempt: 0,
          nextRetryAt: null,
          state: RevisionedMutationState.queued,
          type: type,
          task: entry.value,
        );
        await RevisionedActionLedgerObserver.task(
          scope,
          mutation,
          () => _sync.apply(scope, mutation),
        );
      }
    }
    for (final existing in current.where(
      (value) =>
          !value.isTombstone && !proposedById.containsKey(value.entityId),
    )) {
      final mutation = TaskMutation(
        mutationId: mutationIds.generate(),
        targetId: existing.entityId,
        expectedRevision: existing.revision,
        createdAt: DateTime.now().toUtc(),
        attempt: 0,
        nextRetryAt: null,
        state: RevisionedMutationState.queued,
        type: TaskMutationType.deleteTask,
        task: existing.task,
      );
      await RevisionedActionLedgerObserver.task(
        scope,
        mutation,
        () => _sync.apply(scope, mutation),
      );
    }
  }

  static String? _currentAccountScope() {
    try {
      return AuthService.currentUserId;
    } on Object {
      return null;
    }
  }
}
