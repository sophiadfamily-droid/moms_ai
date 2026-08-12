import '../../models/routine/routine_occurrence_models.dart';
import '../../models/routine/routine_occurrence_override.dart';
import '../../models/routine/routine_zoned_occurrence_models.dart';
import '../../models/routine_model.dart';
import '../routine_repository.dart';
import 'routine_occurrence_engine.dart';
import 'routine_occurrence_override_repository.dart';
import 'routine_zoned_occurrence_engine.dart';

typedef RoutineOccurrenceLoader = Future<List<RoutineModel>> Function(
  String accountScopeId,
);
typedef RoutineOccurrenceOverrideLoader
    = Future<List<RoutineOccurrenceOverride>> Function(String accountScopeId);

/// RO.2 loads canonical routines, then delegates dated projection to RO.1.
/// It never persists an occurrence or turns one into an Event.
final class RoutineOccurrenceService {
  const RoutineOccurrenceService({
    required RoutineOccurrenceLoader loadRoutines,
    RoutineOccurrenceOverrideLoader? loadOverrides,
    RoutineOccurrenceEngine engine = const RoutineOccurrenceEngine(),
    RoutineZonedOccurrenceEngine zonedEngine =
        const RoutineZonedOccurrenceEngine(),
  })  : _loadRoutines = loadRoutines,
        _loadOverrides = loadOverrides,
        _engine = engine,
        _zonedEngine = zonedEngine;

  factory RoutineOccurrenceService.production({
    RoutineRepository? repository,
    RoutineOccurrenceOverrideRepository? overrideRepository,
  }) {
    final source = repository ?? FirestoreRoutineRepository();
    final overrideSource =
        overrideRepository ?? FirestoreRoutineOccurrenceOverrideRepository();
    return RoutineOccurrenceService(
      loadRoutines: source.listForAccount,
      loadOverrides: overrideSource.listForAccount,
    );
  }

  final RoutineOccurrenceLoader _loadRoutines;
  final RoutineOccurrenceOverrideLoader? _loadOverrides;
  final RoutineOccurrenceEngine _engine;
  final RoutineZonedOccurrenceEngine _zonedEngine;

  Future<RoutineOccurrenceProjection> project({
    required String accountScopeId,
    required DateTime windowStartDate,
    required DateTime windowEndDateExclusive,
  }) async {
    if (accountScopeId.trim().isEmpty) {
      throw const RoutineOccurrenceException('invalid_routine_account');
    }
    final routines = await _loadRoutines(accountScopeId);
    final overrides = _loadOverrides == null
        ? const <RoutineOccurrenceOverride>[]
        : await _loadOverrides(accountScopeId);
    return _engine.project(
      accountScopeId: accountScopeId,
      windowStartDate: windowStartDate,
      windowEndDateExclusive: windowEndDateExclusive,
      routines: routines,
      overrides: overrides,
    );
  }

  Future<RoutineZonedOccurrenceProjection> projectZoned({
    required String accountScopeId,
    required DateTime windowStartDate,
    required DateTime windowEndDateExclusive,
    required String timezoneId,
  }) async {
    final localClockProjection = await project(
      accountScopeId: accountScopeId,
      windowStartDate: windowStartDate,
      windowEndDateExclusive: windowEndDateExclusive,
    );
    return _zonedEngine.resolve(
      projection: localClockProjection,
      timezoneId: timezoneId,
    );
  }
}
