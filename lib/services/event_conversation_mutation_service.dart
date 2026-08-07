import 'dart:convert';

import '../models/event_model.dart';
import '../models/event_mutation_models.dart';
import 'event_mutation_service.dart';
import 'event_mutation_result.dart';
import 'event_mutation_invariant_service.dart';
import 'event_service.dart';
import 'event_target_selector.dart';
import 'routine/routine_planning_blocker_service.dart';

typedef EventMutationLoader = Future<List<EventModel>> Function();
typedef EventMutationWriter = Future<EventMutationResult> Function({
  required EventModel existing,
  required EventModel proposed,
  required int expectedEventRevision,
  required EventParticipantMutationIntent participantIntent,
});
typedef EventMutationPlanningBlockerLoader = Future<List<EventModel>> Function(
  EventModel proposed,
);

enum EventMutationExecutionStatus {
  updated,
  notFound,
  concurrentChange,
  conflict,
  verificationUnavailable,
  invalid,
}

final class EventMutationExecutionResult {
  final EventMutationExecutionStatus status;
  final String diagnosticCode;

  const EventMutationExecutionResult(this.status, this.diagnosticCode);
}

final class EventConversationMutationService {
  final EventMutationLoader _loadEvents;
  final EventMutationWriter _write;
  final EventMutationPlanningBlockerLoader? _loadPlanningBlockers;

  EventConversationMutationService({
    EventMutationLoader? loadEvents,
    EventMutationWriter? write,
    EventMutationPlanningBlockerLoader? loadPlanningBlockers,
  })  : _loadEvents = loadEvents ?? EventService.getEvents,
        _write = write ?? EventService.mutateEvent,
        _loadPlanningBlockers = loadPlanningBlockers;

  factory EventConversationMutationService.production({
    required String? accountScopeId,
  }) {
    final routinePlanningBlockers = RoutinePlanningBlockerService.production();
    return EventConversationMutationService(
      loadPlanningBlockers: (proposed) async {
        final scope = accountScopeId?.trim();
        final start = EventService.parseStart(proposed);
        if (scope == null || scope.isEmpty || start == null) {
          throw StateError('event_mutation_planning_context_unavailable');
        }
        return routinePlanningBlockers.load(
          accountScopeId: scope,
          startDay: start,
        );
      },
    );
  }

  Future<EventTargetSelectionResult> select(
      EventMutationRequest request) async {
    return EventTargetSelector.select(
      events: await _loadEvents(),
      target: request.target,
    );
  }

  Future<EventTargetSelectionResult> selectVerifiedIds(
    List<String> eventIds,
  ) async {
    final ids = eventIds
        .where((id) => id.trim().isNotEmpty)
        .map((id) => id.trim())
        .toSet();
    final matches = (await _loadEvents())
        .where((event) => event.id != null && ids.contains(event.id))
        .toList()
      ..sort((first, second) => first.id!.compareTo(second.id!));
    if (matches.isEmpty) {
      return EventTargetSelectionResult(
        status: EventTargetSelectionStatus.notFound,
        diagnosticCode: 'event_reference_ids_not_found',
      );
    }
    if (matches.length == 1) {
      return EventTargetSelectionResult(
        status: EventTargetSelectionStatus.selected,
        selected: matches.single,
        diagnosticCode: 'event_reference_id_verified',
      );
    }
    return EventTargetSelectionResult(
      status: EventTargetSelectionStatus.ambiguous,
      candidates: matches.take(EventTargetSelector.maxCandidates).toList(),
      diagnosticCode: 'event_reference_ids_ambiguous',
    );
  }

  Future<EventTargetSelectionResult> revalidateClarificationCandidate({
    required String eventId,
    required EventModel presented,
    required EventMutationRequest request,
  }) async {
    final events = await _loadEvents();
    final current = events.where((event) => event.id == eventId).firstOrNull;
    if (current == null ||
        jsonEncode(current.toJson()) != jsonEncode(presented.toJson())) {
      return EventTargetSelectionResult(
        status: EventTargetSelectionStatus.notFound,
        diagnosticCode: 'event_clarification_candidate_changed',
      );
    }
    final matching = EventTargetSelector.select(
      events: [current],
      target: request.target,
    );
    if (matching.status != EventTargetSelectionStatus.selected) {
      return EventTargetSelectionResult(
        status: EventTargetSelectionStatus.notFound,
        diagnosticCode: 'event_clarification_constraints_changed',
      );
    }
    return EventTargetSelectionResult(
      status: EventTargetSelectionStatus.selected,
      selected: current,
      diagnosticCode: 'event_clarification_candidate_revalidated',
    );
  }

  EventModel propose(EventModel original, EventMutationChanges changes) {
    final date = changes.date ?? original.date;
    final time = changes.time ?? original.time;
    final duration = changes.durationMinutes ?? original.durationMinutes;
    final start = DateTime.tryParse('${date}T$time:00');
    final end = start?.add(Duration(minutes: duration));
    return original.copyWith(
      title: changes.title,
      date: changes.date,
      time: changes.time,
      durationMinutes: changes.durationMinutes,
      travelGoMinutes: changes.travelGoMinutes,
      travelBackMinutes: changes.travelBackMinutes,
      usesSeparateTravelTimes:
          changes.travelGoMinutes != null || changes.travelBackMinutes != null
              ? true
              : null,
      travelMinutes: changes.travelGoMinutes != null ||
              changes.travelBackMinutes != null
          ? (changes.travelGoMinutes ?? original.resolvedTravelGoMinutes) +
              (changes.travelBackMinutes ?? original.resolvedTravelBackMinutes)
          : null,
      marginMinutes: changes.marginMinutes,
      notes: changes.notes,
      category: changes.category,
      startDateTimeIso: start?.toIso8601String(),
      endDateTimeIso: end?.toIso8601String(),
      endTime: end == null
          ? null
          : '${end.hour.toString().padLeft(2, '0')}:'
              '${end.minute.toString().padLeft(2, '0')}',
    );
  }

  Future<EventMutationExecutionResult> execute({
    required EventModel original,
    required EventModel proposed,
    EventParticipantMutationIntent participantIntent =
        const PreserveEventParticipant(),
  }) async {
    final events = await _loadEvents();
    final current =
        events.where((event) => event.id == original.id).firstOrNull;
    if (current == null) {
      return const EventMutationExecutionResult(
        EventMutationExecutionStatus.notFound,
        'event_mutation_target_disappeared',
      );
    }
    if (jsonEncode(current.toJson()) != jsonEncode(original.toJson())) {
      return const EventMutationExecutionResult(
        EventMutationExecutionStatus.concurrentChange,
        'event_mutation_concurrent_change',
      );
    }
    List<EventModel> planningBlockers = const [];
    final blockerLoader = _loadPlanningBlockers;
    if (blockerLoader != null) {
      try {
        planningBlockers = await blockerLoader(proposed);
      } catch (_) {
        return const EventMutationExecutionResult(
          EventMutationExecutionStatus.verificationUnavailable,
          'event_mutation_planning_verification_unavailable',
        );
      }
    }
    final validation = EventMutationInvariantService.validate(
      existing: current,
      proposed: proposed,
      events: [...events, ...planningBlockers],
    );
    if (validation.status == EventMutationInvariantStatus.planningConflict) {
      return const EventMutationExecutionResult(
        EventMutationExecutionStatus.conflict,
        'event_mutation_conflict',
      );
    }
    if (validation.status != EventMutationInvariantStatus.valid) {
      return EventMutationExecutionResult(
        EventMutationExecutionStatus.invalid,
        validation.diagnosticCode,
      );
    }
    try {
      final writeResult = await _write(
        existing: current,
        proposed: proposed,
        expectedEventRevision: original.eventRevision,
        participantIntent: participantIntent,
      );
      if (writeResult.status == EventMutationStatus.notFound) {
        return const EventMutationExecutionResult(
          EventMutationExecutionStatus.notFound,
          'event_mutation_target_disappeared',
        );
      }
      if (writeResult.status != EventMutationStatus.success) {
        return EventMutationExecutionResult(
          writeResult.status == EventMutationStatus.revisionConflict
              ? EventMutationExecutionStatus.concurrentChange
              : EventMutationExecutionStatus.invalid,
          writeResult.diagnosticCode,
        );
      }
      return const EventMutationExecutionResult(
        EventMutationExecutionStatus.updated,
        'event_mutation_updated',
      );
    } on FormatException {
      return const EventMutationExecutionResult(
        EventMutationExecutionStatus.concurrentChange,
        'event_mutation_concurrent_change',
      );
    }
  }
}
