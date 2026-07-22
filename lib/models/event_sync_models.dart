import 'dart:collection';

import 'event_model.dart';

enum EventSyncOperationType { create, update, delete }

enum EventSyncOperationState {
  pending,
  inFlight,
  applied,
  conflict,
  failed,
  cancelled,
  resolved,
  discarded,
}

enum EventSyncConflictType {
  revisionConflict,
  alreadyExists,
  notFound,
  scopeMismatch,
  invalidPayload,
  partialBatch,
  persistenceFailure,
  retryExhausted,
}

enum EventConflictResolutionState {
  unresolved,
  resolving,
  resolved,
  discarded,
  failed
}

enum EventConflictResolutionDecision {
  keepCloud,
  discardLocal,
  retryAgainstLatest,
  recreateAsNew,
  cancelDeletion,
  retryDeletion,
}

final class PendingEventSyncOperation {
  static const int currentSchemaVersion = 2;

  final String operationId;
  final String eventId;
  final String? accountScopeId;
  final EventSyncOperationType type;
  final int? expectedEventRevision;
  final EventModel? event;
  final EventModel? baseEvent;
  final String batchId;
  final DateTime createdAt;
  final int attempts;
  final EventSyncOperationState state;
  final EventSyncConflictType? conflictType;
  final int schemaVersion;
  final EventConflictResolutionState resolutionState;
  final EventConflictResolutionDecision? resolutionDecision;
  final String? resolutionEventId;

  PendingEventSyncOperation({
    required this.operationId,
    required this.eventId,
    this.accountScopeId,
    required this.type,
    required this.batchId,
    required this.createdAt,
    required this.state,
    this.expectedEventRevision,
    this.event,
    this.baseEvent,
    this.attempts = 0,
    this.conflictType,
    this.schemaVersion = currentSchemaVersion,
    this.resolutionState = EventConflictResolutionState.unresolved,
    this.resolutionDecision,
    this.resolutionEventId,
  }) {
    if (operationId.trim().isEmpty ||
        eventId.trim().isEmpty ||
        (accountScopeId != null && accountScopeId!.trim().isEmpty) ||
        batchId.trim().isEmpty ||
        (schemaVersion < 1 || schemaVersion > currentSchemaVersion) ||
        attempts < 0 ||
        (resolutionEventId != null &&
            (resolutionEventId!.trim().isEmpty ||
                type != EventSyncOperationType.create)) ||
        ((type == EventSyncOperationType.update ||
                type == EventSyncOperationType.delete) &&
            (expectedEventRevision == null || expectedEventRevision! < 0)) ||
        (type != EventSyncOperationType.delete && event == null) ||
        (type == EventSyncOperationType.delete && event != null) ||
        (type == EventSyncOperationType.create && event?.eventRevision != 1) ||
        (type == EventSyncOperationType.update &&
            event?.eventRevision != expectedEventRevision! + 1) ||
        (baseEvent != null &&
            (type != EventSyncOperationType.update ||
                baseEvent!.id != eventId ||
                baseEvent!.eventRevision != expectedEventRevision)) ||
        (event != null && event!.id != eventId)) {
      throw const FormatException('invalid_event_sync_operation');
    }
  }

  bool get isTerminal =>
      state == EventSyncOperationState.applied ||
      state == EventSyncOperationState.cancelled;

  PendingEventSyncOperation copyWith({
    int? attempts,
    EventSyncOperationState? state,
    EventSyncConflictType? conflictType,
    bool clearConflict = false,
    EventConflictResolutionState? resolutionState,
    EventConflictResolutionDecision? resolutionDecision,
    String? resolutionEventId,
  }) {
    return PendingEventSyncOperation(
      operationId: operationId,
      eventId: eventId,
      accountScopeId: accountScopeId,
      type: type,
      expectedEventRevision: expectedEventRevision,
      event: event,
      baseEvent: baseEvent,
      batchId: batchId,
      createdAt: createdAt,
      attempts: attempts ?? this.attempts,
      state: state ?? this.state,
      conflictType: clearConflict ? null : conflictType ?? this.conflictType,
      schemaVersion: schemaVersion,
      resolutionState: resolutionState ?? this.resolutionState,
      resolutionDecision: resolutionDecision ?? this.resolutionDecision,
      resolutionEventId: resolutionEventId ?? this.resolutionEventId,
    );
  }

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'operationId': operationId,
        'eventId': eventId,
        if (accountScopeId != null) 'accountScopeId': accountScopeId,
        'type': type.name,
        if (expectedEventRevision != null)
          'expectedEventRevision': expectedEventRevision,
        if (event != null) 'event': event!.toJson(),
        if (baseEvent != null) 'baseEvent': baseEvent!.toJson(),
        'batchId': batchId,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'attempts': attempts,
        'state': state.name,
        if (conflictType != null) 'conflictType': conflictType!.name,
        'resolutionState': resolutionState.name,
        if (resolutionDecision != null)
          'resolutionDecision': resolutionDecision!.name,
        if (resolutionEventId != null) 'resolutionEventId': resolutionEventId,
      };

  factory PendingEventSyncOperation.fromJson(Map<String, dynamic> json) {
    try {
      const allowedKeys = {
        'schemaVersion',
        'operationId',
        'eventId',
        'accountScopeId',
        'type',
        'expectedEventRevision',
        'event',
        'baseEvent',
        'batchId',
        'createdAt',
        'attempts',
        'state',
        'conflictType',
        'resolutionState',
        'resolutionDecision',
        'resolutionEventId',
      };
      if (json.keys.any((key) => !allowedKeys.contains(key))) {
        throw const FormatException('invalid_event_sync_operation');
      }
      final type = EventSyncOperationType.values.byName(json['type'] as String);
      final state =
          EventSyncOperationState.values.byName(json['state'] as String);
      final rawEvent = json['event'];
      final rawBaseEvent = json['baseEvent'];
      return PendingEventSyncOperation(
        operationId: json['operationId'] as String,
        eventId: json['eventId'] as String,
        accountScopeId: json['accountScopeId'] as String?,
        type: type,
        expectedEventRevision: json['expectedEventRevision'] as int?,
        event: rawEvent is Map
            ? EventModel.fromJson(Map<String, dynamic>.from(rawEvent))
            : null,
        baseEvent: rawBaseEvent is Map
            ? EventModel.fromJson(Map<String, dynamic>.from(rawBaseEvent))
            : null,
        batchId: json['batchId'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
        attempts: json['attempts'] as int,
        state: state,
        conflictType: json['conflictType'] == null
            ? null
            : EventSyncConflictType.values
                .byName(json['conflictType'] as String),
        schemaVersion: json['schemaVersion'] as int,
        resolutionState: json['resolutionState'] == null
            ? EventConflictResolutionState.unresolved
            : EventConflictResolutionState.values
                .byName(json['resolutionState'] as String),
        resolutionDecision: json['resolutionDecision'] == null
            ? null
            : EventConflictResolutionDecision.values
                .byName(json['resolutionDecision'] as String),
        resolutionEventId: json['resolutionEventId'] as String?,
      );
    } catch (_) {
      throw const FormatException('invalid_event_sync_operation');
    }
  }
}

enum EventSyncStatus { synchronized, pending, conflicts, failed }

final class EventSyncResult {
  final EventSyncStatus status;
  final int appliedCount;
  final int conflictCount;
  final int failureCount;
  final UnmodifiableListView<PendingEventSyncOperation> remaining;

  EventSyncResult({
    required this.status,
    required this.appliedCount,
    required this.conflictCount,
    required this.failureCount,
    required List<PendingEventSyncOperation> remaining,
  }) : remaining = UnmodifiableListView(List.of(remaining));
}

enum EventSyncBatchPolicy { explicitPartial }

final class EventSyncBatch {
  static const int currentSchemaVersion = 1;

  final String batchId;
  final EventSyncBatchPolicy policy;
  final UnmodifiableListView<PendingEventSyncOperation> operations;
  final int schemaVersion;

  EventSyncBatch({
    required this.batchId,
    required List<PendingEventSyncOperation> operations,
    this.policy = EventSyncBatchPolicy.explicitPartial,
    this.schemaVersion = currentSchemaVersion,
  }) : operations = UnmodifiableListView(List.of(operations)) {
    if (batchId.trim().isEmpty ||
        schemaVersion != currentSchemaVersion ||
        operations.isEmpty ||
        operations.any((operation) => operation.batchId != batchId)) {
      throw const FormatException('invalid_event_sync_batch');
    }
  }

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'batchId': batchId,
        'policy': policy.name,
        'operations':
            operations.map((operation) => operation.toJson()).toList(),
      };

  factory EventSyncBatch.fromJson(Map<String, dynamic> json) {
    try {
      const allowedKeys = {
        'schemaVersion',
        'batchId',
        'policy',
        'operations',
      };
      if (json.keys.any((key) => !allowedKeys.contains(key))) {
        throw const FormatException('invalid_event_sync_batch');
      }
      final rawOperations = json['operations'];
      if (rawOperations is! List) {
        throw const FormatException('invalid_event_sync_batch');
      }
      return EventSyncBatch(
        batchId: json['batchId'] as String,
        policy: EventSyncBatchPolicy.values.byName(json['policy'] as String),
        operations: rawOperations
            .map(
              (operation) => PendingEventSyncOperation.fromJson(
                Map<String, dynamic>.from(operation as Map),
              ),
            )
            .toList(),
        schemaVersion: json['schemaVersion'] as int,
      );
    } catch (_) {
      throw const FormatException('invalid_event_sync_batch');
    }
  }
}
