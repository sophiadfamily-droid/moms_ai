import 'dart:collection';

import 'event_model.dart';
import 'event_sync_models.dart';

enum EventConflictResolutionStatus {
  success,
  notFound,
  alreadyResolved,
  invalidDecision,
  scopeMismatch,
  cloudChangedAgain,
  confirmationRequired,
  persistenceFailure,
}

final class EventSyncConflict {
  final String conflictId;
  final String operationId;
  final String eventId;
  final String? batchId;
  final String accountScopeId;
  final EventSyncOperationType operationType;
  final EventSyncConflictType conflictType;
  final int? expectedEventRevision;
  final EventModel? localProposal;
  final EventModel? baseEvent;
  final DateTime createdAt;
  final EventConflictResolutionState resolutionState;
  final EventConflictResolutionDecision? resolutionDecision;

  const EventSyncConflict({
    required this.conflictId,
    required this.operationId,
    required this.eventId,
    required this.accountScopeId,
    required this.operationType,
    required this.conflictType,
    required this.createdAt,
    required this.resolutionState,
    this.batchId,
    this.expectedEventRevision,
    this.localProposal,
    this.baseEvent,
    this.resolutionDecision,
  });

  factory EventSyncConflict.fromOperation(PendingEventSyncOperation operation) {
    final scope = operation.accountScopeId?.trim() ?? '';
    if (scope.isEmpty ||
        (operation.state != EventSyncOperationState.conflict &&
            !(operation.state == EventSyncOperationState.failed &&
                operation.attempts >= 5))) {
      throw const FormatException('invalid_event_sync_conflict');
    }
    return EventSyncConflict(
      conflictId: operation.operationId,
      operationId: operation.operationId,
      eventId: operation.eventId,
      batchId: operation.batchId,
      accountScopeId: scope,
      operationType: operation.type,
      conflictType: operation.state == EventSyncOperationState.failed
          ? EventSyncConflictType.retryExhausted
          : operation.conflictType ?? EventSyncConflictType.invalidPayload,
      expectedEventRevision: operation.expectedEventRevision,
      localProposal: operation.event,
      baseEvent: operation.baseEvent,
      createdAt: operation.createdAt,
      resolutionState: operation.resolutionState,
      resolutionDecision: operation.resolutionDecision,
    );
  }

  UnmodifiableListView<EventConflictResolutionDecision> get decisions =>
      UnmodifiableListView(conflictType == EventSyncConflictType.scopeMismatch
          ? const [EventConflictResolutionDecision.discardLocal]
          : switch (operationType) {
              EventSyncOperationType.create => const [
                  EventConflictResolutionDecision.keepCloud,
                  EventConflictResolutionDecision.discardLocal,
                  EventConflictResolutionDecision.recreateAsNew,
                ],
              EventSyncOperationType.update => const [
                  EventConflictResolutionDecision.keepCloud,
                  EventConflictResolutionDecision.discardLocal,
                  EventConflictResolutionDecision.retryAgainstLatest,
                ],
              EventSyncOperationType.delete => const [
                  EventConflictResolutionDecision.keepCloud,
                  EventConflictResolutionDecision.cancelDeletion,
                  EventConflictResolutionDecision.retryDeletion,
                ],
            });

  bool allows(EventConflictResolutionDecision decision) =>
      decisions.contains(decision);
}

final class EventConflictPresentation {
  final String title;
  final String operation;
  final String date;
  final String time;
  final String message;
  final UnmodifiableListView<EventConflictResolutionDecision> decisions;

  EventConflictPresentation({
    required this.title,
    required this.operation,
    required this.date,
    required this.time,
    required this.message,
    required List<EventConflictResolutionDecision> decisions,
  }) : decisions = UnmodifiableListView(List.of(decisions));
}

final class EventConflictResolutionResult {
  final EventConflictResolutionStatus status;
  final String diagnosticCode;
  final EventModel? event;

  const EventConflictResolutionResult._(
    this.status,
    this.diagnosticCode, [
    this.event,
  ]);

  const EventConflictResolutionResult.success([EventModel? event])
      : this._(EventConflictResolutionStatus.success,
            'event_conflict_resolution_success', event);
  const EventConflictResolutionResult.notFound()
      : this._(
            EventConflictResolutionStatus.notFound, 'event_conflict_not_found');
  const EventConflictResolutionResult.alreadyResolved()
      : this._(EventConflictResolutionStatus.alreadyResolved,
            'event_conflict_already_resolved');
  const EventConflictResolutionResult.invalidDecision()
      : this._(EventConflictResolutionStatus.invalidDecision,
            'event_conflict_invalid_decision');
  const EventConflictResolutionResult.scopeMismatch()
      : this._(EventConflictResolutionStatus.scopeMismatch,
            'event_conflict_scope_mismatch');
  const EventConflictResolutionResult.cloudChangedAgain()
      : this._(EventConflictResolutionStatus.cloudChangedAgain,
            'event_conflict_cloud_changed_again');
  const EventConflictResolutionResult.confirmationRequired()
      : this._(EventConflictResolutionStatus.confirmationRequired,
            'event_conflict_confirmation_required');
  const EventConflictResolutionResult.persistenceFailure()
      : this._(EventConflictResolutionStatus.persistenceFailure,
            'event_conflict_persistence_failure');
}
