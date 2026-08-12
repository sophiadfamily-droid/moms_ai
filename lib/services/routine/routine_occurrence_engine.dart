import '../../models/routine/routine_occurrence_models.dart';
import '../../models/routine/routine_occurrence_override.dart';
import '../../models/routine_model.dart';
import 'routine_date_applicability_engine.dart';

/// V1-RO.1 projects active routines onto bounded civil dates.
///
/// It emits local-clock facts only: no timezone is invented, no Event is
/// created, and no persistence or notification is triggered.
final class RoutineOccurrenceEngine {
  const RoutineOccurrenceEngine({
    RoutineDateApplicabilityEngine dateApplicabilityEngine =
        const RoutineDateApplicabilityEngine(),
  }) : _dateApplicabilityEngine = dateApplicabilityEngine;

  final RoutineDateApplicabilityEngine _dateApplicabilityEngine;

  RoutineOccurrenceProjection project({
    required String accountScopeId,
    required DateTime windowStartDate,
    required DateTime windowEndDateExclusive,
    required List<RoutineModel> routines,
    List<RoutineOccurrenceOverride> overrides = const [],
  }) {
    final start = _civilUtc(windowStartDate);
    final end = _civilUtc(windowEndDateExclusive);
    final days = end.difference(start).inDays;
    if (accountScopeId.trim().isEmpty || days < 1 || days > 366) {
      throw const RoutineOccurrenceException('invalid_routine_window');
    }

    final active = routines.where((routine) {
      if (routine.accountScopeId != accountScopeId) {
        throw const RoutineOccurrenceException('routine_account_mismatch');
      }
      return routine.status == RoutineStatus.active;
    }).toList()
      ..sort((left, right) => left.id.compareTo(right.id));
    final activeById = {for (final routine in active) routine.id: routine};
    final overrideByOccurrence = <String, RoutineOccurrenceOverride>{};
    for (final override in overrides) {
      if (override.accountScopeId != accountScopeId) {
        throw const RoutineOccurrenceException(
          'routine_override_account_mismatch',
        );
      }
      if (override.tombstone || !activeById.containsKey(override.routineId)) {
        continue;
      }
      final sourceDate = _parseDateIso(override.sourceDateIso);
      final routine = activeById[override.routineId]!;
      if (sourceDate == null || !_applies(routine, sourceDate)) continue;
      if (overrideByOccurrence.containsKey(override.occurrenceKey)) {
        throw const RoutineOccurrenceException(
          'duplicate_routine_occurrence_override',
        );
      }
      overrideByOccurrence[override.occurrenceKey] = override;
    }
    final occurrences = <RoutineOccurrence>[];
    for (var date = start;
        date.isBefore(end);
        date = date.add(const Duration(days: 1))) {
      for (final routine in active) {
        if (!_applies(routine, date)) continue;
        final dateIso = _dateIso(date);
        final occurrenceOverride =
            overrideByOccurrence['${routine.id}:$dateIso'];
        if (occurrenceOverride?.type ==
                RoutineOccurrenceOverrideType.cancelled ||
            occurrenceOverride?.type == RoutineOccurrenceOverrideType.moved) {
          continue;
        }
        if (occurrenceOverride?.type ==
                RoutineOccurrenceOverrideType.replaced &&
            occurrenceOverride?.replacementLabel == null) {
          continue;
        }
        if (occurrences.length ==
            RoutineOccurrenceProjection.maximumOccurrences) {
          throw const RoutineOccurrenceException(
            'routine_occurrence_budget_exceeded',
          );
        }
        occurrences.add(
          RoutineOccurrence(
            occurrenceId: '${routine.id}:$dateIso',
            routineId: routine.id,
            accountScopeId: accountScopeId,
            dateIso: dateIso,
            startTime: routine.startTime,
            durationMinutes: routine.durationMinutes,
            travelGoMinutes: routine.travelGoMinutes,
            travelBackMinutes: routine.travelBackMinutes,
            marginMinutes: routine.marginMinutes,
            sourceUpdatedAt: routine.updatedAt,
            titleOverride: occurrenceOverride?.replacementLabel,
          ),
        );
      }
    }

    final occupiedRoutineDates =
        occurrences.map((item) => '${item.routineId}:${item.dateIso}').toSet();
    for (final override in overrideByOccurrence.values) {
      if (override.type != RoutineOccurrenceOverrideType.moved) continue;
      final replacementDate = _parseDateIso(override.replacementDateIso!);
      if (replacementDate == null ||
          replacementDate.isBefore(start) ||
          !replacementDate.isBefore(end)) {
        continue;
      }
      if (occurrences.length ==
          RoutineOccurrenceProjection.maximumOccurrences) {
        throw const RoutineOccurrenceException(
          'routine_occurrence_budget_exceeded',
        );
      }
      final routine = activeById[override.routineId]!;
      final destinationKey = '${routine.id}:${override.replacementDateIso}';
      if (!occupiedRoutineDates.add(destinationKey)) {
        throw const RoutineOccurrenceException(
          'routine_override_destination_conflict',
        );
      }
      occurrences.add(
        RoutineOccurrence(
          occurrenceId: override.occurrenceKey,
          routineId: routine.id,
          accountScopeId: accountScopeId,
          dateIso: override.replacementDateIso!,
          originalDateIso: override.sourceDateIso,
          startTime: override.replacementStartTime!,
          durationMinutes: routine.durationMinutes,
          travelGoMinutes: routine.travelGoMinutes,
          travelBackMinutes: routine.travelBackMinutes,
          marginMinutes: routine.marginMinutes,
          sourceUpdatedAt: override.updatedAt.isAfter(routine.updatedAt)
              ? override.updatedAt
              : routine.updatedAt,
        ),
      );
    }

    occurrences.sort((left, right) {
      final date = left.dateIso.compareTo(right.dateIso);
      if (date != 0) return date;
      final time = left.startTime.compareTo(right.startTime);
      if (time != 0) return time;
      return left.routineId.compareTo(right.routineId);
    });
    return RoutineOccurrenceProjection(
      accountScopeId: accountScopeId,
      windowStartDateIso: _dateIso(start),
      windowEndDateExclusiveIso: _dateIso(end),
      occurrences: occurrences,
    );
  }

  bool _applies(RoutineModel routine, DateTime date) =>
      _dateApplicabilityEngine.applies(
        recurrenceType: routine.recurrenceType.name,
        weekdays: routine.days,
        date: date,
        anchorDateIso: routine.anchorDateIso,
        weekOfMonth: routine.weekOfMonth,
      );

  DateTime _civilUtc(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  String _dateIso(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  DateTime? _parseDateIso(String value) {
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
}
