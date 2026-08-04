import '../task_model.dart';

enum TaskLifecycleState { active, completed, deleted }

enum TaskLifecycleOperation { create, update, complete, reopen, delete }

final class TaskLifecycleException implements Exception {
  const TaskLifecycleException(this.code);

  final String code;

  @override
  String toString() => 'TaskLifecycleException($code)';
}

/// Closed request contract for one future Task persistence transition.
final class TaskLifecycleRequest {
  const TaskLifecycleRequest({
    required this.operation,
    required this.expectedRevision,
    this.current,
    this.proposed,
  });

  final TaskLifecycleOperation operation;
  final int expectedRevision;
  final TaskModel? current;
  final TaskModel? proposed;
}

/// Pure transition result. It describes intent but grants no write authority.
final class TaskLifecycleTransition {
  static const int currentSchemaVersion = 1;

  TaskLifecycleTransition({
    this.schemaVersion = currentSchemaVersion,
    required this.operation,
    required this.taskId,
    required this.expectedRevision,
    required this.nextRevision,
    required this.beforeState,
    required this.afterState,
    required this.task,
  }) {
    if (schemaVersion != currentSchemaVersion) {
      throw const TaskLifecycleException(
        'unsupported_task_lifecycle_version',
      );
    }
    if (taskId.trim().isEmpty ||
        expectedRevision < 0 ||
        nextRevision != expectedRevision + 1 ||
        (task != null && task!.id != taskId) ||
        !_matchesOperation()) {
      throw const TaskLifecycleException('invalid_task_lifecycle_result');
    }
  }

  bool _matchesOperation() => switch (operation) {
        TaskLifecycleOperation.create => expectedRevision == 0 &&
            beforeState == null &&
            afterState == TaskLifecycleState.active &&
            task != null &&
            !task!.isDone,
        TaskLifecycleOperation.update => expectedRevision >= 1 &&
            beforeState != null &&
            beforeState == afterState &&
            afterState != TaskLifecycleState.deleted &&
            task != null &&
            task!.isDone == (afterState == TaskLifecycleState.completed),
        TaskLifecycleOperation.complete => expectedRevision >= 1 &&
            beforeState == TaskLifecycleState.active &&
            afterState == TaskLifecycleState.completed &&
            task != null &&
            task!.isDone,
        TaskLifecycleOperation.reopen => expectedRevision >= 1 &&
            beforeState == TaskLifecycleState.completed &&
            afterState == TaskLifecycleState.active &&
            task != null &&
            !task!.isDone,
        TaskLifecycleOperation.delete => expectedRevision >= 1 &&
            beforeState != null &&
            beforeState != TaskLifecycleState.deleted &&
            afterState == TaskLifecycleState.deleted &&
            task == null,
      };

  final int schemaVersion;
  final TaskLifecycleOperation operation;
  final String taskId;
  final int expectedRevision;
  final int nextRevision;
  final TaskLifecycleState? beforeState;
  final TaskLifecycleState afterState;
  final TaskModel? task;

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'operation': operation.name,
        'taskId': taskId,
        'expectedRevision': expectedRevision,
        'nextRevision': nextRevision,
        'beforeState': beforeState?.name,
        'afterState': afterState.name,
        if (task != null) 'task': task!.toJson(),
      };
}
