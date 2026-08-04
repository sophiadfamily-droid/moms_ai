import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/task/task_lifecycle_models.dart';
import 'package:moms_ai/models/task_model.dart';
import 'package:moms_ai/services/task/task_lifecycle_engine.dart';

void main() {
  const engine = TaskLifecycleEngine();

  test('create starts one identified active Task at revision one', () {
    final transition = engine.transition(
      TaskLifecycleRequest(
        operation: TaskLifecycleOperation.create,
        expectedRevision: 0,
        proposed: _task(),
      ),
    );

    expect(transition.beforeState, isNull);
    expect(transition.afterState, TaskLifecycleState.active);
    expect(transition.nextRevision, 1);
    expect(transition.taskId, 'task-1');
  });

  test('update preserves identity, creation time and completion state', () {
    final current = _task();
    final transition = engine.transition(
      TaskLifecycleRequest(
        operation: TaskLifecycleOperation.update,
        expectedRevision: 3,
        current: current,
        proposed: current.copyWith(title: 'Titre corrigé'),
      ),
    );

    expect(transition.beforeState, TaskLifecycleState.active);
    expect(transition.afterState, TaskLifecycleState.active);
    expect(transition.nextRevision, 4);
    expect(transition.task!.title, 'Titre corrigé');
  });

  test('complete and reopen are distinct reversible transitions', () {
    final completed = engine.transition(
      TaskLifecycleRequest(
        operation: TaskLifecycleOperation.complete,
        expectedRevision: 1,
        current: _task(),
      ),
    );
    final reopened = engine.transition(
      TaskLifecycleRequest(
        operation: TaskLifecycleOperation.reopen,
        expectedRevision: 2,
        current: completed.task,
      ),
    );

    expect(completed.afterState, TaskLifecycleState.completed);
    expect(completed.task!.isDone, isTrue);
    expect(reopened.beforeState, TaskLifecycleState.completed);
    expect(reopened.afterState, TaskLifecycleState.active);
    expect(reopened.task!.isDone, isFalse);
  });

  test('delete produces a tombstone intent without carrying Task content', () {
    final transition = engine.transition(
      TaskLifecycleRequest(
        operation: TaskLifecycleOperation.delete,
        expectedRevision: 7,
        current: _task(),
      ),
    );

    expect(transition.afterState, TaskLifecycleState.deleted);
    expect(transition.nextRevision, 8);
    expect(transition.task, isNull);
    expect(transition.toJson(), isNot(containsPair('task', anything)));
  });

  test('rejects state changes hidden inside a generic update', () {
    final current = _task();

    expect(
      () => engine.transition(
        TaskLifecycleRequest(
          operation: TaskLifecycleOperation.update,
          expectedRevision: 1,
          current: current,
          proposed: current.copyWith(isDone: true),
        ),
      ),
      throwsA(
        isA<TaskLifecycleException>().having(
          (error) => error.code,
          'code',
          'invalid_task_update_transition',
        ),
      ),
    );
  });

  test('rejects missing identity and stale create revisions', () {
    expect(
      () => engine.transition(
        TaskLifecycleRequest(
          operation: TaskLifecycleOperation.create,
          expectedRevision: 0,
          proposed: _task(id: null),
        ),
      ),
      throwsA(isA<TaskLifecycleException>()),
    );
    expect(
      () => engine.transition(
        TaskLifecycleRequest(
          operation: TaskLifecycleOperation.create,
          expectedRevision: 1,
          proposed: _task(),
        ),
      ),
      throwsA(isA<TaskLifecycleException>()),
    );
  });

  test('result contract rejects a deleted state that still carries content',
      () {
    expect(
      () => TaskLifecycleTransition(
        operation: TaskLifecycleOperation.delete,
        taskId: 'task-1',
        expectedRevision: 1,
        nextRevision: 2,
        beforeState: TaskLifecycleState.active,
        afterState: TaskLifecycleState.deleted,
        task: _task(),
      ),
      throwsA(
        isA<TaskLifecycleException>().having(
          (error) => error.code,
          'code',
          'invalid_task_lifecycle_result',
        ),
      ),
    );
  });
}

TaskModel _task({String? id = 'task-1'}) => TaskModel(
      id: id,
      title: 'Envoyer le dossier',
      category: 'Administratif',
      isDone: false,
      createdAt: DateTime.utc(2026, 8, 4, 17),
      dueDate: '2026-08-05',
      priority: 'Haute',
    );
