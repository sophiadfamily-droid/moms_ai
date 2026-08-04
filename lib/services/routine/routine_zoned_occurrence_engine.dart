import 'package:timezone/timezone.dart' as tz;

import '../../models/routine/routine_occurrence_models.dart';
import '../../models/routine/routine_zoned_occurrence_models.dart';

/// RO.4 resolves local-clock occurrences only when a timezone is explicit.
///
/// It performs no persistence, notification, conflict decision, or Event
/// creation. Impossible wall-clock values fail closed.
final class RoutineZonedOccurrenceEngine {
  const RoutineZonedOccurrenceEngine();

  RoutineZonedOccurrenceProjection resolve({
    required RoutineOccurrenceProjection projection,
    required String timezoneId,
  }) {
    final normalizedTimezone = timezoneId.trim();
    late final tz.Location location;
    try {
      location = tz.getLocation(normalizedTimezone);
    } on Object {
      throw const RoutineOccurrenceException('invalid_routine_timezone');
    }

    final resolved = projection.occurrences.map((occurrence) {
      final date = occurrence.dateIso.split('-').map(int.parse).toList();
      final time = occurrence.startTime.split(':').map(int.parse).toList();
      final local = tz.TZDateTime(
        location,
        date[0],
        date[1],
        date[2],
        time[0],
        time[1],
      );
      if (local.year != date[0] ||
          local.month != date[1] ||
          local.day != date[2] ||
          local.hour != time[0] ||
          local.minute != time[1]) {
        throw const RoutineOccurrenceException(
          'invalid_routine_local_time',
        );
      }
      final start = local.toUtc();
      final end = start.add(Duration(minutes: occurrence.durationMinutes));
      return RoutineZonedOccurrence(
        occurrenceId: occurrence.occurrenceId,
        routineId: occurrence.routineId,
        accountScopeId: occurrence.accountScopeId,
        timezoneId: normalizedTimezone,
        start: start,
        end: end,
        protectedStart: start.subtract(
          Duration(minutes: occurrence.travelGoMinutes),
        ),
        protectedEnd: end.add(
          Duration(
            minutes: occurrence.travelBackMinutes + occurrence.marginMinutes,
          ),
        ),
        sourceUpdatedAt: occurrence.sourceUpdatedAt,
      );
    }).toList(growable: false)
      ..sort((left, right) {
        final start = left.start.compareTo(right.start);
        return start != 0
            ? start
            : left.occurrenceId.compareTo(right.occurrenceId);
      });

    return RoutineZonedOccurrenceProjection(
      accountScopeId: projection.accountScopeId,
      timezoneId: normalizedTimezone,
      occurrences: resolved,
    );
  }
}
