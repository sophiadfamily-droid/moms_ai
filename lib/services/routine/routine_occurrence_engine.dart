import '../../models/routine/routine_occurrence_models.dart';
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
    final occurrences = <RoutineOccurrence>[];
    for (var date = start;
        date.isBefore(end);
        date = date.add(const Duration(days: 1))) {
      for (final routine in active) {
        if (!_applies(routine, date)) continue;
        if (occurrences.length ==
            RoutineOccurrenceProjection.maximumOccurrences) {
          throw const RoutineOccurrenceException(
            'routine_occurrence_budget_exceeded',
          );
        }
        final dateIso = _dateIso(date);
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
          ),
        );
      }
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
}
