import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/services/planning_proposal_engine.dart';

void main() {
  group('PlanningProposalEngine', () {
    test('returns diversified planning options across multiple days', () {
      final startDate = DateTime(2026, 7, 1);

      final result = PlanningProposalEngine.findBestOptionsFromEvents(
        startDate: startDate,
        totalMinutes: 60,
        events: <EventModel>[],
        reasoning: const [],
        searchDays: 7,
        maxOptions: 3,
      );

      expect(result.hasOptions, true);
      expect(result.options.length, 3);

      final uniqueDays = result.options.map((option) => option.dateIso).toSet();
      expect(uniqueDays.length, greaterThan(1));
    });

    test(
      'reserves exactly 90 minutes for 45 min appointment plus separate travel',
      () {
        const appointmentMinutes = 45;
        const travelGoMinutes = 15;
        const travelBackMinutes = 30;
        const totalMinutes =
            appointmentMinutes + travelGoMinutes + travelBackMinutes;

        final requestedDate = DateTime(2026, 7, 14);

        final result = PlanningProposalEngine.findBestOptionsFromEvents(
          startDate: requestedDate,
          totalMinutes: totalMinutes,
          events: <EventModel>[],
          reasoning: const [],
          searchDays: 1,
          maxOptions: 3,
        );

        expect(totalMinutes, 90);
        expect(result.hasOptions, true);
        expect(result.options.length, 3);

        final uniqueSlots = result.options
            .map((option) => '${option.dateIso}-${option.startTime}')
            .toSet();

        expect(uniqueSlots.length, result.options.length);

        for (final option in result.options) {
          expect(option.dateIso, '2026-07-14');
          expect(option.end.difference(option.start).inMinutes, totalMinutes);
        }
      },
    );

    test('returns no options for invalid duration', () {
      final result = PlanningProposalEngine.findBestOptionsFromEvents(
        startDate: DateTime(2026, 7, 1),
        totalMinutes: 0,
        events: <EventModel>[],
        reasoning: const [],
      );

      expect(result.hasOptions, false);
      expect(result.options, isEmpty);
    });

    test('allows evening slots when no real family constraint exists', () {
      final result = PlanningProposalEngine.findBestOptionsFromEvents(
        startDate: DateTime(2026, 7, 20),
        totalMinutes: 30,
        events: <EventModel>[],
        reasoning: const [
          {
            'type': 'blocked_period',
            'sourceType': 'test',
            'label': 'Journée occupée',
            'days': ['Lundi'],
            'startTime': '08:00',
            'endTime': '18:30',
            'travelBeforeMinutes': 0,
            'travelAfterMinutes': 0,
          },
        ],
        searchDays: 1,
        maxOptions: 3,
      );

      expect(result.hasOptions, true);
      expect(result.options, isNotEmpty);

      for (final option in result.options) {
        expect(
          option.start.isBefore(DateTime(2026, 7, 20, 18, 30)),
          false,
        );
      }
    });

    test('blocks evening slots from a real structured family period', () {
      final result = PlanningProposalEngine.findBestOptionsFromEvents(
        startDate: DateTime(2026, 7, 20),
        totalMinutes: 30,
        events: <EventModel>[],
        reasoning: const [
          {
            'type': 'blocked_period',
            'sourceType': 'test',
            'label': 'Journée occupée',
            'days': ['Lundi'],
            'startTime': '08:00',
            'endTime': '18:30',
            'travelBeforeMinutes': 0,
            'travelAfterMinutes': 0,
          },
          {
            'type': 'blocked_period',
            'sourceType': 'family_routine',
            'label': 'Routine familiale du soir',
            'days': ['Lundi'],
            'startTime': '18:30',
            'endTime': '21:00',
            'travelBeforeMinutes': 0,
            'travelAfterMinutes': 0,
          },
        ],
        searchDays: 1,
        maxOptions: 3,
      );

      expect(result.hasOptions, false);
      expect(result.options, isEmpty);
    });
  });
}
