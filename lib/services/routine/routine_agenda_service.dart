import '../../models/routine/routine_agenda_item.dart';
import '../../models/routine/routine_occurrence_override.dart';
import '../../models/routine/routine_schedule_definition.dart';
import '../../models/routine_model.dart';
import '../cloud_profile_service.dart';
import '../routine_repository.dart';
import 'routine_occurrence_override_repository.dart';
import 'routine_occurrence_engine.dart';
import 'routine_schedule_catalog_service.dart';

typedef RoutineAgendaLoader = Future<List<RoutineModel>> Function(
  String accountScopeId,
);
typedef RoutineAgendaOverrideLoader = Future<List<RoutineOccurrenceOverride>>
    Function(String accountScopeId);
typedef RoutineAgendaCatalogLoader = Future<List<RoutineScheduleDefinition>>
    Function(String accountScopeId);

/// Projects canonical routines into read-only Agenda rows for one civil day.
/// It does not create, edit, or persist Events.
final class RoutineAgendaService {
  RoutineAgendaService({
    required RoutineAgendaLoader loadRoutines,
    RoutineAgendaOverrideLoader? loadOverrides,
    RoutineScheduleProfileLoader? loadProfile,
    RoutineAgendaCatalogLoader? loadCatalog,
    RoutineOccurrenceEngine engine = const RoutineOccurrenceEngine(),
  })  : _loadCatalog = loadCatalog ??
            RoutineScheduleCatalogService(
              loadRoutines: loadRoutines,
              loadProfile: loadProfile,
            ).forAccount,
        _loadOverrides = loadOverrides,
        _engine = engine;

  factory RoutineAgendaService.production({
    RoutineRepository? repository,
    RoutineOccurrenceOverrideRepository? overrideRepository,
    RoutineScheduleProfileLoader? loadProfile,
  }) {
    final source = repository ?? FirestoreRoutineRepository();
    final overrideSource =
        overrideRepository ?? FirestoreRoutineOccurrenceOverrideRepository();
    return RoutineAgendaService(
      loadRoutines: source.listForAccount,
      loadOverrides: overrideSource.listForAccount,
      loadProfile: loadProfile ?? CloudProfileService.getProfile,
    );
  }

  final RoutineAgendaCatalogLoader _loadCatalog;
  final RoutineAgendaOverrideLoader? _loadOverrides;
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
    final catalog = await _loadCatalog(accountScopeId);
    final routines = catalog.map((entry) => entry.routine).toList();
    final overrides = _loadOverrides == null
        ? const <RoutineOccurrenceOverride>[]
        : await _loadOverrides(accountScopeId);
    final byId = {
      for (final definition in catalog) definition.routine.id: definition,
    };
    final start = DateTime.utc(startDay.year, startDay.month, startDay.day);
    final projection = _engine.project(
      accountScopeId: accountScopeId,
      windowStartDate: start,
      windowEndDateExclusive: start.add(Duration(days: days)),
      routines: routines,
      overrides: overrides,
    );
    return projection.occurrences.map((occurrence) {
      final definition = byId[occurrence.routineId]!;
      final routine = definition.routine;
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
        title: occurrence.titleOverride ?? routine.title,
        startTime: occurrence.startTime,
        endTime: occurrence.endTime,
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
        kind: definition.kind,
        blocksPrimaryUser: definition.blocksPrimaryUser,
        subjectLabel: definition.subjectLabel,
      );
    }).toList(growable: false);
  }
}
