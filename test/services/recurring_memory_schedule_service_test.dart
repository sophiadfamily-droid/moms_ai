import 'package:flutter_test/flutter_test.dart';

import 'package:moms_ai/services/memory_reasoning_service.dart';
import 'package:moms_ai/services/recurring_memory_schedule_service.dart';
import 'package:moms_ai/services/smart_planning_service.dart';

void main() {
  group('RecurringMemoryScheduleService', () {
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
  });
}
