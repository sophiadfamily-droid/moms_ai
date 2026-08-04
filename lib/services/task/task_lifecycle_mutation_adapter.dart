import 'dart:convert';

import '../../models/revisioned_domain_models.dart';
import '../../models/task/task_lifecycle_models.dart';
import '../../models/task_model.dart';
import 'task_lifecycle_engine.dart';

/// T.2 maps a validated T.1 transition to the existing revisioned protocol.
/// It plans a mutation but never persists it.
final class TaskLifecycleMutationPlan {
  const TaskLifecycleMutationPlan({
    required this.transition,
    required this.mutationType,
    required this.persistencePayload,
  });

  final TaskLifecycleTransition transition;
  final TaskMutationType mutationType;
  final TaskModel persistencePayload;
}

final class TaskLifecycleMutationAdapter {
  const TaskLifecycleMutationAdapter();

  TaskLifecycleMutationPlan create(TaskModel proposed) {
    final transition = const TaskLifecycleEngine().transition(
      TaskLifecycleRequest(
        operation: TaskLifecycleOperation.create,
        expectedRevision: 0,
        proposed: proposed,
      ),
    );
    return TaskLifecycleMutationPlan(
      transition: transition,
      mutationType: TaskMutationType.createTask,
      persistencePayload: transition.task!,
    );
  }

  TaskLifecycleMutationPlan? change({
    required RevisionedTask current,
    required TaskModel? proposed,
  }) {
    if (current.isTombstone) return null;
    if (proposed != null &&
        jsonEncode(current.task.toJson()) == jsonEncode(proposed.toJson())) {
      return null;
    }
    final operation = proposed == null
        ? TaskLifecycleOperation.delete
        : current.task.isDone == proposed.isDone
            ? TaskLifecycleOperation.update
            : proposed.isDone
                ? TaskLifecycleOperation.complete
                : TaskLifecycleOperation.reopen;
    final transition = const TaskLifecycleEngine().transition(
      TaskLifecycleRequest(
        operation: operation,
        expectedRevision: current.revision,
        current: current.task,
        proposed: operation == TaskLifecycleOperation.delete ? null : proposed,
      ),
    );
    return TaskLifecycleMutationPlan(
      transition: transition,
      mutationType: switch (operation) {
        TaskLifecycleOperation.update => TaskMutationType.updateTask,
        TaskLifecycleOperation.complete => TaskMutationType.completeTask,
        TaskLifecycleOperation.reopen => TaskMutationType.reopenTask,
        TaskLifecycleOperation.delete => TaskMutationType.deleteTask,
        TaskLifecycleOperation.create => TaskMutationType.createTask,
      },
      // The legacy tombstone protocol retains the previous payload.
      persistencePayload: transition.task ?? current.task,
    );
  }
}
