import '../models/proactive_detection.dart';
import '../models/life_context/life_context_domains.dart';
import 'event_service.dart';
import 'life_context/life_context_relation_engine.dart';
import 'life_context_production_factory.dart';
import 'proactive_detection_engine.dart';
import 'proactive_detection_life_context_adapter.dart';
import 'proactive_detection_lifecycle.dart';

/// Production read boundary. Canonical planning conflict observations are
/// supplied only when the Planning boundary can prove them; absence is not
/// treated as proof that no conflict exists.
final class ProductionProactiveDetectionInputProvider
    implements ProactiveDetectionInputProvider {
  const ProductionProactiveDetectionInputProvider({
    this.confirmedConflicts = _confirmedPlanningConflicts,
    this.currentTimezoneId = _utcTimezone,
  });

  final Future<List<StructuredConflictObservation>> Function(
    String accountScopeId,
  ) confirmedConflicts;
  final Future<String> Function() currentTimezoneId;

  @override
  Future<ProactiveDetectionInput> load({
    required String accountScopeId,
    required List<ProactiveDetectionSignal> existingSignals,
    required DetectionEvaluationTrigger trigger,
  }) async {
    final lifeContext = await LifeContextProductionFactory.production();
    lifeContext.handleAccountScopeChanged(accountScopeId);
    final snapshot = await lifeContext.refreshIfNeeded();
    final graph = lifeContext.currentGraph ??
        const LifeContextRelationEngine().build(snapshot);
    var conflictSourceAvailable = true;
    List<StructuredConflictObservation> conflicts;
    try {
      conflicts = await confirmedConflicts(accountScopeId);
    } on Object {
      conflictSourceAvailable = false;
      conflicts = const [];
    }
    return const ProactiveDetectionLifeContextAdapter().adapt(
      snapshot: snapshot,
      graph: graph,
      confirmedConflicts: conflicts,
      conflictSourceAvailable: conflictSourceAvailable,
      existingSignals: existingSignals,
      timezoneId: await currentTimezoneId(),
    );
  }

  static Future<List<StructuredConflictObservation>>
      _confirmedPlanningConflicts(
    String accountScopeId,
  ) async {
    final references =
        await EventService.getProtectedConflictsForDetection(accountScopeId);
    return references
        .map(
          (item) => StructuredConflictObservation(
            conflictId:
                '${item.firstEventId}:${item.secondEventId}:protected-v1',
            firstSourceId: item.firstEventId,
            secondSourceId: item.secondEventId,
            firstRevision: item.firstRevision,
            secondRevision: item.secondRevision,
            confirmedByCanonicalEngine: true,
            evidence: [
              DetectionEvidence(
                sourceType: DetectionEvidenceSource.confirmedConflictResult,
                domain: LifeContextDomain.event,
                sourceId: item.firstEventId,
                revision: item.firstRevision,
                freshness: LifeContextFreshness.current,
                availability: LifeContextAvailability.available,
                certainty: DetectionEvidenceLevel.confirmedStructured,
                intervalStart: item.protectedStart,
                intervalEnd: item.protectedEnd,
                confirmed: true,
              ),
              DetectionEvidence(
                sourceType: DetectionEvidenceSource.confirmedConflictResult,
                domain: LifeContextDomain.event,
                sourceId: item.secondEventId,
                revision: item.secondRevision,
                freshness: LifeContextFreshness.current,
                availability: LifeContextAvailability.available,
                certainty: DetectionEvidenceLevel.confirmedStructured,
                intervalStart: item.protectedStart,
                intervalEnd: item.protectedEnd,
                confirmed: true,
              ),
            ],
          ),
        )
        .toList(growable: false);
  }

  static Future<String> _utcTimezone() async => 'Etc/UTC';
}
