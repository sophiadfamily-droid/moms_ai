import '../models/event_sync_models.dart';
import 'event_mutation_result.dart';
import 'event_sync_journal.dart';

typedef EventSyncOperationExecutor = Future<EventMutationResult> Function(
  PendingEventSyncOperation operation,
);

final class EventSyncService {
  final EventSyncJournal _journal;
  final EventSyncOperationExecutor _execute;
  Future<EventSyncResult>? _activeSync;

  EventSyncService({
    required EventSyncOperationExecutor execute,
    EventSyncJournal? journal,
  })  : _execute = execute,
        _journal = journal ?? EventSyncJournal();

  Future<EventSyncResult> synchronize() {
    return _activeSync ??=
        _synchronize().whenComplete(() => _activeSync = null);
  }

  Future<EventSyncResult> _synchronize() async {
    var operations = await _journal.load();
    var applied = 0;
    for (var index = 0; index < operations.length; index++) {
      final operation = operations[index];
      if (operation.state != EventSyncOperationState.pending &&
          operation.state != EventSyncOperationState.inFlight &&
          !(operation.state == EventSyncOperationState.failed &&
              operation.attempts < 5)) {
        continue;
      }
      final inFlight = operation.copyWith(
        attempts: operation.attempts + 1,
        state: EventSyncOperationState.inFlight,
        clearConflict: true,
      );
      operations[index] = inFlight;
      await _journal.save(operations);
      EventMutationResult result;
      try {
        result = await _execute(inFlight);
      } catch (_) {
        result = const EventMutationResult.persistenceFailure();
      }
      switch (result.status) {
        case EventMutationStatus.success:
          operations[index] = inFlight.copyWith(
            state: EventSyncOperationState.applied,
          );
          applied++;
        case EventMutationStatus.revisionConflict:
          operations[index] = inFlight.copyWith(
            state: EventSyncOperationState.conflict,
            conflictType: EventSyncConflictType.revisionConflict,
          );
        case EventMutationStatus.alreadyExists:
          operations[index] = inFlight.copyWith(
            state: EventSyncOperationState.conflict,
            conflictType: EventSyncConflictType.alreadyExists,
          );
        case EventMutationStatus.scopeMismatch:
          operations[index] = inFlight.copyWith(
            state: EventSyncOperationState.conflict,
            conflictType: EventSyncConflictType.scopeMismatch,
          );
        case EventMutationStatus.notFound:
          final idempotentDelete =
              operation.type == EventSyncOperationType.delete;
          operations[index] = inFlight.copyWith(
            state: idempotentDelete
                ? EventSyncOperationState.applied
                : EventSyncOperationState.conflict,
            conflictType:
                idempotentDelete ? null : EventSyncConflictType.notFound,
          );
          if (idempotentDelete) applied++;
        case EventMutationStatus.invalidMutation:
          operations[index] = inFlight.copyWith(
            state: EventSyncOperationState.conflict,
            conflictType: EventSyncConflictType.invalidPayload,
          );
        case EventMutationStatus.persistenceFailure:
          operations[index] = inFlight.copyWith(
            state: inFlight.attempts >= 5
                ? EventSyncOperationState.conflict
                : EventSyncOperationState.failed,
            conflictType: inFlight.attempts >= 5
                ? EventSyncConflictType.retryExhausted
                : EventSyncConflictType.persistenceFailure,
          );
      }
      await _journal.save(operations);
    }
    operations = await _journal.load();
    final retainedConflicts = operations
        .where(
            (operation) => operation.state == EventSyncOperationState.conflict)
        .length;
    final retainedFailures = operations
        .where((operation) => operation.state == EventSyncOperationState.failed)
        .length;
    return EventSyncResult(
      status: retainedConflicts > 0
          ? EventSyncStatus.conflicts
          : retainedFailures > 0
              ? EventSyncStatus.failed
              : operations.isEmpty
                  ? EventSyncStatus.synchronized
                  : EventSyncStatus.pending,
      appliedCount: applied,
      conflictCount: retainedConflicts,
      failureCount: retainedFailures,
      remaining: operations,
    );
  }
}
