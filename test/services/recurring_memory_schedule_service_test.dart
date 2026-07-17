import 'package:flutter_test/flutter_test.dart';

import 'package:moms_ai/services/memory_reasoning_service.dart';
import 'package:moms_ai/services/recurring_memory_schedule_service.dart';
import 'package:moms_ai/services/smart_planning_service.dart';

void main() {
  group('RecurringMemoryScheduleService', () {
    test('extracts a weekdays recurrence without explicit days', () {
      final result = RecurringMemoryScheduleService.buildBlockedPeriod(
        text: 'Tous les jours ouvrés de 9h à 10h.',
        category: 'work',
      );

      expect(result, isNotNull);
      expect(result!['recurrenceType'], 'weekdays');
      expect(result.containsKey('days'), false);
      expect(result['startTime'], '09:00');
      expect(result['endTime'], '10:00');
      expect(result['category'], 'work');
    });

    test('keeps explicit day routines as weekly recurrences', () {
      final result = RecurringMemoryScheduleService.buildBlockedPeriod(
        text: 'Tous les mercredis de 18h30 à 20h.',
      );

      expect(result, isNotNull);
      expect(result!['recurrenceType'], 'weekly');
      expect(result['days'], ['Mercredi']);
    });

    test('extracts a weekly routine with a complete time range', () {
      final result = RecurringMemoryScheduleService.buildBlockedPeriod(
        text: 'Tous les mercredis de 18h30 à 20h, j’emmène Kassim au foot.',
        category: 'children',
      );

      expect(result, isNotNull);
      expect(result!['type'], 'blocked_period');
      expect(result['sourceType'], 'memory_routine');
      expect(result['category'], 'children');
      expect(result['days'], ['Mercredi']);
      expect(result['startTime'], '18:30');
      expect(result['endTime'], '20:00');
      expect(result['travelBeforeMinutes'], 0);
      expect(result['travelAfterMinutes'], 0);
    });

    test('extracts several explicit recurring days', () {
      final result = RecurringMemoryScheduleService.buildBlockedPeriod(
        text: 'Tous les lundis et jeudis de 17h à 18h15, cours de sport.',
      );

      expect(result, isNotNull);
      expect(result!['days'], ['Lundi', 'Jeudi']);
      expect(result['startTime'], '17:00');
      expect(result['endTime'], '18:15');
    });

    test('supports an interval written with entre and et', () {
      final result = RecurringMemoryScheduleService.buildBlockedPeriod(
        text: 'Chaque mardi entre 19h00 et 20h30 je suis indisponible.',
      );

      expect(result, isNotNull);
      expect(result!['days'], ['Mardi']);
      expect(result['startTime'], '19:00');
      expect(result['endTime'], '20:30');
    });

    test('does not invent an end time from a single hour', () {
      final result = RecurringMemoryScheduleService.buildBlockedPeriod(
        text: 'Tous les mercredis à 18h30, Kassim a football.',
      );

      expect(result, isNull);
    });

    test('ignores a non-recurring appointment', () {
      final result = RecurringMemoryScheduleService.buildBlockedPeriod(
        text: 'Mercredi de 18h30 à 20h, Kassim a football.',
      );

      expect(result, isNull);
    });

    test('rejects an invalid or reversed time range', () {
      final result = RecurringMemoryScheduleService.buildBlockedPeriod(
        text: 'Tous les mercredis de 20h à 18h30.',
      );

      expect(result, isNull);
    });
    test('extracts separate outbound and return travel', () {
      final result = RecurringMemoryScheduleService.buildBlockedPeriod(
        text:
            'Tous les mercredis de 18h30 à 20h avec 15 minutes de trajet aller et 20 minutes de trajet retour.',
      );

      expect(result, isNotNull);
      expect(result!['travelBeforeMinutes'], 15);
      expect(result['travelAfterMinutes'], 20);
      expect(result['travelMinutes'], 35);
    });

    test('supports travel duration written after each direction', () {
      final result = RecurringMemoryScheduleService.buildBlockedPeriod(
        text:
            'Chaque mardi de 19h à 20h, trajet aller 10 min et trajet retour 25 min.',
      );

      expect(result, isNotNull);
      expect(result!['travelBeforeMinutes'], 10);
      expect(result['travelAfterMinutes'], 25);
      expect(result['travelMinutes'], 35);
    });

    test('applies one shared travel duration to both directions', () {
      final result = RecurringMemoryScheduleService.buildBlockedPeriod(
        text: 'Tous les lundis de 17h à 18h avec 15 minutes de trajet.',
      );

      expect(result, isNotNull);
      expect(result!['travelBeforeMinutes'], 15);
      expect(result['travelAfterMinutes'], 15);
      expect(result['travelMinutes'], 30);
    });

    test('supports travel durations expressed in hours', () {
      final result = RecurringMemoryScheduleService.buildBlockedPeriod(
        text:
            'Tous les samedis de 10h à 12h avec 1 heure de trajet aller et 30 min de trajet retour.',
      );

      expect(result, isNotNull);
      expect(result!['travelBeforeMinutes'], 60);
      expect(result['travelAfterMinutes'], 30);
      expect(result['travelMinutes'], 90);
    });

    test('does not invent travel when none is provided', () {
      final result = RecurringMemoryScheduleService.buildBlockedPeriod(
        text: 'Tous les vendredis de 18h à 19h, cours de sport.',
      );

      expect(result, isNotNull);
      expect(result!['travelBeforeMinutes'], 0);
      expect(result['travelAfterMinutes'], 0);
      expect(result['travelMinutes'], 0);
    });
  });

  group('MemoryReasoningService weekdays blocked periods', () {
    test('creates a weekdays blocked period from memory', () {
      final reasoning = MemoryReasoningService.buildReasoning(
        const [
          {
            'text': 'Tous les jours ouvrés de 9h à 10h.',
            'category': 'work',
          },
        ],
      );

      expect(
        reasoning.where((item) => item['type'] == 'routine'),
        hasLength(1),
      );

      final blockedPeriods =
          reasoning.where((item) => item['type'] == 'blocked_period').toList();

      expect(blockedPeriods, hasLength(1));
      expect(blockedPeriods.first['recurrenceType'], 'weekdays');
      expect(blockedPeriods.first.containsKey('days'), false);
    });

    test('blocks weekdays but leaves weekends available', () {
      final reasoning = MemoryReasoningService.buildReasoning(
        const [
          {
            'text': 'Tous les jours ouvrés de 9h à 10h.',
            'category': 'work',
          },
        ],
      );

      expect(
        SmartPlanningService.overlapsBlockedReasoning(
          start: DateTime(2026, 7, 20, 9, 15),
          end: DateTime(2026, 7, 20, 9, 45),
          reasoning: reasoning,
        ),
        true,
      );

      expect(
        SmartPlanningService.overlapsBlockedReasoning(
          start: DateTime(2026, 7, 25, 9, 15),
          end: DateTime(2026, 7, 25, 9, 45),
          reasoning: reasoning,
        ),
        false,
      );
    });
  });

  group('MemoryReasoningService recurring blocked periods', () {
    test('keeps routine reasoning and adds a blocked period', () {
      final reasoning = MemoryReasoningService.buildReasoning(
        const [
          {
            'text':
                'Tous les mercredis de 18h30 à 20h, j’emmène Kassim au foot.',
            'category': 'children',
          },
        ],
      );

      expect(
        reasoning.where((item) => item['type'] == 'routine'),
        hasLength(1),
      );

      final blockedPeriods =
          reasoning.where((item) => item['type'] == 'blocked_period').toList();

      expect(blockedPeriods, hasLength(1));
      expect(blockedPeriods.first['days'], ['Mercredi']);
      expect(blockedPeriods.first['startTime'], '18:30');
      expect(blockedPeriods.first['endTime'], '20:00');
    });

    test('blocks only the recurring weekday in planning', () {
      final reasoning = MemoryReasoningService.buildReasoning(
        const [
          {
            'text':
                'Tous les mercredis de 18h30 à 20h, j’emmène Kassim au foot.',
            'category': 'children',
          },
        ],
      );

      expect(
        SmartPlanningService.overlapsBlockedReasoning(
          start: DateTime(2026, 7, 22, 19),
          end: DateTime(2026, 7, 22, 19, 30),
          reasoning: reasoning,
        ),
        true,
      );

      expect(
        SmartPlanningService.overlapsBlockedReasoning(
          start: DateTime(2026, 7, 23, 19),
          end: DateTime(2026, 7, 23, 19, 30),
          reasoning: reasoning,
        ),
        false,
      );
    });

    test('does not create a blocked period without a complete range', () {
      final reasoning = MemoryReasoningService.buildReasoning(
        const [
          {
            'text': 'Tous les mercredis à 18h30, Kassim a football.',
            'category': 'children',
          },
        ],
      );

      expect(
        reasoning.where((item) => item['type'] == 'routine'),
        hasLength(1),
      );

      expect(
        reasoning.where((item) => item['type'] == 'blocked_period'),
        isEmpty,
      );
    });
    test('blocks outbound travel before a recurring routine', () {
      final reasoning = MemoryReasoningService.buildReasoning(
        const [
          {
            'text':
                'Tous les mercredis de 18h30 à 20h avec 15 minutes de trajet aller et 20 minutes de trajet retour.',
            'category': 'children',
          },
        ],
      );

      expect(
        SmartPlanningService.overlapsBlockedReasoning(
          start: DateTime(2026, 7, 22, 18, 20),
          end: DateTime(2026, 7, 22, 18, 25),
          reasoning: reasoning,
        ),
        true,
      );
    });

    test('blocks return travel after a recurring routine', () {
      final reasoning = MemoryReasoningService.buildReasoning(
        const [
          {
            'text':
                'Tous les mercredis de 18h30 à 20h avec 15 minutes de trajet aller et 20 minutes de trajet retour.',
            'category': 'children',
          },
        ],
      );

      expect(
        SmartPlanningService.overlapsBlockedReasoning(
          start: DateTime(2026, 7, 22, 20, 10),
          end: DateTime(2026, 7, 22, 20, 15),
          reasoning: reasoning,
        ),
        true,
      );

      expect(
        SmartPlanningService.overlapsBlockedReasoning(
          start: DateTime(2026, 7, 22, 20, 20),
          end: DateTime(2026, 7, 22, 20, 30),
          reasoning: reasoning,
        ),
        false,
      );
    });
  });
}
