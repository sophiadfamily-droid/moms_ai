import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/services/planning_proposal_engine.dart';
import 'package:moms_ai/services/selected_slot_revalidation_service.dart';

void main() {
  EventModel buildEvent({
    String title = 'Médecin',
  }) {
    return EventModel(
      title: title,
      date: '2026-07-20',
      time: '10:15',
      endTime: '11:00',
      durationMinutes: 45,
      travelMinutes: 45,
      travelGoMinutes: 15,
      travelBackMinutes: 30,
      usesSeparateTravelTimes: true,
      marginMinutes: 10,
      startDateTimeIso: '2026-07-20T10:15:00',
      endDateTimeIso: '2026-07-20T11:00:00',
      category: 'Santé',
      notes: '',
      createdAt: DateTime(2026, 7, 16),
    );
  }

  group('SelectedSlotRevalidationService', () {
    test('keeps the selected slot when no new conflict exists', () async {
      var alternativeSearches = 0;

      final result = await SelectedSlotRevalidationService.revalidate(
        candidate: buildEvent(),
        protectedStart: DateTime(2026, 7, 20, 10),
        totalMinutes: 100,
        reasoning: const [],
        conflictChecker: ({required candidate}) async => null,
        alternativeFinder: ({
          required startDate,
          required totalMinutes,
          required reasoning,
          searchDays = 21,
          maxOptions = 3,
        }) async {
          alternativeSearches++;

          return const PlanningProposalEngineResult(
            hasOptions: false,
            options: [],
            explanation: '',
          );
        },
      );

      expect(result.isAvailable, isTrue);
      expect(result.conflictEvent, isNull);
      expect(result.alternatives.options, isEmpty);
      expect(alternativeSearches, 0);
    });

    test('searches fresh alternatives when the slot became unavailable',
        () async {
      var receivedTotalMinutes = 0;
      DateTime? receivedStartDate;

      final alternative = PlanningProposalOption(
        start: DateTime(2026, 7, 20, 13),
        end: DateTime(2026, 7, 20, 14, 40),
        score: 80,
        dateIso: '2026-07-20',
        startTime: '13:00',
        endTime: '14:40',
        label: '20/07/2026 de 13:00 à 14:40',
      );

      final result = await SelectedSlotRevalidationService.revalidate(
        candidate: buildEvent(),
        protectedStart: DateTime(2026, 7, 20, 10),
        totalMinutes: 100,
        reasoning: const [],
        conflictChecker: ({required candidate}) async {
          return buildEvent(title: 'École');
        },
        alternativeFinder: ({
          required startDate,
          required totalMinutes,
          required reasoning,
          searchDays = 21,
          maxOptions = 3,
        }) async {
          receivedStartDate = startDate;
          receivedTotalMinutes = totalMinutes;

          return PlanningProposalEngineResult(
            hasOptions: true,
            options: [alternative],
            explanation: 'Une nouvelle option.',
          );
        },
      );

      expect(result.isAvailable, isFalse);
      expect(result.conflictEvent?.title, 'École');
      expect(result.alternatives.hasOptions, isTrue);
      expect(result.alternatives.options.single.startTime, '13:00');
      expect(receivedStartDate, DateTime(2026, 7, 20, 10));
      expect(receivedTotalMinutes, 100);
    });

    test('revalidates a selected slot against a changed canonical routine',
        () async {
      var alternativeSearches = 0;
      final result = await SelectedSlotRevalidationService.revalidate(
        candidate: buildEvent(),
        protectedStart: DateTime(2026, 7, 20, 10),
        totalMinutes: 100,
        reasoning: const [
          {
            'type': 'blocked_period',
            'recurrenceType': 'weekly',
            'days': ['Lundi'],
            'startTime': '10:30',
            'endTime': '11:30',
            'travelBeforeMinutes': 0,
            'travelAfterMinutes': 0,
          },
        ],
        conflictChecker: ({required candidate}) async => null,
        alternativeFinder: ({
          required startDate,
          required totalMinutes,
          required reasoning,
          searchDays = 21,
          maxOptions = 3,
        }) async {
          alternativeSearches++;
          return const PlanningProposalEngineResult(
            hasOptions: false,
            options: [],
            explanation: 'Aucune alternative.',
          );
        },
      );

      expect(result.isAvailable, isFalse);
      expect(result.conflictEvent, isNull);
      expect(alternativeSearches, 1);
    });

    test('never accepts a conflicting slot when no alternative exists',
        () async {
      final result = await SelectedSlotRevalidationService.revalidate(
        candidate: buildEvent(),
        protectedStart: DateTime(2026, 7, 20, 10),
        totalMinutes: 100,
        reasoning: const [],
        conflictChecker: ({required candidate}) async {
          return buildEvent(title: 'École');
        },
        alternativeFinder: ({
          required startDate,
          required totalMinutes,
          required reasoning,
          searchDays = 21,
          maxOptions = 3,
        }) async {
          return const PlanningProposalEngineResult(
            hasOptions: false,
            options: [],
            explanation: 'Aucune alternative.',
          );
        },
      );

      expect(result.isAvailable, isFalse);
      expect(result.conflictEvent?.title, 'École');
      expect(result.alternatives.hasOptions, isFalse);
      expect(result.alternatives.options, isEmpty);
    });
  });
}
