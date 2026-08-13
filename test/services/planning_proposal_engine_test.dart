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

    test(
      'does not propose an appointment at a dependent school pickup time',
      () {
        final result = PlanningProposalEngine.findBestOptionsFromEvents(
          startDate: DateTime(2026, 7, 20),
          totalMinutes: 90,
          events: <EventModel>[],
          reasoning: const [
            {
              'type': 'other_person_schedule',
              'planningEffect': 'potential_care_transition',
              'routineKind': 'schoolSchedule',
              'days': ['Lundi'],
              'startTime': '13:30',
              'endTime': '16:30',
              'transitionBeforeMinutes': 10,
              'transitionAfterMinutes': 10,
            },
          ],
          searchDays: 1,
          maxOptions: 3,
        );

        expect(result.hasOptions, true);
        expect(result.options, isNotEmpty);
        expect(
          result.options.any(
            (option) => option.start == DateTime(2026, 7, 20, 16, 30),
          ),
          false,
        );
        expect(
          result.options.every(
            (option) =>
                !option.start.isBefore(DateTime(2026, 7, 20, 13, 45)) &&
                !option.end.isAfter(DateTime(2026, 7, 20, 16)),
          ),
          true,
        );
      },
    );

    test(
      'ranks school-time comfort above pickup boundaries across a week',
      () {
        final result = PlanningProposalEngine.findBestOptionsFromEvents(
          startDate: DateTime(2026, 7, 20),
          totalMinutes: 90,
          events: <EventModel>[],
          reasoning: const [
            {
              'type': 'other_person_schedule',
              'planningEffect': 'potential_care_transition',
              'routineKind': 'schoolSchedule',
              'days': ['Lundi', 'Mardi', 'Jeudi', 'Vendredi'],
              'startTime': '08:30',
              'endTime': '11:50',
            },
            {
              'type': 'other_person_schedule',
              'planningEffect': 'potential_care_transition',
              'routineKind': 'schoolSchedule',
              'days': ['Lundi', 'Mardi', 'Jeudi', 'Vendredi'],
              'startTime': '13:30',
              'endTime': '16:30',
            },
          ],
          searchDays: 5,
          maxOptions: 3,
        );

        expect(result.hasOptions, true);
        expect(
          result.options.map((option) => option.start.weekday).toList(),
          [DateTime.monday, DateTime.tuesday, DateTime.thursday],
        );
        expect(
          result.options.every(
            (option) {
              final morningStart = DateTime(
                option.start.year,
                option.start.month,
                option.start.day,
                8,
                45,
              );
              final morningEnd = DateTime(
                option.end.year,
                option.end.month,
                option.end.day,
                11,
                20,
              );
              final afternoonStart = DateTime(
                option.start.year,
                option.start.month,
                option.start.day,
                13,
                45,
              );
              final afternoonEnd = DateTime(
                option.end.year,
                option.end.month,
                option.end.day,
                16,
              );
              final insideMorning = !option.start.isBefore(morningStart) &&
                  !option.end.isAfter(morningEnd);
              final insideAfternoon = !option.start.isBefore(afternoonStart) &&
                  !option.end.isAfter(afternoonEnd);
              return insideMorning || insideAfternoon;
            },
          ),
          true,
        );
      },
    );
  });
}
