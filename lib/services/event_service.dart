import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/identity/entity_id_generator.dart';
import '../core/identity/entity_identity.dart';
import '../core/identity/entity_matcher.dart';
import '../core/identity/uuid_v7_entity_id_generator.dart';
import '../models/event_model.dart';
import 'cloud_event_service.dart';
import 'event_mutation_service.dart';
import 'event_mutation_result.dart';

typedef EventCloudMutation = Future<EventMutationResult?> Function({
  required EventModel existing,
  required EventModel proposed,
  required int expectedEventRevision,
});

typedef EventCloudDeletion = Future<EventMutationResult?> Function({
  required EventModel existing,
  required int expectedEventRevision,
});

class EventService {
  static const String eventsKey = "zelia_events";

  static final EntityMatcher<EventModel> _eventMatcher = EntityMatcher(
    idOf: (event) => event.id,
    legacyEquals: (first, second) {
      return first.title == second.title &&
          first.createdAt == second.createdAt &&
          first.date == second.date &&
          first.time == second.time;
    },
  );

  static final ValueNotifier<int> eventsVersion = ValueNotifier<int>(0);

  static void notifyEventsChanged() {
    eventsVersion.value++;
  }

  static Future<void> saveEvents(
    List<EventModel> events,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(eventsKey) ?? const [];
    final existing = stored
        .map(
          (event) => EventModel.fromJson(
            Map<String, dynamic>.from(jsonDecode(event) as Map),
          ),
        )
        .toList(growable: false);
    final reconciled = EventMutationService.reconcileFullRewrite(
      existing: existing,
      proposed: events,
    );
    _validateFullRewriteRevisions(existing: existing, proposed: reconciled);

    final encoded = reconciled
        .map(
          (event) => jsonEncode(event.toJson()),
        )
        .toList();

    await prefs.setStringList(
      eventsKey,
      encoded,
    );

    try {
      await CloudEventService.saveEvents(reconciled);
    } catch (_) {
      // L'agenda reste disponible hors ligne ou sans compte connecté.
    }

    notifyEventsChanged();
  }

  static Future<List<EventModel>> getEvents() async {
    final prefs = await SharedPreferences.getInstance();

    final data = prefs.getStringList(eventsKey);

    final localEvents = data == null
        ? <EventModel>[]
        : data
            .map(
              (event) => EventModel.fromJson(
                jsonDecode(event),
              ),
            )
            .toList();

    try {
      final cloudEvents = await CloudEventService.getEvents();

      if (cloudEvents.isNotEmpty) {
        final encoded = cloudEvents
            .map(
              (event) => jsonEncode(event.toJson()),
            )
            .toList();

        await prefs.setStringList(
          eventsKey,
          encoded,
        );

        return cloudEvents;
      }

      if (localEvents.isNotEmpty) {
        await CloudEventService.saveEvents(localEvents);
      }
    } catch (_) {
      // Si Firestore est indisponible, on utilise l'agenda local.
    }

    return localEvents;
  }

  static Future<void> addEvent(
    EventModel event, {
    EntityIdGenerator idGenerator = const UuidV7EntityIdGenerator(),
  }) async {
    final events = await getEvents();

    events.add(_withIdForCreation(event, idGenerator));

    await saveEvents(events);
  }

  static Future<void> addEvents(
    List<EventModel> newEvents, {
    EntityIdGenerator idGenerator = const UuidV7EntityIdGenerator(),
  }) async {
    final events = await getEvents();

    events.addAll(
      newEvents.map((event) => _withIdForCreation(event, idGenerator)),
    );

    await saveEvents(events);
  }

  static Future<void> updateEvents(
    List<EventModel> events,
  ) async {
    await saveEvents(events);
  }

  static Future<EventMutationResult> mutateEvent({
    required EventModel existing,
    required EventModel proposed,
    required int expectedEventRevision,
    EventParticipantMutationIntent participantIntent =
        const PreserveEventParticipant(),
    EventCloudMutation cloudMutate = CloudEventService.mutateEvent,
  }) async {
    final events = await getEvents();
    final index = events.indexWhere(
      (event) => areSameEvent(event, existing),
    );
    if (index < 0) return const EventMutationResult.notFound();
    final current = events[index];
    if (expectedEventRevision < 0 ||
        current.eventRevision != expectedEventRevision) {
      return const EventMutationResult.revisionConflict();
    }
    try {
      final next = EventMutationService.apply(
        existing: current,
        proposed: proposed,
        participantIntent: participantIntent,
      ).copyWith(eventRevision: current.eventRevision + 1);
      final cloudResult = await cloudMutate(
        existing: current,
        proposed: next,
        expectedEventRevision: expectedEventRevision,
      );
      if (cloudResult != null &&
          cloudResult.status != EventMutationStatus.success) {
        return cloudResult;
      }
      events[index] = next;
      await _writeLocalEvents(events);
      notifyEventsChanged();
      return EventMutationResult.success(next);
    } on FormatException {
      return const EventMutationResult.invalid();
    } catch (_) {
      return const EventMutationResult.persistenceFailure();
    }
  }

  static Future<EventMutationResult> deleteEvent({
    required EventModel existing,
    required int expectedEventRevision,
    EventCloudDeletion cloudDelete = CloudEventService.deleteEvent,
  }) async {
    final events = await getEvents();
    final index = events.indexWhere((event) => areSameEvent(event, existing));
    if (index < 0) return const EventMutationResult.notFound();
    if (events[index].eventRevision != expectedEventRevision) {
      return const EventMutationResult.revisionConflict();
    }
    try {
      final cloudResult = await cloudDelete(
        existing: events[index],
        expectedEventRevision: expectedEventRevision,
      );
      if (cloudResult != null &&
          cloudResult.status != EventMutationStatus.success) {
        return cloudResult;
      }
      final removed = events.removeAt(index);
      await _writeLocalEvents(events);
      notifyEventsChanged();
      return EventMutationResult.success(removed);
    } catch (_) {
      return const EventMutationResult.persistenceFailure();
    }
  }

  static Future<void> _writeLocalEvents(List<EventModel> events) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      eventsKey,
      events.map((event) => jsonEncode(event.toJson())).toList(),
    );
  }

  static void _validateFullRewriteRevisions({
    required List<EventModel> existing,
    required List<EventModel> proposed,
  }) {
    final proposedById = {
      for (final event in proposed)
        if (EntityIdentity.isValid(event.id)) event.id!: event,
    };
    for (final current in existing) {
      if (!EntityIdentity.isValid(current.id)) continue;
      final next = proposedById[current.id];
      if (next == null) continue;
      if (jsonEncode(current.toJson()) == jsonEncode(next.toJson())) continue;
      if (next.eventRevision != current.eventRevision + 1) {
        throw const FormatException('event_mutation_revision_required');
      }
    }
  }

  static Future<void> duplicateEvent(
    EventModel source, {
    EntityIdGenerator idGenerator = const UuidV7EntityIdGenerator(),
  }) {
    return addEvent(
      EventMutationService.duplicate(source),
      idGenerator: idGenerator,
    );
  }

  static EventModel _withIdForCreation(
    EventModel event,
    EntityIdGenerator idGenerator,
  ) {
    final creation =
        event.eventRevision == 1 ? event : event.copyWith(eventRevision: 1);
    if (EntityIdentity.isValid(creation.id)) return creation;
    final generatedId = idGenerator.generate();
    return creation.copyWith(id: generatedId);
  }

  static bool areSameEvent(EventModel first, EventModel second) {
    return _eventMatcher.matches(first, second);
  }

  static DateTime? parseStart(EventModel event) {
    if (event.startDateTimeIso.isNotEmpty) {
      return DateTime.tryParse(event.startDateTimeIso);
    }

    if (event.date.isEmpty || event.time.isEmpty) {
      return null;
    }

    return DateTime.tryParse(
      "${event.date}T${event.time}:00",
    );
  }

  static DateTime? parseEnd(EventModel event) {
    if (event.endDateTimeIso.isNotEmpty) {
      return DateTime.tryParse(event.endDateTimeIso);
    }

    final start = parseStart(event);

    if (start == null) {
      return null;
    }

    final minutes = event.durationMinutes > 0 ? event.durationMinutes : 60;

    return start.add(
      Duration(minutes: minutes),
    );
  }

  static DateTime? parseProtectedStart(EventModel event) {
    final start = parseStart(event);

    if (start == null) {
      return null;
    }

    return start.subtract(
      Duration(minutes: event.resolvedTravelGoMinutes),
    );
  }

  static DateTime? parseProtectedEnd(EventModel event) {
    final end = parseEnd(event);

    if (end == null) {
      return null;
    }

    return end.add(
      Duration(
        minutes: event.resolvedTravelBackMinutes + event.marginMinutes,
      ),
    );
  }

  static bool eventsOverlap(
    EventModel first,
    EventModel second,
  ) {
    final firstStart = parseStart(first);
    final firstEnd = parseEnd(first);
    final secondStart = parseStart(second);
    final secondEnd = parseEnd(second);

    if (firstStart == null ||
        firstEnd == null ||
        secondStart == null ||
        secondEnd == null) {
      return false;
    }

    return firstStart.isBefore(secondEnd) && secondStart.isBefore(firstEnd);
  }

  static bool eventsProtectedOverlap(
    EventModel first,
    EventModel second,
  ) {
    final firstStart = parseProtectedStart(first);
    final firstEnd = parseProtectedEnd(first);
    final secondStart = parseProtectedStart(second);
    final secondEnd = parseProtectedEnd(second);

    if (firstStart == null ||
        firstEnd == null ||
        secondStart == null ||
        secondEnd == null) {
      return false;
    }

    return firstStart.isBefore(secondEnd) && secondStart.isBefore(firstEnd);
  }

  static Future<bool> hasConflict({
    required String startDateTimeIso,
  }) async {
    final events = await getEvents();

    for (final event in events) {
      if (event.startDateTimeIso == startDateTimeIso) {
        return true;
      }
    }

    return false;
  }

  static Future<EventModel?> getConflictEvent({
    required String startDateTimeIso,
  }) async {
    final events = await getEvents();

    for (final event in events) {
      if (event.startDateTimeIso == startDateTimeIso) {
        return event;
      }
    }

    return null;
  }

  static Future<EventModel?> getOverlapConflict({
    required EventModel candidate,
  }) async {
    final events = await getEvents();

    for (final event in events) {
      if (eventsProtectedOverlap(event, candidate)) {
        return event;
      }
    }

    return null;
  }

  static String formatIsoDate(DateTime date) {
    final y = date.year.toString();
    final m = date.month.toString().padLeft(2, "0");
    final d = date.day.toString().padLeft(2, "0");

    return "$y-$m-$d";
  }

  static String formatIsoTime(DateTime date) {
    final h = date.hour.toString().padLeft(2, "0");
    final m = date.minute.toString().padLeft(2, "0");

    return "$h:$m";
  }

  static List<EventModel> buildWeeklyOccurrences({
    required EventModel baseEvent,
    required int count,
  }) {
    final start = parseStart(baseEvent);

    if (start == null) {
      return [baseEvent];
    }

    final occurrences = <EventModel>[];

    final safeCount = count <= 0 ? 52 : count;

    final parentId = DateTime.now().microsecondsSinceEpoch.toString();

    for (var index = 0; index < safeCount; index++) {
      final occurrenceStart = start.add(
        Duration(days: index * 7),
      );

      final duration =
          baseEvent.durationMinutes > 0 ? baseEvent.durationMinutes : 60;

      final occurrenceEnd = occurrenceStart.add(
        Duration(minutes: duration),
      );

      final date = formatIsoDate(occurrenceStart);
      final time = formatIsoTime(occurrenceStart);
      final endDate = formatIsoDate(occurrenceEnd);
      final endTime = formatIsoTime(occurrenceEnd);

      occurrences.add(
        baseEvent.copyWith(
          clearId: true,
          eventRevision: 1,
          date: date,
          time: time,
          startDateTimeIso: "${date}T$time:00",
          endTime: endTime,
          endDateTimeIso: "${endDate}T$endTime:00",
          durationMinutes: duration,
          isRecurring: true,
          recurringType: "weekly",
          recurringWeekday: occurrenceStart.weekday,
          parentRecurringId: parentId,
        ),
      );
    }

    return occurrences;
  }
}
