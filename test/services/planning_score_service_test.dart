import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/services/planning_score_service.dart';

void main() {
  EventModel buildEvent({
    required String title,
    required String startIso,
    required String endIso,
    int travelGoMinutes = 0,
    int travelBackMinutes = 0,
    int marginMinutes = 0,
  }) {
    final start = DateTime.parse(startIso);
    final end = DateTime.parse(endIso);

    return EventModel(
      title: title,
      date: startIso.substring(0, 10),
      time: startIso.substring(11, 16),
      endTime: endIso.substring(11, 16),
      durationMinutes: end.difference(start).inMinutes,
      travelMinutes: travelGoMinutes + travelBackMinutes,
      travelGoMinutes: travelGoMinutes,
      travelBackMinutes: travelBackMinutes,
      usesSeparateTravelTimes: true,
      marginMinutes: marginMinutes,
      startDateTimeIso: startIso,
      endDateTimeIso: endIso,
      notes: '',
      category: 'Personnel',
      createdAt: DateTime(2026, 7, 16),
    );
  }

  group('PlanningScoreService', () {
    test('ignores events from other calendar days', () {
      final unrelatedEvent = buildEvent(
        title: 'Événement du lendemain',
        startIso: '2026-07-21T10:00:00',
        endIso: '2026-07-21T11:00:00',
      );

      final scoreWithUnrelatedEvent = PlanningScoreService.scoreSlot(
        start: DateTime(2026, 7, 20, 10),
        end: DateTime(2026, 7, 20, 11),
        events: [unrelatedEvent],
        reasoning: const [],
        preferredStartHour: 9,
        preferredEndHour: 18,
      );

      final scoreWithoutEvent = PlanningScoreService.scoreSlot(
        start: DateTime(2026, 7, 20, 10),
        end: DateTime(2026, 7, 20, 11),
        events: const [],
        reasoning: const [],
        preferredStartHour: 9,
        preferredEndHour: 18,
      );

      expect(scoreWithUnrelatedEvent, scoreWithoutEvent);
    });

    test('rewards a compact same-day gap between 30 and 120 minutes', () {
      final existingEvent = buildEvent(
        title: 'École',
        startIso: '2026-07-20T09:00:00',
        endIso: '2026-07-20T10:00:00',
      );

      final compactScore = PlanningScoreService.scoreSlot(
        start: DateTime(2026, 7, 20, 10, 30),
        end: DateTime(2026, 7, 20, 11, 30),
        events: [existingEvent],
        reasoning: const [],
        preferredStartHour: 9,
        preferredEndHour: 18,
      );

      final distantScore = PlanningScoreService.scoreSlot(
        start: DateTime(2026, 7, 20, 15),
        end: DateTime(2026, 7, 20, 16),
        events: [existingEvent],
        reasoning: const [],
        preferredStartHour: 9,
        preferredEndHour: 18,
      );

      expect(compactScore, greaterThan(distantScore));
    });

    test('uses protected travel range when measuring proximity', () {
      final existingEvent = buildEvent(
        title: 'Médecin',
        startIso: '2026-07-20T10:00:00',
        endIso: '2026-07-20T11:00:00',
        travelBackMinutes: 30,
      );

      final score = PlanningScoreService.scoreSlot(
        start: DateTime(2026, 7, 20, 11, 40),
        end: DateTime(2026, 7, 20, 12, 10),
        events: [existingEvent],
        reasoning: const [],
        preferredStartHour: 9,
        preferredEndHour: 18,
      );

      final scoreWithoutReturnTravel = PlanningScoreService.scoreSlot(
        start: DateTime(2026, 7, 20, 11, 40),
        end: DateTime(2026, 7, 20, 12, 10),
        events: [
          buildEvent(
            title: 'Médecin sans trajet',
            startIso: '2026-07-20T10:00:00',
            endIso: '2026-07-20T11:00:00',
          ),
        ],
        reasoning: const [],
        preferredStartHour: 9,
        preferredEndHour: 18,
      );

      expect(score, lessThan(scoreWithoutReturnTravel));
    });

    test('strongly penalizes an overlapping protected range', () {
      final existingEvent = buildEvent(
        title: 'Dentiste',
        startIso: '2026-07-20T14:00:00',
        endIso: '2026-07-20T15:00:00',
        travelGoMinutes: 15,
        travelBackMinutes: 15,
      );

      final score = PlanningScoreService.scoreSlot(
        start: DateTime(2026, 7, 20, 13, 50),
        end: DateTime(2026, 7, 20, 14, 20),
        events: [existingEvent],
        reasoning: const [],
        preferredStartHour: 9,
        preferredEndHour: 18,
      );

      expect(score, lessThanOrEqualTo(50));
    });

    test('returns zero for an invalid candidate range', () {
      final score = PlanningScoreService.scoreSlot(
        start: DateTime(2026, 7, 20, 14),
        end: DateTime(2026, 7, 20, 14),
        events: const [],
        reasoning: const [],
      );

      expect(score, 0);
    });
  });
}
