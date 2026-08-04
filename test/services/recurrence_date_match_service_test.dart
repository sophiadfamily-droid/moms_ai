import 'package:flutter_test/flutter_test.dart';

import 'package:moms_ai/services/recurrence_date_match_service.dart';
import 'package:moms_ai/services/routine/routine_date_applicability_engine.dart';
import 'package:moms_ai/services/smart_planning_service.dart';

void main() {
  group('RecurrenceDateMatchService weekly recurrence', () {
    test('matches only configured weekly days', () {
      const item = {
        'recurrenceType': 'weekly',
        'days': ['Lundi', 'Jeudi'],
      };

      expect(
        RecurrenceDateMatchService.appliesToDate(
          item,
          DateTime(2026, 7, 20),
        ),
        true,
      );

      expect(
        RecurrenceDateMatchService.appliesToDate(
          item,
          DateTime(2026, 7, 21),
        ),
        false,
      );

      expect(
        RecurrenceDateMatchService.appliesToDate(
          item,
          DateTime(2026, 7, 23),
        ),
        true,
      );
    });

    test('keeps legacy blocked periods without days compatible', () {
      const item = {
        'type': 'blocked_period',
        'recurrenceType': 'weekly',
      };

      expect(
        RecurrenceDateMatchService.appliesToDate(
          item,
          DateTime(2026, 7, 20),
        ),
        true,
      );
    });
  });

  group('RecurrenceDateMatchService weekdays recurrence', () {
    test('matches Monday through Friday only', () {
      const item = {
        'recurrenceType': 'weekdays',
      };

      expect(
        RecurrenceDateMatchService.appliesToDate(
          item,
          DateTime(2026, 7, 20),
        ),
        true,
      );

      expect(
        RecurrenceDateMatchService.appliesToDate(
          item,
          DateTime(2026, 7, 24),
        ),
        true,
      );

      expect(
        RecurrenceDateMatchService.appliesToDate(
          item,
          DateTime(2026, 7, 25),
        ),
        false,
      );

      expect(
        RecurrenceDateMatchService.appliesToDate(
          item,
          DateTime(2026, 7, 26),
        ),
        false,
      );
    });
  });

  group('RecurrenceDateMatchService monthly recurrence', () {
    test('matches the second Tuesday of the month', () {
      const item = {
        'recurrenceType': 'monthly_nth_weekday',
        'days': ['Mardi'],
        'weekOfMonth': 2,
      };

      expect(
        RecurrenceDateMatchService.appliesToDate(
          item,
          DateTime(2026, 7, 14),
        ),
        true,
      );

      expect(
        RecurrenceDateMatchService.appliesToDate(
          item,
          DateTime(2026, 7, 7),
        ),
        false,
      );

      expect(
        RecurrenceDateMatchService.appliesToDate(
          item,
          DateTime(2026, 7, 15),
        ),
        false,
      );
    });

    test('matches the last Friday of the month', () {
      const item = {
        'recurrenceType': 'monthly_nth_weekday',
        'days': ['Vendredi'],
        'weekOfMonth': -1,
      };

      expect(
        RecurrenceDateMatchService.appliesToDate(
          item,
          DateTime(2026, 7, 31),
        ),
        true,
      );

      expect(
        RecurrenceDateMatchService.appliesToDate(
          item,
          DateTime(2026, 7, 24),
        ),
        false,
      );
    });

    test('rejects an invalid monthly occurrence', () {
      const item = {
        'recurrenceType': 'monthly_nth_weekday',
        'days': ['Lundi'],
        'weekOfMonth': 0,
      };

      expect(
        RecurrenceDateMatchService.appliesToDate(
          item,
          DateTime(2026, 7, 20),
        ),
        false,
      );
    });
  });

  group('RecurrenceDateMatchService biweekly recurrence', () {
    const item = {
      'recurrenceType': 'biweekly',
      'days': ['Mercredi'],
      'anchorDateIso': '2026-07-01',
    };

    test('matches the anchor week', () {
      expect(
        RecurrenceDateMatchService.appliesToDate(
          item,
          DateTime(2026, 7, 1),
        ),
        true,
      );
    });

    test('skips the following week', () {
      expect(
        RecurrenceDateMatchService.appliesToDate(
          item,
          DateTime(2026, 7, 8),
        ),
        false,
      );
    });

    test('matches the next alternating week', () {
      expect(
        RecurrenceDateMatchService.appliesToDate(
          item,
          DateTime(2026, 7, 15),
        ),
        true,
      );
    });

    test('does not match another weekday', () {
      expect(
        RecurrenceDateMatchService.appliesToDate(
          item,
          DateTime(2026, 7, 16),
        ),
        false,
      );
    });

    test('does not match dates before the anchor', () {
      expect(
        RecurrenceDateMatchService.appliesToDate(
          item,
          DateTime(2026, 6, 24),
        ),
        false,
      );
    });

    test('rejects a missing anchor date', () {
      const invalidItem = {
        'recurrenceType': 'biweekly',
        'days': ['Mercredi'],
      };

      expect(
        RecurrenceDateMatchService.appliesToDate(
          invalidItem,
          DateTime(2026, 7, 15),
        ),
        false,
      );
    });
  });

  group('Advanced recurrence planning integration', () {
    test('blocks a selected weekday recurrence in planning', () {
      const reasoning = [
        {
          'type': 'blocked_period',
          'recurrenceType': 'weekdays',
          'startTime': '09:00',
          'endTime': '10:00',
          'travelBeforeMinutes': 0,
          'travelAfterMinutes': 0,
        },
      ];

      expect(
        SmartPlanningService.overlapsBlockedReasoning(
          start: DateTime(2026, 7, 20, 9, 30),
          end: DateTime(2026, 7, 20, 9, 45),
          reasoning: reasoning,
        ),
        true,
      );

      expect(
        SmartPlanningService.overlapsBlockedReasoning(
          start: DateTime(2026, 7, 25, 9, 30),
          end: DateTime(2026, 7, 25, 9, 45),
          reasoning: reasoning,
        ),
        false,
      );
    });

    test('blocks only the active biweekly occurrence', () {
      const reasoning = [
        {
          'type': 'blocked_period',
          'recurrenceType': 'biweekly',
          'days': ['Mercredi'],
          'anchorDateIso': '2026-07-01',
          'startTime': '18:00',
          'endTime': '19:00',
          'travelBeforeMinutes': 15,
          'travelAfterMinutes': 20,
        },
      ];

      expect(
        SmartPlanningService.overlapsBlockedReasoning(
          start: DateTime(2026, 7, 15, 17, 50),
          end: DateTime(2026, 7, 15, 18, 10),
          reasoning: reasoning,
        ),
        true,
      );

      expect(
        SmartPlanningService.overlapsBlockedReasoning(
          start: DateTime(2026, 7, 8, 18, 10),
          end: DateTime(2026, 7, 8, 18, 30),
          reasoning: reasoning,
        ),
        false,
      );
    });
  });

  test('legacy planning and canonical routine rules stay equivalent', () {
    const engine = RoutineDateApplicabilityEngine();
    const scenarios = <Map<String, dynamic>>[
      {
        'recurrenceType': 'weekly',
        'days': ['Mardi', 'Vendredi'],
        'weekdays': [DateTime.tuesday, DateTime.friday],
      },
      {
        'recurrenceType': 'weekdays',
        'days': <String>[],
        'weekdays': <int>[],
      },
      {
        'recurrenceType': 'biweekly',
        'days': ['Mercredi'],
        'weekdays': [DateTime.wednesday],
        'anchorDateIso': '2026-07-01',
      },
      {
        'recurrenceType': 'monthly_nth_weekday',
        'days': ['Vendredi'],
        'weekdays': [DateTime.friday],
        'weekOfMonth': -1,
      },
    ];

    for (final scenario in scenarios) {
      for (var day = 1; day <= 31; day++) {
        final date = DateTime(2026, 7, day);
        expect(
          RecurrenceDateMatchService.appliesToDate(scenario, date),
          engine.applies(
            recurrenceType: scenario['recurrenceType']! as String,
            weekdays: scenario['weekdays']! as List<int>,
            date: date,
            anchorDateIso: scenario['anchorDateIso'] as String?,
            weekOfMonth: scenario['weekOfMonth'] as int?,
          ),
          reason: '${scenario['recurrenceType']} on $date',
        );
      }
    }
  });
}
