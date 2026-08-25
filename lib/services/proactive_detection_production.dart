import '../models/proactive_detection.dart';
import '../models/life_context/life_context_domains.dart';
import '../models/life_context/life_context_snapshot.dart';
import 'package:timezone/timezone.dart' as tz;
import 'app_diagnostics.dart';
import 'life_context/event_life_context_conflict_engine.dart';
import 'life_context/life_context_relation_engine.dart';
import 'life_context_production_factory.dart';
import 'proactive_detection_engine.dart';
import 'proactive_detection_life_context_adapter.dart';
import 'proactive_detection_lifecycle.dart';
import 'routine/routine_event_conflict_engine.dart';
import 'routine/routine_occurrence_service.dart';

typedef ConfirmedRoutineConflicts = Future<List<StructuredConflictObservation>>
    Function({
  required String accountScopeId,
  required LifeContextSnapshot snapshot,
  required String timezoneId,
});

typedef ConfirmedEventConflicts = Future<List<StructuredConflictObservation>>
    Function({
  required String accountScopeId,
  required LifeContextSnapshot snapshot,
});

/// Production read boundary. Canonical planning conflict observations are
/// supplied only when the Planning boundary can prove them; absence is not
/// treated as proof that no conflict exists.
final class ProductionProactiveDetectionInputProvider
    implements ProactiveDetectionInputProvider {
  const ProductionProactiveDetectionInputProvider({
    this.confirmedConflicts = _confirmedPlanningConflicts,
    this.confirmedRoutineConflicts = _confirmedRoutinePlanningConflicts,
    this.currentTimezoneId = _utcTimezone,
  });

  final ConfirmedEventConflicts confirmedConflicts;
  final ConfirmedRoutineConflicts confirmedRoutineConflicts;
  final Future<String> Function() currentTimezoneId;

  @override
  Future<ProactiveDetectionInput> load({
    required String accountScopeId,
    required List<ProactiveDetectionSignal> existingSignals,
    required DetectionEvaluationTrigger trigger,
  }) async {
    final lifeContext = await LifeContextProductionFactory.production();
    lifeContext.handleAccountScopeChanged(accountScopeId);
    // The domain notifier and the detection listener are both synchronous.
    // Do not depend on their registration order: mark the changed canonical
    // section dirty before reading the snapshot used to validate detections.
    switch (trigger) {
      case DetectionEvaluationTrigger.eventChanged:
        lifeContext.invalidateSection(LifeContextDomain.event);
      case DetectionEvaluationTrigger.taskChanged:
        lifeContext.invalidateSection(LifeContextDomain.task);
      case DetectionEvaluationTrigger.routineChanged:
        lifeContext.invalidateSection(LifeContextDomain.routine);
      case DetectionEvaluationTrigger.explicitInternalRefresh:
        lifeContext
          ..invalidateSection(LifeContextDomain.event)
          ..invalidateSection(LifeContextDomain.task)
          ..invalidateSection(LifeContextDomain.routine);
      case DetectionEvaluationTrigger.authenticatedBootstrap:
      case DetectionEvaluationTrigger.foreground:
      case DetectionEvaluationTrigger.dependencyChanged:
      case DetectionEvaluationTrigger.timezoneChanged:
      case DetectionEvaluationTrigger.sourceResolved:
      case DetectionEvaluationTrigger.networkRestored:
        break;
    }
    final snapshot = await lifeContext.refreshIfNeeded();
    final graph = lifeContext.currentGraph ??
        const LifeContextRelationEngine().build(snapshot);
    final timezoneId = await currentTimezoneId();
    var conflictSourceAvailable = true;
    var routineConflictSourceAvailable = true;
    List<StructuredConflictObservation> eventConflicts;
    try {
      eventConflicts = await confirmedConflicts(
        accountScopeId: accountScopeId,
        snapshot: snapshot,
      );
    } on Object {
      conflictSourceAvailable = false;
      eventConflicts = const [];
    }
    _recordConflictSource(
      step: 'event_conflict_source',
      available: conflictSourceAvailable,
      count: eventConflicts.length,
    );
    List<StructuredConflictObservation> routineConflicts;
    try {
      routineConflicts = await confirmedRoutineConflicts(
        accountScopeId: accountScopeId,
        snapshot: snapshot,
        timezoneId: timezoneId,
      );
    } on Object {
      routineConflictSourceAvailable = false;
      routineConflicts = const [];
    }
    _recordConflictSource(
      step: 'routine_conflict_source',
      available: routineConflictSourceAvailable,
      count: routineConflicts.length,
    );
    return const ProactiveDetectionLifeContextAdapter().adapt(
      snapshot: snapshot,
      graph: graph,
      confirmedConflicts: [...eventConflicts, ...routineConflicts],
      conflictSourceAvailable: conflictSourceAvailable,
      routineConflictSourceAvailable: routineConflictSourceAvailable,
      existingSignals: existingSignals,
      timezoneId: timezoneId,
    );
  }

  static Future<List<StructuredConflictObservation>>
      _confirmedRoutinePlanningConflicts({
    required String accountScopeId,
    required LifeContextSnapshot snapshot,
    required String timezoneId,
  }) async {
    snapshot.validateCanonical();
    if (snapshot.accountScopeId != accountScopeId) {
      throw const FormatException('routine_conflict_account_mismatch');
    }
    final location = tz.getLocation(timezoneId);
    final observedAt = snapshot.generatedAt.toUtc();
    final local = tz.TZDateTime.from(observedAt, location);
    final start = DateTime.utc(local.year, local.month, local.day);
    final projection = await RoutineOccurrenceService.production().projectZoned(
      accountScopeId: accountScopeId,
      windowStartDate: start,
      windowEndDateExclusive: start.add(const Duration(days: 15)),
      timezoneId: timezoneId,
    );
    return const RoutineEventConflictEngine().evaluate(
      routineProjection: projection,
      routineSection: snapshot.routineDomain!,
      eventSection: snapshot.eventDomain!,
      observedAt: observedAt,
    );
  }

  static Future<List<StructuredConflictObservation>>
      _confirmedPlanningConflicts({
    required String accountScopeId,
    required LifeContextSnapshot snapshot,
  }) async {
    snapshot.validateCanonical();
    if (snapshot.accountScopeId != accountScopeId) {
      throw const FormatException('event_conflict_account_mismatch');
    }
    return const EventLifeContextConflictEngine().evaluate(
      eventSection: snapshot.eventDomain!,
      observedAt: snapshot.generatedAt,
    );
  }

  static Future<String> _utcTimezone() async => 'Etc/UTC';

  static void _recordConflictSource({
    required String step,
    required bool available,
    required int count,
  }) {
    AppDiagnostics.record(
      component: 'proactive_detection',
      domain: 'notification',
      operation: 'load',
      step: step,
      code: available
          ? (count > 0
              ? AppErrorCode.proactiveShow
              : AppErrorCode.proactiveNoShow)
          : AppErrorCode.dependencyUnavailable,
      severity:
          available ? AppErrorSeverity.info : AppErrorSeverity.recoverableError,
      metadata: {
        'status': available ? 'available' : 'unavailable',
        'count': count,
      },
    );
  }
}
