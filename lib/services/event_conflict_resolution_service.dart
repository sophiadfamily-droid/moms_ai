import 'dart:convert';

import '../core/identity/entity_id_generator.dart';
import '../models/event_model.dart';
import '../models/event_sync_conflict.dart';
import '../models/event_sync_models.dart';
import 'event_mutation_result.dart';
import 'event_mutation_service.dart';
import 'event_sync_journal.dart';

typedef EventConflictCloudReader = Future<EventModel?> Function(String eventId);
typedef EventConflictCloudMutation = Future<EventMutationResult?> Function({
  required EventModel existing,
  required EventModel proposed,
  required int expectedEventRevision,
});
typedef EventConflictCloudDeletion = Future<EventMutationResult?> Function({
  required EventModel existing,
  required int expectedEventRevision,
});
typedef EventConflictLocalReconciler = Future<void> Function(
  String eventId,
  EventModel? event,
);
typedef EventConflictLocalCreator = Future<void> Function(EventModel event);

final class EventConflictResolutionService {
  final EventSyncJournal _journal;
  final EventConflictCloudReader _readCloud;
  final EventConflictCloudMutation _mutateCloud;
  final EventConflictCloudDeletion _deleteCloud;
  final EventConflictLocalReconciler _reconcileLocal;
  final EventConflictLocalCreator _createLocal;
  final EntityIdGenerator _idGenerator;
  final Set<String> _active = {};

  EventConflictResolutionService({
    required EventConflictCloudReader readCloud,
    required EventConflictCloudMutation mutateCloud,
    required EventConflictCloudDeletion deleteCloud,
    required EventConflictLocalReconciler reconcileLocal,
    required EventConflictLocalCreator createLocal,
    required EntityIdGenerator idGenerator,
    EventSyncJournal? journal,
  })  : _readCloud = readCloud,
        _mutateCloud = mutateCloud,
        _deleteCloud = deleteCloud,
        _reconcileLocal = reconcileLocal,
        _createLocal = createLocal,
        _idGenerator = idGenerator,
        _journal = journal ?? EventSyncJournal();

  Future<List<EventSyncConflict>> conflictsForScope(
      String accountScopeId) async {
    final scope = accountScopeId.trim();
    if (scope.isEmpty) return const [];
    final operations = await _journal.load();
    return operations
        .where((operation) => operation.accountScopeId == scope)
        .where((operation) =>
            operation.state == EventSyncOperationState.conflict ||
            (operation.state == EventSyncOperationState.failed &&
                operation.attempts >= 5))
        .map(EventSyncConflict.fromOperation)
        .toList(growable: false);
  }

  EventConflictPresentation present(EventSyncConflict conflict) {
    final event = conflict.localProposal ?? conflict.baseEvent;
    return EventConflictPresentation(
      title: event?.title ?? 'Événement',
      operation: conflict.operationType.name,
      date: event?.date ?? '',
      time: event?.time ?? '',
      message: 'Cet événement a changé ailleurs. Choisissez comment continuer.',
      decisions: conflict.decisions,
    );
  }

  Future<EventConflictResolutionResult> resolve({
    required String conflictId,
    required String accountScopeId,
    required EventConflictResolutionDecision decision,
    bool confirmed = false,
  }) async {
    if (!_active.add(conflictId)) {
      return const EventConflictResolutionResult.alreadyResolved();
    }
    try {
      final operations = await _journal.load();
      final index =
          operations.indexWhere((item) => item.operationId == conflictId);
      if (index < 0) return const EventConflictResolutionResult.notFound();
      final operation = operations[index];
      if (operation.state == EventSyncOperationState.resolved ||
          operation.state == EventSyncOperationState.discarded) {
        return const EventConflictResolutionResult.alreadyResolved();
      }
      EventSyncConflict conflict;
      try {
        conflict = EventSyncConflict.fromOperation(operation);
      } on FormatException {
        return const EventConflictResolutionResult.invalidDecision();
      }
      if (accountScopeId.trim().isEmpty ||
          operation.accountScopeId != accountScopeId) {
        return const EventConflictResolutionResult.scopeMismatch();
      }
      if (!conflict.allows(decision)) {
        return const EventConflictResolutionResult.invalidDecision();
      }
      final writesCloud =
          decision == EventConflictResolutionDecision.retryAgainstLatest ||
              decision == EventConflictResolutionDecision.recreateAsNew ||
              decision == EventConflictResolutionDecision.retryDeletion;
      if (writesCloud && !confirmed) {
        return const EventConflictResolutionResult.confirmationRequired();
      }
      final resolvingOperation = operation.copyWith(
        resolutionState: EventConflictResolutionState.resolving,
        resolutionDecision: decision,
        resolutionEventId:
            decision == EventConflictResolutionDecision.recreateAsNew
                ? operation.resolutionEventId ?? _idGenerator.generate()
                : operation.resolutionEventId,
      );
      await _journal.replace(resolvingOperation);
      final result = await _apply(resolvingOperation, decision);
      if (result.status == EventConflictResolutionStatus.success) {
        await _journal.replace(resolvingOperation.copyWith(
          state: decision == EventConflictResolutionDecision.discardLocal
              ? EventSyncOperationState.discarded
              : EventSyncOperationState.resolved,
          resolutionState:
              decision == EventConflictResolutionDecision.discardLocal
                  ? EventConflictResolutionState.discarded
                  : EventConflictResolutionState.resolved,
          resolutionDecision: decision,
        ));
      } else {
        await _journal.replace(resolvingOperation.copyWith(
          resolutionState: EventConflictResolutionState.failed,
          resolutionDecision: decision,
        ));
      }
      return result;
    } catch (_) {
      return const EventConflictResolutionResult.persistenceFailure();
    } finally {
      _active.remove(conflictId);
    }
  }

  Future<EventConflictResolutionResult> _apply(
    PendingEventSyncOperation operation,
    EventConflictResolutionDecision decision,
  ) async {
    if (decision == EventConflictResolutionDecision.recreateAsNew) {
      final source = operation.event;
      if (source == null) {
        return const EventConflictResolutionResult.invalidDecision();
      }
      final recreated = EventMutationService.duplicate(source).copyWith(
        id: operation.resolutionEventId,
        eventRevision: 1,
      );
      await _createLocal(recreated);
      return EventConflictResolutionResult.success(recreated);
    }

    final cloud = await _readCloud(operation.eventId);
    if (decision == EventConflictResolutionDecision.keepCloud ||
        decision == EventConflictResolutionDecision.discardLocal ||
        decision == EventConflictResolutionDecision.cancelDeletion) {
      await _reconcileLocal(operation.eventId, cloud);
      return const EventConflictResolutionResult.success();
    }
    if (decision == EventConflictResolutionDecision.retryDeletion) {
      if (cloud == null) {
        await _reconcileLocal(operation.eventId, null);
        return const EventConflictResolutionResult.success();
      }
      final result = await _deleteCloud(
        existing: cloud,
        expectedEventRevision: cloud.eventRevision,
      );
      if (result?.status == EventMutationStatus.success ||
          result?.status == EventMutationStatus.notFound) {
        await _reconcileLocal(operation.eventId, null);
        return const EventConflictResolutionResult.success();
      }
      if (result?.status == EventMutationStatus.revisionConflict) {
        return const EventConflictResolutionResult.cloudChangedAgain();
      }
      return const EventConflictResolutionResult.persistenceFailure();
    }
    if (cloud == null) return const EventConflictResolutionResult.notFound();
    final base = operation.baseEvent;
    final local = operation.event;
    if (base == null || local == null || !_sameParticipant(base, local)) {
      return const EventConflictResolutionResult.invalidDecision();
    }
    final rebased =
        _rebaseStandardChanges(base: base, local: local, cloud: cloud);
    final proposed =
        EventMutationService.apply(existing: cloud, proposed: rebased)
            .copyWith(eventRevision: cloud.eventRevision + 1);
    final result = await _mutateCloud(
      existing: cloud,
      proposed: proposed,
      expectedEventRevision: cloud.eventRevision,
    );
    if (result?.status == EventMutationStatus.success) {
      await _reconcileLocal(operation.eventId, result!.event ?? proposed);
      return EventConflictResolutionResult.success(result.event ?? proposed);
    }
    if (result?.status == EventMutationStatus.revisionConflict) {
      return const EventConflictResolutionResult.cloudChangedAgain();
    }
    return const EventConflictResolutionResult.persistenceFailure();
  }

  static EventModel _rebaseStandardChanges({
    required EventModel base,
    required EventModel local,
    required EventModel cloud,
  }) {
    return cloud.copyWith(
      title: base.title == local.title ? cloud.title : local.title,
      date: base.date == local.date ? cloud.date : local.date,
      time: base.time == local.time ? cloud.time : local.time,
      notes: base.notes == local.notes ? cloud.notes : local.notes,
      category:
          base.category == local.category ? cloud.category : local.category,
      startDateTimeIso: base.startDateTimeIso == local.startDateTimeIso
          ? cloud.startDateTimeIso
          : local.startDateTimeIso,
      endTime: base.endTime == local.endTime ? cloud.endTime : local.endTime,
      endDateTimeIso: base.endDateTimeIso == local.endDateTimeIso
          ? cloud.endDateTimeIso
          : local.endDateTimeIso,
      durationMinutes: base.durationMinutes == local.durationMinutes
          ? cloud.durationMinutes
          : local.durationMinutes,
      travelMinutes: base.travelMinutes == local.travelMinutes
          ? cloud.travelMinutes
          : local.travelMinutes,
      travelGoMinutes: base.travelGoMinutes == local.travelGoMinutes
          ? cloud.travelGoMinutes
          : local.travelGoMinutes,
      travelBackMinutes: base.travelBackMinutes == local.travelBackMinutes
          ? cloud.travelBackMinutes
          : local.travelBackMinutes,
      usesSeparateTravelTimes:
          base.usesSeparateTravelTimes == local.usesSeparateTravelTimes
              ? cloud.usesSeparateTravelTimes
              : local.usesSeparateTravelTimes,
      marginMinutes: base.marginMinutes == local.marginMinutes
          ? cloud.marginMinutes
          : local.marginMinutes,
      departureContext: base.departureContext == local.departureContext
          ? cloud.departureContext
          : local.departureContext,
      arrivalContext: base.arrivalContext == local.arrivalContext
          ? cloud.arrivalContext
          : local.arrivalContext,
      isRecurring: base.isRecurring == local.isRecurring
          ? cloud.isRecurring
          : local.isRecurring,
      recurringType: base.recurringType == local.recurringType
          ? cloud.recurringType
          : local.recurringType,
      recurringWeekday: base.recurringWeekday == local.recurringWeekday
          ? cloud.recurringWeekday
          : local.recurringWeekday,
      recurringUntil: base.recurringUntil == local.recurringUntil
          ? cloud.recurringUntil
          : local.recurringUntil,
      parentRecurringId: base.parentRecurringId == local.parentRecurringId
          ? cloud.parentRecurringId
          : local.parentRecurringId,
    );
  }

  static bool _sameParticipant(EventModel first, EventModel second) =>
      first.participantIdentityRevision == second.participantIdentityRevision &&
      jsonEncode(first.participantIdentity?.toJson()) ==
          jsonEncode(second.participantIdentity?.toJson());
}
