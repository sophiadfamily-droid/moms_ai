import '../../models/routine/routine_agenda_item.dart';
import '../../models/routine_model.dart';
import '../routine_repository.dart';
import 'routine_occurrence_engine.dart';

typedef RoutineAgendaLoader = Future<List<RoutineModel>> Function(
  String accountScopeId,
);

/// Projects canonical routines into read-only Agenda rows for one civil day.
/// It does not create, edit, or persist Events.
final class RoutineAgendaService {
  const RoutineAgendaService({
    required RoutineAgendaLoader loadRoutines,
    RoutineOccurrenceEngine engine = const RoutineOccurrenceEngine(),
  })  : _loadRoutines = loadRoutines,
        _engine = engine;

  factory RoutineAgendaService.production({RoutineRepository? repository}) {
    final source = repository ?? FirestoreRoutineRepository();
    return RoutineAgendaService(loadRoutines: source.listForAccount);
  }

  final RoutineAgendaLoader _loadRoutines;
  final RoutineOccurrenceEngine _engine;

  Future<List<RoutineAgendaItem>> forDay({
    required String accountScopeId,
    required DateTime day,
  }) =>
      forWindow(accountScopeId: accountScopeId, startDay: day, days: 1);

  Future<List<RoutineAgendaItem>> forWindow({
    required String accountScopeId,
    required DateTime startDay,
    required int days,
  }) async {
    if (accountScopeId.trim().isEmpty || accountScopeId == 'guest') {
      return const [];
    }
    if (days < 1 || days > 31) {
      throw const FormatException('invalid_routine_agenda_window');
    }
    final routines = await _loadRoutines(accountScopeId);
    final byId = {for (final routine in routines) routine.id: routine};
    final start = DateTime.utc(startDay.year, startDay.month, startDay.day);
    final projection = _engine.project(
      accountScopeId: accountScopeId,
      windowStartDate: start,
      windowEndDateExclusive: start.add(Duration(days: days)),
      routines: routines,
    );
    return projection.occurrences.map((occurrence) {
      final routine = byId[occurrence.routineId]!;
      final timeParts = occurrence.startTime.split(':');
      final dateParts = occurrence.dateIso.split('-');
      final startTime = DateTime(
        int.parse(dateParts[0]),
        int.parse(dateParts[1]),
        int.parse(dateParts[2]),
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
      );
      return RoutineAgendaItem(
        occurrenceId: occurrence.occurrenceId,
        routineId: occurrence.routineId,
        dateIso: occurrence.dateIso,
        title: routine.title,
        startTime: occurrence.startTime,
        endTime: routine.endTime,
        protectedStart: startTime.subtract(
          Duration(minutes: occurrence.travelGoMinutes),
        ),
        protectedEnd: startTime.add(
          Duration(
            minutes: occurrence.durationMinutes +
                occurrence.travelBackMinutes +
                occurrence.marginMinutes,
          ),
        ),
      );
    }).toList(growable: false);
  }
}
