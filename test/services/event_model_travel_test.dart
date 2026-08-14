import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/services/event_service.dart';
import 'package:moms_ai/services/smart_planning_service.dart';

void main() {
  group('EventModel travel persistence', () {
    test('preserves an explicit zero return travel', () {
      final event = EventModel(
        title: 'Médecin',
        date: '2026-07-14',
        time: '10:15',
        notes: '',
        createdAt: DateTime(2026, 7, 13),
        startDateTimeIso: '2026-07-14T10:15:00',
        endTime: '11:00',
        endDateTimeIso: '2026-07-14T11:00:00',
        durationMinutes: 45,
        travelMinutes: 15,
        travelGoMinutes: 15,
        travelBackMinutes: 0,
        usesSeparateTravelTimes: true,
      );

      final restored = EventModel.fromJson(event.toJson());

      expect(restored.usesSeparateTravelTimes, true);
      expect(restored.resolvedTravelGoMinutes, 15);
      expect(restored.resolvedTravelBackMinutes, 0);
      expect(restored.totalTravelMinutes, 15);
    });

    test('preserves an optional physical place without changing old events',
        () {
      final event = EventModel(
        title: 'Dentiste',
        date: '2026-07-14',
        time: '10:15',
        notes: '',
        location: 'Clinique Saint-Jean',
        locationEntityId: 'place-clinique-saint-jean',
        createdAt: DateTime(2026, 7, 13),
        startDateTimeIso: '2026-07-14T10:15:00',
      );

      final restored = EventModel.fromJson(event.toJson());
      final legacy = EventModel.fromJson({
        'title': 'Ancien rendez-vous',
        'date': '2026-07-14',
        'time': '09:00',
        'notes': '',
        'createdAt': '2026-07-13T10:00:00',
        'startDateTimeIso': '2026-07-14T09:00:00',
      });

      expect(restored.location, 'Clinique Saint-Jean');
      expect(restored.locationEntityId, 'place-clinique-saint-jean');
      expect(legacy.location, isEmpty);
      expect(legacy.locationEntityId, isNull);
    });

    test(
      'keeps legacy travel when zero-valued separate keys are present',
      () {
        final restored = EventModel.fromJson({
          'title': 'Ancien rendez-vous',
          'date': '2026-07-14',
          'time': '10:00',
          'notes': '',
          'createdAt': '2026-07-13T10:00:00',
          'startDateTimeIso': '2026-07-14T10:00:00',
          'durationMinutes': 45,
          'travelMinutes': 20,
          'travelGoMinutes': 0,
          'travelBackMinutes': 0,
        });

        expect(restored.usesSeparateTravelTimes, false);
        expect(restored.resolvedTravelGoMinutes, 20);
        expect(restored.resolvedTravelBackMinutes, 20);
      },
    );

    test('keeps legacy travel compatible', () {
      final restored = EventModel.fromJson({
        'title': 'Ancien rendez-vous',
        'date': '2026-07-14',
        'time': '10:00',
        'notes': '',
        'createdAt': '2026-07-13T10:00:00',
        'startDateTimeIso': '2026-07-14T10:00:00',
        'durationMinutes': 45,
        'travelMinutes': 20,
      });

      expect(restored.usesSeparateTravelTimes, false);
      expect(restored.resolvedTravelGoMinutes, 20);
      expect(restored.resolvedTravelBackMinutes, 20);
    });

    test('protected range includes travel and margin exactly once', () {
      final event = EventModel(
        title: 'Médecin',
        date: '2026-07-14',
        time: '10:15',
        notes: '',
        createdAt: DateTime(2026, 7, 13),
        startDateTimeIso: '2026-07-14T10:15:00',
        endTime: '11:00',
        endDateTimeIso: '2026-07-14T11:00:00',
        durationMinutes: 45,
        travelMinutes: 45,
        travelGoMinutes: 15,
        travelBackMinutes: 30,
        usesSeparateTravelTimes: true,
        marginMinutes: 10,
      );

      expect(
        EventService.parseProtectedStart(event),
        DateTime(2026, 7, 14, 10),
      );

      expect(
        EventService.parseProtectedEnd(event),
        DateTime(2026, 7, 14, 11, 40),
      );
    });
  });

  test('smart proposal stores appointment time instead of protected block', () {
    const proposal = SmartPlanningProposal(
      canPropose: true,
      taskTitle: 'Médecin',
      taskType: 'appointment',
      needsTravel: true,
      date: '2026-07-14',
      startTime: '10:00',
      endTime: '11:40',
      actionMinutes: 45,
      travelGoMinutes: 15,
      travelBackMinutes: 30,
      marginMinutes: 10,
      totalMinutes: 100,
      explanation: '',
      confirmationMessage: '',
    );

    final event = SmartPlanningService.eventFromProposal(proposal);

    expect(event.time, '10:15');
    expect(event.endTime, '11:00');
    expect(event.durationMinutes, 45);
    expect(event.travelGoMinutes, 15);
    expect(event.travelBackMinutes, 30);
    expect(event.marginMinutes, 10);
    expect(event.usesSeparateTravelTimes, true);

    expect(
      EventService.parseProtectedStart(event),
      DateTime(2026, 7, 14, 10),
    );

    expect(
      EventService.parseProtectedEnd(event),
      DateTime(2026, 7, 14, 11, 40),
    );
  });

  group('EventService protected overlap', () {
    EventModel buildEvent({
      required String title,
      required String startIso,
      required String endIso,
      required int durationMinutes,
      int travelGoMinutes = 0,
      int travelBackMinutes = 0,
      int marginMinutes = 0,
    }) {
      final start = DateTime.parse(startIso);

      return EventModel(
        title: title,
        date: EventService.formatIsoDate(start),
        time: EventService.formatIsoTime(start),
        notes: '',
        createdAt: DateTime(2026, 7, 13),
        startDateTimeIso: startIso,
        endTime: endIso.substring(11, 16),
        endDateTimeIso: endIso,
        durationMinutes: durationMinutes,
        travelMinutes: travelGoMinutes + travelBackMinutes,
        travelGoMinutes: travelGoMinutes,
        travelBackMinutes: travelBackMinutes,
        usesSeparateTravelTimes: true,
        marginMinutes: marginMinutes,
      );
    }

    test('detects conflict caused only by return travel', () {
      final first = buildEvent(
        title: 'Médecin',
        startIso: '2026-07-14T14:00:00',
        endIso: '2026-07-14T15:00:00',
        durationMinutes: 60,
        travelBackMinutes: 30,
      );

      final second = buildEvent(
        title: 'École',
        startIso: '2026-07-14T15:10:00',
        endIso: '2026-07-14T15:40:00',
        durationMinutes: 30,
      );

      expect(EventService.eventsOverlap(first, second), false);
      expect(EventService.eventsProtectedOverlap(first, second), true);
    });

    test('detects conflict caused only by outbound travel', () {
      final first = buildEvent(
        title: 'École',
        startIso: '2026-07-14T13:30:00',
        endIso: '2026-07-14T13:50:00',
        durationMinutes: 20,
      );

      final second = buildEvent(
        title: 'Médecin',
        startIso: '2026-07-14T14:00:00',
        endIso: '2026-07-14T15:00:00',
        durationMinutes: 60,
        travelGoMinutes: 20,
      );

      expect(EventService.eventsOverlap(first, second), false);
      expect(EventService.eventsProtectedOverlap(first, second), true);
    });

    test('detects conflict caused only by safety margin', () {
      final first = buildEvent(
        title: 'Médecin',
        startIso: '2026-07-14T14:00:00',
        endIso: '2026-07-14T15:00:00',
        durationMinutes: 60,
        marginMinutes: 15,
      );

      final second = buildEvent(
        title: 'Appel',
        startIso: '2026-07-14T15:10:00',
        endIso: '2026-07-14T15:30:00',
        durationMinutes: 20,
      );

      expect(EventService.eventsOverlap(first, second), false);
      expect(EventService.eventsProtectedOverlap(first, second), true);
    });

    test('allows events touching exactly at protected boundaries', () {
      final first = buildEvent(
        title: 'Médecin',
        startIso: '2026-07-14T14:00:00',
        endIso: '2026-07-14T15:00:00',
        durationMinutes: 60,
        travelBackMinutes: 30,
      );

      final second = buildEvent(
        title: 'Appel',
        startIso: '2026-07-14T15:30:00',
        endIso: '2026-07-14T16:00:00',
        durationMinutes: 30,
      );

      expect(EventService.eventsProtectedOverlap(first, second), false);
    });

    test('uses legacy travel on both sides for old events', () {
      final legacy = EventModel(
        title: 'Ancien rendez-vous',
        date: '2026-07-14',
        time: '14:00',
        notes: '',
        createdAt: DateTime(2026, 7, 13),
        startDateTimeIso: '2026-07-14T14:00:00',
        endTime: '15:00',
        endDateTimeIso: '2026-07-14T15:00:00',
        durationMinutes: 60,
        travelMinutes: 20,
      );

      final candidate = buildEvent(
        title: 'Nouvel événement',
        startIso: '2026-07-14T15:10:00',
        endIso: '2026-07-14T15:40:00',
        durationMinutes: 30,
      );

      expect(legacy.resolvedTravelBackMinutes, 20);
      expect(EventService.eventsProtectedOverlap(legacy, candidate), true);
    });
  });
}
