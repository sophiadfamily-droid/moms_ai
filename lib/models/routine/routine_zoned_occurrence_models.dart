import 'dart:collection';

import 'routine_occurrence_models.dart';

/// One canonical Routine occurrence resolved to explicit UTC instants.
///
/// This remains a read-only projection. It is not an Event and contains no
/// user-facing content.
final class RoutineZonedOccurrence {
  const RoutineZonedOccurrence({
    required this.occurrenceId,
    required this.routineId,
    required this.accountScopeId,
    required this.timezoneId,
    required this.start,
    required this.end,
    required this.protectedStart,
    required this.protectedEnd,
    required this.sourceUpdatedAt,
  });

  final String occurrenceId;
  final String routineId;
  final String accountScopeId;
  final String timezoneId;
  final DateTime start;
  final DateTime end;
  final DateTime protectedStart;
  final DateTime protectedEnd;
  final DateTime sourceUpdatedAt;

  void validate() {
    if (occurrenceId.trim().isEmpty ||
        routineId.trim().isEmpty ||
        accountScopeId.trim().isEmpty ||
        timezoneId.trim().isEmpty ||
        !start.isUtc ||
        !end.isUtc ||
        !protectedStart.isUtc ||
        !protectedEnd.isUtc ||
        !sourceUpdatedAt.isUtc ||
        !end.isAfter(start) ||
        protectedStart.isAfter(start) ||
        protectedEnd.isBefore(end)) {
      throw const RoutineOccurrenceException('invalid_zoned_occurrence');
    }
  }

  Map<String, Object?> toJson() => {
        'occurrenceId': occurrenceId,
        'routineId': routineId,
        'accountScopeId': accountScopeId,
        'timezoneId': timezoneId,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'protectedStart': protectedStart.toIso8601String(),
        'protectedEnd': protectedEnd.toIso8601String(),
        'sourceUpdatedAt': sourceUpdatedAt.toIso8601String(),
      };
}

final class RoutineZonedOccurrenceProjection {
  RoutineZonedOccurrenceProjection({
    required this.accountScopeId,
    required this.timezoneId,
    required List<RoutineZonedOccurrence> occurrences,
  }) : occurrences = UnmodifiableListView(occurrences) {
    if (accountScopeId.trim().isEmpty ||
        timezoneId.trim().isEmpty ||
        occurrences.length > RoutineOccurrenceProjection.maximumOccurrences ||
        occurrences.any(
          (item) =>
              item.accountScopeId != accountScopeId ||
              item.timezoneId != timezoneId,
        ) ||
        occurrences.map((item) => item.occurrenceId).toSet().length !=
            occurrences.length) {
      throw const RoutineOccurrenceException(
        'invalid_zoned_occurrence_projection',
      );
    }
    for (final occurrence in occurrences) {
      occurrence.validate();
    }
  }

  final String accountScopeId;
  final String timezoneId;
  final List<RoutineZonedOccurrence> occurrences;

  Map<String, Object?> toJson() => {
        'accountScopeId': accountScopeId,
        'timezoneId': timezoneId,
        'occurrences': occurrences.map((item) => item.toJson()).toList(),
      };
}
