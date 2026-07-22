import 'dart:convert';

import '../models/event_model.dart';
import '../models/event_mutation_models.dart';
import 'event_mutation_service.dart';
import 'event_service.dart';
import 'event_target_selector.dart';

typedef EventMutationLoader = Future<List<EventModel>> Function();
typedef EventMutationWriter = Future<void> Function({
  required EventModel existing,
  required EventModel proposed,
  required EventParticipantMutationIntent participantIntent,
});

enum EventMutationExecutionStatus {
  updated,
  notFound,
  concurrentChange,
  conflict,
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

  EventConversationMutationService({
    EventMutationLoader? loadEvents,
    EventMutationWriter? write,
  })  : _loadEvents = loadEvents ?? EventService.getEvents,
        _write = write ?? EventService.mutateEvent;

  Future<EventTargetSelectionResult> select(
      EventMutationRequest request) async {
    return EventTargetSelector.select(
      events: await _loadEvents(),
      target: request.target,
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
    final conflict = events.any(
      (event) =>
          event.id != current.id &&
          EventService.eventsProtectedOverlap(event, proposed),
    );
    if (conflict) {
      return const EventMutationExecutionResult(
        EventMutationExecutionStatus.conflict,
        'event_mutation_conflict',
      );
    }
    try {
      await _write(
        existing: current,
        proposed: proposed,
        participantIntent: const PreserveEventParticipant(),
      );
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
