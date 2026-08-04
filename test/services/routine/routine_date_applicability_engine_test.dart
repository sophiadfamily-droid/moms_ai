import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/services/routine/routine_date_applicability_engine.dart';

void main() {
  const engine = RoutineDateApplicabilityEngine();

  test('applies weekly and weekday rules', () {
    expect(
      engine.applies(
        recurrenceType: 'weekly',
        weekdays: const [DateTime.tuesday],
        date: DateTime(2026, 8, 4),
      ),
      true,
    );
    expect(
      engine.applies(
        recurrenceType: 'weekly',
        weekdays: const [DateTime.tuesday],
        date: DateTime(2026, 8, 5),
      ),
      false,
    );
    expect(
      engine.applies(
        recurrenceType: 'weekdays',
        weekdays: const [],
        date: DateTime(2026, 8, 8),
      ),
      false,
    );
  });

  test('applies alternating weeks from a civil anchor date', () {
    bool applies(DateTime date) => engine.applies(
          recurrenceType: 'biweekly',
          weekdays: const [DateTime.tuesday],
          date: date,
          anchorDateIso: '2026-08-04',
        );

    expect(applies(DateTime(2026, 8, 4)), true);
    expect(applies(DateTime(2026, 8, 11)), false);
    expect(applies(DateTime(2026, 8, 18)), true);
    expect(applies(DateTime(2026, 7, 28)), false);
  });

  test('fails closed when a biweekly anchor is missing or invalid', () {
    for (final anchor in <String?>[null, '', 'not-a-date']) {
      expect(
        engine.applies(
          recurrenceType: 'biweekly',
          weekdays: const [DateTime.tuesday],
          date: DateTime(2026, 8, 4),
          anchorDateIso: anchor,
        ),
        false,
      );
    }
  });

  test('applies nth and last weekday monthly rules', () {
    expect(
      engine.applies(
        recurrenceType: 'monthly_nth_weekday',
        weekdays: const [DateTime.tuesday],
        date: DateTime(2026, 8, 11),
        weekOfMonth: 2,
      ),
      true,
    );
    expect(
      engine.applies(
        recurrenceType: 'monthlyNthWeekday',
        weekdays: const [DateTime.friday],
        date: DateTime(2026, 8, 28),
        weekOfMonth: -1,
      ),
      true,
    );
    expect(
      engine.applies(
        recurrenceType: 'monthly_nth_weekday',
        weekdays: const [DateTime.tuesday],
        date: DateTime(2026, 8, 11),
        weekOfMonth: 0,
      ),
      false,
    );
  });

  test('keeps empty-day matching behind an explicit legacy switch', () {
    expect(
      engine.applies(
        recurrenceType: 'weekly',
        weekdays: const [],
        date: DateTime(2026, 8, 4),
      ),
      false,
    );
    expect(
      engine.applies(
        recurrenceType: 'weekly',
        weekdays: const [],
        date: DateTime(2026, 8, 4),
        emptyWeekdaysMatchAll: true,
      ),
      true,
    );
  });
}
