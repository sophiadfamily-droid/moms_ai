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
}
