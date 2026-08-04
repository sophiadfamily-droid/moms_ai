import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/revisioned_domain_models.dart';
import 'package:moms_ai/models/task/task_lifecycle_models.dart';
import 'package:moms_ai/models/task_model.dart';
import 'package:moms_ai/services/task/task_lifecycle_mutation_adapter.dart';

void main() {
  const adapter = TaskLifecycleMutationAdapter();

  test('maps create to the existing create mutation', () {
    final plan = adapter.create(_task());
    expect(plan.mutationType, TaskMutationType.createTask);
    expect(plan.transition.afterState, TaskLifecycleState.active);
    expect(plan.transition.nextRevision, 1);
  });

  test('maps update, complete and reopen through T.1', () {
    final current = _revisioned(_task(), revision: 3);
    final update = adapter.change(
      current: current,
      proposed: current.task.copyWith(title: 'Corrigée'),
    );
    final complete = adapter.change(
      current: current,
      proposed: current.task.copyWith(title: 'Terminée', isDone: true),
    );
    final reopen = adapter.change(
      current: _revisioned(_task(isDone: true), revision: 4),
      proposed: _task(isDone: false),
    );

    expect(update!.mutationType, TaskMutationType.updateTask);
    expect(complete!.mutationType, TaskMutationType.completeTask);
    expect(complete.transition.afterState, TaskLifecycleState.completed);
    expect(complete.persistencePayload.title, 'Terminée');
    expect(reopen!.mutationType, TaskMutationType.reopenTask);
  });

  test('maps removal to delete while retaining legacy tombstone payload', () {
    final current = _revisioned(_task(), revision: 5);
    final plan = adapter.change(current: current, proposed: null)!;

    expect(plan.mutationType, TaskMutationType.deleteTask);
    expect(plan.transition.task, isNull);
    expect(plan.persistencePayload, same(current.task));
  });

  test('identical and tombstoned values produce no mutation', () {
    final current = _revisioned(_task(), revision: 2);
    expect(adapter.change(current: current, proposed: current.task), isNull);
    expect(
      adapter.change(
        current: _revisioned(_task(), revision: 2, tombstone: true),
        proposed: _task(),
      ),
      isNull,
    );
  });
}

TaskModel _task({bool isDone = false}) => TaskModel(
      id: 'task-1',
      title: 'Tâche',
      category: 'To-do',
      isDone: isDone,
      createdAt: DateTime.utc(2026, 8, 4),
    );

RevisionedTask _revisioned(
  TaskModel task, {
  required int revision,
  bool tombstone = false,
}) =>
    RevisionedTask(
      accountScopeId: 'account-a',
      entityId: task.id!,
      task: task,
      revision: revision,
      createdAt: DateTime.utc(2026, 8, 4),
      updatedAt: DateTime.utc(2026, 8, 4),
      lastMutationId: 'mutation-$revision',
      isTombstone: tombstone,
    );
