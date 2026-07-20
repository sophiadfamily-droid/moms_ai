import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/services/cloud_event_service.dart';
import 'package:moms_ai/services/event_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_entity_id_generator.dart';

void main() {
  EventModel buildEvent({
    String? id,
    String title = 'Dentiste',
    String startDateTimeIso = '2026-07-21T10:00:00',
    String parentRecurringId = '',
  }) {
    return EventModel(
      id: id,
      title: title,
      date: startDateTimeIso.substring(0, 10),
      time: startDateTimeIso.substring(11, 16),
      notes: '',
      category: 'Santé',
      createdAt: DateTime(2026, 7, 20),
      startDateTimeIso: startDateTimeIso,
      endTime: '10:45',
      endDateTimeIso: '2026-07-21T10:45:00',
      durationMinutes: 45,
      isRecurring: parentRecurringId.isNotEmpty,
      recurringType: parentRecurringId.isEmpty ? '' : 'weekly',
      recurringWeekday: parentRecurringId.isEmpty ? 0 : DateTime.tuesday,
      parentRecurringId: parentRecurringId,
    );
  }

  EventModel buildCompleteEvent() {
    return EventModel(
      title: 'Dentiste complet',
      date: '2026-07-21',
      time: '10:00',
      notes: 'Toutes les métadonnées',
      category: 'Santé',
      createdAt: DateTime(2026, 7, 20, 8, 30),
      startDateTimeIso: '2026-07-21T10:00:00',
      endTime: '10:45',
      endDateTimeIso: '2026-07-21T10:45:00',
      durationMinutes: 45,
      travelMinutes: 35,
      travelGoMinutes: 15,
      travelBackMinutes: 20,
      usesSeparateTravelTimes: true,
      marginMinutes: 10,
      departureContext: 'home',
      arrivalContext: 'work',
      isRecurring: true,
      recurringType: 'weekly',
      recurringWeekday: DateTime.tuesday,
      recurringUntil: '2026-12-31',
      parentRecurringId: 'series-complete',
    );
  }

  group('EventModel stable identity', () {
    test('creation accepts an ID without generating one', () {
      final generator = FakeEntityIdGenerator(['unused']);

      final event = buildEvent(id: 'event-1');

      expect(event.id, 'event-1');
      expect(generator.callCount, 0);
    });

    test('copyWith preserves ID across title and schedule changes', () {
      final event = buildEvent(
        id: 'event-1',
        parentRecurringId: 'series-1',
      );

      final renamed = event.copyWith(title: 'Nouveau titre');
      final rescheduled = renamed.copyWith(
        date: '2026-07-22',
        time: '14:00',
        startDateTimeIso: '2026-07-22T14:00:00',
        endTime: '14:45',
        endDateTimeIso: '2026-07-22T14:45:00',
      );

      expect(renamed.id, 'event-1');
      expect(rescheduled.id, 'event-1');
      expect(rescheduled.parentRecurringId, 'series-1');
    });

    test('copyWith can assign an ID without generating or losing fields', () {
      final generator = FakeEntityIdGenerator(['unused']);
      final event = buildCompleteEvent();
      final expectedBusinessFields = Map<String, dynamic>.from(event.toJson());

      final identified = event.copyWith(id: 'event-assigned');
      final actualBusinessFields = Map<String, dynamic>.from(
        identified.toJson(),
      )..remove('id');

      expect(identified.id, 'event-assigned');
      expect(actualBusinessFields, expectedBusinessFields);
      expect(generator.callCount, 0);
    });

    test('JSON round trip preserves an existing ID', () {
      final event = buildEvent(id: 'event-1');

      expect(event.toJson()['id'], 'event-1');
      expect(EventModel.fromJson(event.toJson()).id, 'event-1');
    });

    test('legacy JSON without ID remains readable and does not invent one', () {
      final generator = FakeEntityIdGenerator(['unused']);
      final legacyJson = buildEvent().toJson();

      final restored = EventModel.fromJson(legacyJson);

      expect(legacyJson, isNot(containsPair('id', anything)));
      expect(restored.id, isNull);
      expect(generator.callCount, 0);
    });
  });

  group('EventService identity comparison', () {
    test('different valid IDs override identical historical properties', () {
      final first = buildEvent(id: 'event-1');
      final second = buildEvent(id: 'event-2');

      expect(EventService.areSameEvent(first, second), isFalse);
    });

    test('legacy events retain the exact historical comparison', () {
      final first = buildEvent();
      final sameLegacyEvent = buildEvent();
      final differentLegacyEvent = buildEvent(title: 'Autre titre');

      expect(EventService.areSameEvent(first, sameLegacyEvent), isTrue);
      expect(EventService.areSameEvent(first, differentLegacyEvent), isFalse);
    });

    test('ID-first deletion removes only the selected entity', () {
      final selected = buildEvent(id: 'event-1');
      final distinctDuplicate = buildEvent(id: 'event-2');
      final events = [selected, distinctDuplicate]..removeWhere(
          (event) => EventService.areSameEvent(event, selected),
        );

      expect(events, [same(distinctDuplicate)]);
    });

    test('ID-first conflict exclusion ignores only the edited entity', () {
      final edited = buildEvent(id: 'event-1');
      final distinctConflict = buildEvent(id: 'event-2');
      final candidates = [edited, distinctConflict].where(
        (event) => !EventService.areSameEvent(event, edited),
      );

      expect(candidates, [same(distinctConflict)]);
      expect(
        EventService.eventsProtectedOverlap(candidates.single, edited),
        isTrue,
      );
    });
  });

  group('EventService creation identity', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('generates one ID once when a new event is added', () async {
      final generator = FakeEntityIdGenerator(['event-generated']);
      final event = buildCompleteEvent();
      final expectedBusinessFields = Map<String, dynamic>.from(event.toJson());

      await EventService.addEvent(
        event,
        idGenerator: generator,
      );

      final stored = await _storedEvents();
      final storedBusinessFields = Map<String, dynamic>.from(
        stored.single.toJson(),
      )..remove('id');
      expect(generator.callCount, 1);
      expect(stored.single.id, 'event-generated');
      expect(storedBusinessFields, expectedBusinessFields);
    });

    test('does not regenerate an existing event ID', () async {
      final generator = FakeEntityIdGenerator(['unused']);

      await EventService.addEvent(
        buildEvent(id: 'event-existing'),
        idGenerator: generator,
      );

      final stored = await _storedEvents();
      expect(generator.callCount, 0);
      expect(stored.single.id, 'event-existing');
    });

    test('replaces an empty ID with one generated ID', () async {
      final generator = FakeEntityIdGenerator(['event-from-empty']);

      await EventService.addEvent(
        buildEvent(id: ''),
        idGenerator: generator,
      );

      final stored = await _storedEvents();
      expect(generator.callCount, 1);
      expect(stored.single.id, 'event-from-empty');
    });

    test('replaces a whitespace ID with one generated ID', () async {
      final generator = FakeEntityIdGenerator(['event-from-whitespace']);

      await EventService.addEvent(
        buildEvent(id: '   '),
        idGenerator: generator,
      );

      final stored = await _storedEvents();
      expect(generator.callCount, 1);
      expect(stored.single.id, 'event-from-whitespace');
    });

    test('recurring occurrences receive distinct IDs and keep their series',
        () async {
      final generator = FakeEntityIdGenerator([
        'occurrence-1',
        'occurrence-2',
        'occurrence-3',
      ]);
      final base = buildEvent(parentRecurringId: 'series-1');
      final occurrences = [
        base,
        base.copyWith(
          date: '2026-07-28',
          startDateTimeIso: '2026-07-28T10:00:00',
        ),
        base.copyWith(
          date: '2026-08-04',
          startDateTimeIso: '2026-08-04T10:00:00',
        ),
      ];

      await EventService.addEvents(
        occurrences,
        idGenerator: generator,
      );

      final stored = await _storedEvents();
      expect(generator.callCount, 3);
      expect(stored.map((event) => event.id).toSet(), {
        'occurrence-1',
        'occurrence-2',
        'occurrence-3',
      });
      expect(
        stored.map((event) => event.parentRecurringId).toSet(),
        {'series-1'},
      );
    });

    test('persisted recurring base never shares its ID with occurrences',
        () async {
      final generator = FakeEntityIdGenerator([
        'generated-occurrence-1',
        'generated-occurrence-2',
        'generated-occurrence-3',
      ]);
      final persistedBase = buildEvent(id: 'persisted-base-id');
      final occurrences = EventService.buildWeeklyOccurrences(
        baseEvent: persistedBase,
        count: 3,
      );

      expect(occurrences, hasLength(3));
      expect(occurrences.every((event) => event.id == null), isTrue);
      expect(
        occurrences.map((event) => event.parentRecurringId).toSet(),
        hasLength(1),
      );

      await EventService.addEvents(
        occurrences,
        idGenerator: generator,
      );

      final stored = await _storedEvents();
      expect(generator.callCount, 3);
      expect(stored.map((event) => event.id).toSet(), {
        'generated-occurrence-1',
        'generated-occurrence-2',
        'generated-occurrence-3',
      });
      expect(
        stored.map((event) => event.parentRecurringId).toSet(),
        hasLength(1),
      );
    });

    test('saving a legacy event keeps its historical null identity', () async {
      await EventService.saveEvents([buildEvent()]);

      final stored = await _storedEvents();
      expect(stored.single.id, isNull);
    });
  });

  group('CloudEventService identity compatibility', () {
    test('Firestore loading injects the document ID', () {
      final event = CloudEventService.eventFromDocument(
        documentId: 'firestore-doc-id',
        data: buildEvent().toJson(),
      );

      expect(event.id, 'firestore-doc-id');
    });

    test('stable ID selects the document and is excluded from cloud data', () {
      final event = buildCompleteEvent().copyWith(id: 'event-1');
      final expectedPayload = Map<String, dynamic>.from(event.toJson())
        ..remove('id');

      expect(
        CloudEventService.documentIdForEvent(event),
        'event-1',
      );
      expect(CloudEventService.firestoreDataForEvent(event), expectedPayload);
      expect(
        CloudEventService.firestoreDataForEvent(event),
        isNot(containsPair('id', anything)),
      );
    });

    test('missing ID keeps the exact historical document ID algorithm', () {
      final event = buildEvent(parentRecurringId: 'series-1');
      final raw = [
        event.createdAt.toIso8601String(),
        event.startDateTimeIso,
        event.title,
        event.parentRecurringId,
      ].join('|');
      final historicalId =
          base64Url.encode(utf8.encode(raw)).replaceAll('=', '');

      expect(CloudEventService.documentIdForEvent(event), historicalId);
    });

    test('empty and whitespace IDs use the historical document ID', () {
      final event = buildEvent(parentRecurringId: 'series-1');
      final expectedId = CloudEventService.documentIdForEvent(event);

      expect(
        CloudEventService.documentIdForEvent(event.copyWith(id: '')),
        expectedId,
      );
      expect(
        CloudEventService.documentIdForEvent(event.copyWith(id: '   ')),
        expectedId,
      );
    });
  });
}

Future<List<EventModel>> _storedEvents() async {
  final prefs = await SharedPreferences.getInstance();
  final stored = prefs.getStringList(EventService.eventsKey) ?? const [];
  return stored
      .map(
        (event) => EventModel.fromJson(
          Map<String, dynamic>.from(jsonDecode(event) as Map),
        ),
      )
      .toList();
}
