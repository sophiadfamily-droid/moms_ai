import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/routine/routine_occurrence_models.dart';
import 'package:moms_ai/services/routine/routine_zoned_occurrence_engine.dart';
import 'package:timezone/data/latest.dart' as tz_data;

void main() {
  setUpAll(tz_data.initializeTimeZones);

  const engine = RoutineZonedOccurrenceEngine();

  test('resolves an explicit local timezone and complete protected range', () {
    final result = engine.resolve(
      projection: _projection(
        dateIso: '2026-08-04',
        startTime: '14:00',
        durationMinutes: 60,
        travelGoMinutes: 10,
        travelBackMinutes: 5,
        marginMinutes: 5,
      ),
      timezoneId: 'Europe/Paris',
    );

    final occurrence = result.occurrences.single;
    expect(occurrence.start, DateTime.utc(2026, 8, 4, 12));
    expect(occurrence.end, DateTime.utc(2026, 8, 4, 13));
    expect(occurrence.protectedStart, DateTime.utc(2026, 8, 4, 11, 50));
    expect(occurrence.protectedEnd, DateTime.utc(2026, 8, 4, 13, 10));
    expect(occurrence.timezoneId, 'Europe/Paris');
  });

  test('rejects an unknown timezone instead of assuming one', () {
    expect(
      () => engine.resolve(
        projection: _projection(),
        timezoneId: 'Unknown/Somewhere',
      ),
      throwsA(
        isA<RoutineOccurrenceException>().having(
          (error) => error.code,
          'code',
          'invalid_routine_timezone',
        ),
      ),
    );
  });

  test('rejects a nonexistent local time during daylight-saving change', () {
    expect(
      () => engine.resolve(
        projection: _projection(
          dateIso: '2026-03-29',
          startTime: '02:30',
        ),
        timezoneId: 'Europe/Paris',
      ),
      throwsA(
        isA<RoutineOccurrenceException>().having(
          (error) => error.code,
          'code',
          'invalid_routine_local_time',
        ),
      ),
    );
  });
}

RoutineOccurrenceProjection _projection({
  String dateIso = '2026-08-04',
  String startTime = '14:00',
  int durationMinutes = 60,
  int travelGoMinutes = 0,
  int travelBackMinutes = 0,
  int marginMinutes = 0,
}) =>
    RoutineOccurrenceProjection(
      accountScopeId: 'account-a',
      windowStartDateIso: dateIso,
      windowEndDateExclusiveIso: _nextDate(dateIso),
      occurrences: [
        RoutineOccurrence(
          occurrenceId: 'routine-a:$dateIso',
          routineId: 'routine-a',
          accountScopeId: 'account-a',
          dateIso: dateIso,
          startTime: startTime,
          durationMinutes: durationMinutes,
          travelGoMinutes: travelGoMinutes,
          travelBackMinutes: travelBackMinutes,
          marginMinutes: marginMinutes,
          sourceUpdatedAt: DateTime.utc(2026, 8, 1),
        ),
      ],
    );

String _nextDate(String dateIso) {
  final parts = dateIso.split('-').map(int.parse).toList();
  final next = DateTime.utc(parts[0], parts[1], parts[2] + 1);
  return '${next.year.toString().padLeft(4, '0')}-'
      '${next.month.toString().padLeft(2, '0')}-'
      '${next.day.toString().padLeft(2, '0')}';
}
