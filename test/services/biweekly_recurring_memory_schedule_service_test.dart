import 'package:flutter_test/flutter_test.dart';

import 'package:moms_ai/services/memory_reasoning_service.dart';
import 'package:moms_ai/services/recurring_memory_schedule_service.dart';
import 'package:moms_ai/services/smart_planning_service.dart';

void main() {
  group('RecurringMemoryScheduleService biweekly', () {
    test('extracts one Wednesday out of two', () {
      final result = RecurringMemoryScheduleService.buildBlockedPeriod(
        text: 'Un mercredi sur deux de 18h30 à 20h.',
        referenceDate: DateTime(2026, 7, 20, 14),
      );

      expect(result, isNotNull);
      expect(result!['recurrenceType'], 'biweekly');
      expect(result['days'], ['Mercredi']);
      expect(result['anchorDateIso'], '2026-07-22');
      expect(result['startTime'], '18:30');
      expect(result['endTime'], '20:00');
    });

    test('supports every two weeks with an explicit weekday', () {
      final result = RecurringMemoryScheduleService.buildBlockedPeriod(
        text: 'Toutes les deux semaines le mardi de 9h à 10h.',
        referenceDate: DateTime(2026, 7, 22),
      );

      expect(result, isNotNull);
      expect(result!['recurrenceType'], 'biweekly');
      expect(result['days'], ['Mardi']);
      expect(result['anchorDateIso'], '2026-07-28');
    });

    test('uses the creation weekday when no weekday is written', () {
      final result = RecurringMemoryScheduleService.buildBlockedPeriod(
        text: 'Tous les quinze jours de 9h à 10h.',
        referenceDate: DateTime(2026, 7, 22, 15),
      );

      expect(result, isNotNull);
      expect(result!['recurrenceType'], 'biweekly');
      expect(result['days'], ['Mercredi']);
      expect(result['anchorDateIso'], '2026-07-22');
    });

    test('supports every 15 days', () {
      final result = RecurringMemoryScheduleService.buildBlockedPeriod(
        text: 'Tous les 15 jours le vendredi de 14h à 15h.',
        referenceDate: DateTime(2026, 7, 22),
      );

      expect(result, isNotNull);
      expect(result!['recurrenceType'], 'biweekly');
      expect(result['days'], ['Vendredi']);
      expect(result['anchorDateIso'], '2026-07-24');
    });

    test('requires a reference date', () {
      final result = RecurringMemoryScheduleService.buildBlockedPeriod(
        text: 'Un mercredi sur deux de 18h30 à 20h.',
      );

      expect(result, isNull);
    });

    test('preserves outbound and return travel', () {
      final result = RecurringMemoryScheduleService.buildBlockedPeriod(
        text: 'Un mercredi sur deux de 18h30 à 20h avec 15 minutes '
            'de trajet aller et 20 minutes de trajet retour.',
        referenceDate: DateTime(2026, 7, 20),
      );

      expect(result, isNotNull);
      expect(result!['travelBeforeMinutes'], 15);
      expect(result['travelAfterMinutes'], 20);
      expect(result['travelMinutes'], 35);
    });
  });

  group('MemoryReasoningService biweekly', () {
    test('uses memory createdAt as anchor source', () {
      final reasoning = MemoryReasoningService.buildReasoning(
        [
          {
            'text': 'Un mercredi sur deux de 18h30 à 20h.',
            'category': 'children',
            'createdAt': DateTime(2026, 7, 20, 14),
          },
        ],
      );

      final blockedPeriods =
          reasoning.where((item) => item['type'] == 'blocked_period').toList();

      expect(blockedPeriods, hasLength(1));
      expect(blockedPeriods.first['recurrenceType'], 'biweekly');
      expect(blockedPeriods.first['anchorDateIso'], '2026-07-22');
    });

    test('supports createdAtIso', () {
      final reasoning = MemoryReasoningService.buildReasoning(
        [
          {
            'text': 'Un mercredi sur deux de 18h30 à 20h.',
            'createdAtIso': '2026-07-20T14:00:00.000',
          },
        ],
      );

      final blockedPeriods =
          reasoning.where((item) => item['type'] == 'blocked_period').toList();

      expect(blockedPeriods, hasLength(1));
      expect(blockedPeriods.first['anchorDateIso'], '2026-07-22');
    });

    test('blocks only alternating weeks', () {
      final reasoning = MemoryReasoningService.buildReasoning(
        [
          {
            'text': 'Un mercredi sur deux de 18h30 à 20h.',
            'createdAt': DateTime(2026, 7, 20),
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
          start: DateTime(2026, 7, 29, 19),
          end: DateTime(2026, 7, 29, 19, 30),
          reasoning: reasoning,
        ),
        false,
      );

      expect(
        SmartPlanningService.overlapsBlockedReasoning(
          start: DateTime(2026, 8, 5, 19),
          end: DateTime(2026, 8, 5, 19, 30),
          reasoning: reasoning,
        ),
        true,
      );
    });
  });
}
