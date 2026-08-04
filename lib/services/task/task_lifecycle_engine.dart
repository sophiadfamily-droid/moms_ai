import '../../core/identity/entity_identity.dart';
import '../../models/task/task_lifecycle_models.dart';
import '../../models/task_model.dart';

/// V1-T.1 validates Task state transitions without reading or writing storage.
final class TaskLifecycleEngine {
  const TaskLifecycleEngine();

  TaskLifecycleTransition transition(TaskLifecycleRequest request) {
    return switch (request.operation) {
      TaskLifecycleOperation.create => _create(request),
      TaskLifecycleOperation.update => _update(request),
      TaskLifecycleOperation.complete => _complete(request),
      TaskLifecycleOperation.reopen => _reopen(request),
      TaskLifecycleOperation.delete => _delete(request),
    };
  }

  TaskLifecycleTransition _create(TaskLifecycleRequest request) {
    final proposed = request.proposed;
    if (request.current != null ||
        request.expectedRevision != 0 ||
        proposed == null ||
        proposed.isDone) {
      throw const TaskLifecycleException('invalid_task_create_transition');
    }
    _validateTask(proposed);
    return _result(
      request: request,
      task: proposed,
      before: null,
      after: TaskLifecycleState.active,
    );
  }

  TaskLifecycleTransition _update(TaskLifecycleRequest request) {
    final current = _existing(request);
    final proposed = request.proposed;
    if (proposed == null ||
        proposed.id != current.id ||
        proposed.createdAt != current.createdAt ||
        proposed.isDone != current.isDone) {
      throw const TaskLifecycleException('invalid_task_update_transition');
    }
    _validateTask(proposed);
    return _result(
      request: request,
      task: proposed,
      before: _stateOf(current),
      after: _stateOf(proposed),
    );
  }

  TaskLifecycleTransition _complete(TaskLifecycleRequest request) {
    final current = _existing(request);
    if (request.proposed != null || current.isDone) {
      throw const TaskLifecycleException('invalid_task_complete_transition');
    }
    return _result(
      request: request,
      task: current.copyWith(isDone: true),
      before: TaskLifecycleState.active,
      after: TaskLifecycleState.completed,
    );
  }

  TaskLifecycleTransition _reopen(TaskLifecycleRequest request) {
    final current = _existing(request);
    if (request.proposed != null || !current.isDone) {
      throw const TaskLifecycleException('invalid_task_reopen_transition');
    }
    return _result(
      request: request,
      task: current.copyWith(isDone: false),
      before: TaskLifecycleState.completed,
      after: TaskLifecycleState.active,
    );
  }

  TaskLifecycleTransition _delete(TaskLifecycleRequest request) {
    final current = _existing(request);
    if (request.proposed != null) {
      throw const TaskLifecycleException('invalid_task_delete_transition');
    }
    return _result(
      request: request,
      task: null,
      before: _stateOf(current),
      after: TaskLifecycleState.deleted,
    );
  }

  TaskModel _existing(TaskLifecycleRequest request) {
    final current = request.current;
    if (current == null || request.expectedRevision < 1) {
      throw const TaskLifecycleException('task_current_state_required');
    }
    _validateTask(current);
    return current;
  }

  void _validateTask(TaskModel task) {
    if (!EntityIdentity.isValid(task.id) ||
        task.title.trim().isEmpty ||
        task.title.length > 500 ||
        task.category.length > 100 ||
        task.dueDate.length > 40 ||
        task.notes.length > 4000 ||
        task.planning.length > 100 ||
        task.priority.length > 100) {
      throw const TaskLifecycleException('invalid_task_lifecycle_payload');
    }
  }

  TaskLifecycleState _stateOf(TaskModel task) =>
      task.isDone ? TaskLifecycleState.completed : TaskLifecycleState.active;

  TaskLifecycleTransition _result({
    required TaskLifecycleRequest request,
    required TaskModel? task,
    required TaskLifecycleState? before,
    required TaskLifecycleState after,
  }) =>
      TaskLifecycleTransition(
        operation: request.operation,
        taskId: (task ?? request.current)!.id!,
        expectedRevision: request.expectedRevision,
        nextRevision: request.expectedRevision + 1,
        beforeState: before,
        afterState: after,
        task: task,
      );
}
