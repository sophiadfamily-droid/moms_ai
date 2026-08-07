import '../../models/event_model.dart';
import 'routine_agenda_service.dart';

/// Converts canonical routine occurrences into read-only planning blockers.
/// The synthetic Events are used only by conflict validation and are never
/// persisted.
final class RoutinePlanningBlockerService {
  const RoutinePlanningBlockerService({
    required RoutineAgendaService routineAgendaService,
  }) : _routineAgendaService = routineAgendaService;

  factory RoutinePlanningBlockerService.production() =>
      RoutinePlanningBlockerService(
        routineAgendaService: RoutineAgendaService.production(),
      );

  final RoutineAgendaService _routineAgendaService;

  Future<List<EventModel>> load({
    required String accountScopeId,
    required DateTime startDay,
    int days = 1,
  }) async {
    if (accountScopeId.trim().isEmpty || accountScopeId == 'guest') {
      throw StateError('routine_planning_scope_unavailable');
    }
    final routines = await _routineAgendaService.forWindow(
      accountScopeId: accountScopeId,
      startDay: startDay,
      days: days,
    );
    return routines
        .map(
          (routine) => EventModel(
            id: 'routine:${routine.occurrenceId}',
            title: routine.title,
            date: _dateIso(routine.protectedStart),
            time: _time(routine.protectedStart),
            notes: '',
            category: 'Routine',
            createdAt: routine.protectedStart,
            startDateTimeIso: routine.protectedStart.toIso8601String(),
            endTime: _time(routine.protectedEnd),
            endDateTimeIso: routine.protectedEnd.toIso8601String(),
            durationMinutes: routine.protectedEnd
                .difference(routine.protectedStart)
                .inMinutes,
          ),
        )
        .toList(growable: false);
  }

  static String _dateIso(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}
