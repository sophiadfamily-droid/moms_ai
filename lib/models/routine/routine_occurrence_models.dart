import 'dart:collection';

final class RoutineOccurrenceException implements Exception {
  const RoutineOccurrenceException(this.code);

  final String code;

  @override
  String toString() => 'RoutineOccurrenceException($code)';
}

/// A dated local-clock projection, deliberately not a persisted Event.
final class RoutineOccurrence {
  static const int currentSchemaVersion = 1;

  RoutineOccurrence({
    this.schemaVersion = currentSchemaVersion,
    required this.occurrenceId,
    required this.routineId,
    required this.accountScopeId,
    required this.dateIso,
    required this.startTime,
    required this.durationMinutes,
    required this.travelGoMinutes,
    required this.travelBackMinutes,
    required this.marginMinutes,
    required this.sourceUpdatedAt,
    this.originalDateIso,
    this.titleOverride,
  }) {
    if (schemaVersion != currentSchemaVersion ||
        occurrenceId.trim().isEmpty ||
        routineId.trim().isEmpty ||
        accountScopeId.trim().isEmpty ||
        _parseCivilDate(dateIso) == null ||
        (originalDateIso != null &&
            _parseCivilDate(originalDateIso!) == null) ||
        titleOverride?.trim().isEmpty == true ||
        (titleOverride?.length ?? 0) > 300 ||
        !RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(startTime) ||
        durationMinutes < 1 ||
        travelGoMinutes < 0 ||
        travelBackMinutes < 0 ||
        marginMinutes < 0 ||
        !sourceUpdatedAt.isUtc) {
      throw const RoutineOccurrenceException('invalid_routine_occurrence');
    }
  }

  final int schemaVersion;
  final String occurrenceId;
  final String routineId;
  final String accountScopeId;
  final String dateIso;
  final String startTime;
  final int durationMinutes;
  final int travelGoMinutes;
  final int travelBackMinutes;
  final int marginMinutes;
  final DateTime sourceUpdatedAt;
  final String? originalDateIso;
  final String? titleOverride;

  bool get isMoved => originalDateIso != null && originalDateIso != dateIso;

  String get endTime {
    final parts = startTime.split(':');
    final start =
        DateTime.utc(2000, 1, 1, int.parse(parts[0]), int.parse(parts[1]));
    final end = start.add(Duration(minutes: durationMinutes));
    return '${end.hour.toString().padLeft(2, '0')}:'
        '${end.minute.toString().padLeft(2, '0')}';
  }

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'occurrenceId': occurrenceId,
        'routineId': routineId,
        'accountScopeId': accountScopeId,
        'dateIso': dateIso,
        'startTime': startTime,
        'durationMinutes': durationMinutes,
        'travelGoMinutes': travelGoMinutes,
        'travelBackMinutes': travelBackMinutes,
        'marginMinutes': marginMinutes,
        'sourceUpdatedAt': sourceUpdatedAt.toIso8601String(),
        if (originalDateIso != null) 'originalDateIso': originalDateIso,
        if (titleOverride != null) 'titleOverride': titleOverride,
      };
}

final class RoutineOccurrenceProjection {
  static const int currentSchemaVersion = 1;
  static const int maximumOccurrences = 400;

  RoutineOccurrenceProjection({
    this.schemaVersion = currentSchemaVersion,
    required this.accountScopeId,
    required this.windowStartDateIso,
    required this.windowEndDateExclusiveIso,
    required List<RoutineOccurrence> occurrences,
  }) : occurrences = UnmodifiableListView(occurrences) {
    final start = _parseCivilDate(windowStartDateIso);
    final end = _parseCivilDate(windowEndDateExclusiveIso);
    if (schemaVersion != currentSchemaVersion ||
        accountScopeId.trim().isEmpty ||
        start == null ||
        end == null ||
        !end.isAfter(start) ||
        occurrences.length > maximumOccurrences ||
        occurrences.any((item) => item.accountScopeId != accountScopeId) ||
        occurrences.any((item) {
          final date = _parseCivilDate(item.dateIso)!;
          return date.isBefore(start) || !date.isBefore(end);
        }) ||
        occurrences.map((item) => item.occurrenceId).toSet().length !=
            occurrences.length) {
      throw const RoutineOccurrenceException(
        'invalid_routine_occurrence_projection',
      );
    }
  }

  final int schemaVersion;
  final String accountScopeId;
  final String windowStartDateIso;
  final String windowEndDateExclusiveIso;
  final List<RoutineOccurrence> occurrences;

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'accountScopeId': accountScopeId,
        'windowStartDateIso': windowStartDateIso,
        'windowEndDateExclusiveIso': windowEndDateExclusiveIso,
        'occurrences': occurrences.map((item) => item.toJson()).toList(),
      };
}

DateTime? _parseCivilDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final parsed = DateTime.utc(year, month, day);
  return parsed.year == year && parsed.month == month && parsed.day == day
      ? parsed
      : null;
}
