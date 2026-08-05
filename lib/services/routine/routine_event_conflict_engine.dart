import '../../models/life_context/life_context_domains.dart';
import '../../models/proactive_detection.dart';
import '../../models/routine/routine_zoned_occurrence_models.dart';

/// RO.5 proves bounded Event/Routine protected-range overlaps.
///
/// It emits structured evidence only. It does not notify, persist, mutate, or
/// decide how a conflict should be resolved.
final class RoutineEventConflictEngine {
  const RoutineEventConflictEngine();

  List<StructuredConflictObservation> evaluate({
    required RoutineZonedOccurrenceProjection routineProjection,
    required RoutineDomainSection routineSection,
    required EventDomainSection eventSection,
    required DateTime observedAt,
    Duration horizon = const Duration(days: 14),
    int maximumConflicts = 50,
  }) {
    if (horizon <= Duration.zero ||
        horizon > const Duration(days: 31) ||
        maximumConflicts < 1 ||
        maximumConflicts > 100) {
      throw const FormatException('routine_conflict_policy_invalid');
    }
    final now = observedAt.toUtc();
    final limit = now.add(horizon);
    final events = eventSection.events
        .map(_protectedEvent)
        .whereType<_ProtectedEvent>()
        .where(
          (item) => item.end.isAfter(now) && item.start.isBefore(limit),
        )
        .toList(growable: false)
      ..sort((left, right) => left.id.compareTo(right.id));
    final routines = routineProjection.occurrences
        .where(
          (item) =>
              item.protectedEnd.isAfter(now) &&
              item.protectedStart.isBefore(limit),
        )
        .toList(growable: false)
      ..sort((left, right) => left.occurrenceId.compareTo(right.occurrenceId));
    final results = <StructuredConflictObservation>[];
    for (final event in events) {
      for (final routine in routines) {
        final overlapStart = event.start.isAfter(routine.protectedStart)
            ? event.start
            : routine.protectedStart;
        final overlapEnd = event.end.isBefore(routine.protectedEnd)
            ? event.end
            : routine.protectedEnd;
        if (!overlapEnd.isAfter(overlapStart)) continue;
        final routineRevision = routine.sourceUpdatedAt.millisecondsSinceEpoch;
        results.add(
          StructuredConflictObservation(
            conflictId:
                '${event.id}:${routine.occurrenceId}:protected-routine-v1',
            firstSourceId: event.id,
            secondSourceId: routine.occurrenceId,
            firstRevision: event.revision,
            secondRevision: routineRevision,
            confirmedByCanonicalEngine: true,
            evidence: [
              DetectionEvidence(
                sourceType: DetectionEvidenceSource.fixedEventInterval,
                domain: LifeContextDomain.event,
                sourceId: event.id,
                revision: event.revision,
                freshness: eventSection.metadata.freshness,
                availability: eventSection.metadata.availability,
                certainty: DetectionEvidenceLevel.confirmedStructured,
                intervalStart: overlapStart,
                intervalEnd: overlapEnd,
                confirmed: true,
              ),
              DetectionEvidence(
                sourceType:
                    DetectionEvidenceSource.structuredRoutineOccurrence,
                domain: LifeContextDomain.routine,
                sourceId: routine.occurrenceId,
                revision: routineRevision,
                freshness: routineSection.metadata.freshness,
                availability: routineSection.metadata.availability,
                certainty: DetectionEvidenceLevel.confirmedStructured,
                intervalStart: overlapStart,
                intervalEnd: overlapEnd,
                confirmed: true,
              ),
            ],
          ),
        );
        if (results.length == maximumConflicts) return results;
      }
    }
    return results;
  }

  _ProtectedEvent? _protectedEvent(EventContextItem event) {
    final start = DateTime.tryParse(event.startDateTimeIso)?.toUtc();
    final end = DateTime.tryParse(event.endDateTimeIso)?.toUtc();
    if (start == null || end == null || !end.isAfter(start)) return null;
    return _ProtectedEvent(
      id: event.id,
      revision: event.revision,
      start: start.subtract(Duration(minutes: event.travelGoMinutes)),
      end: end.add(
        Duration(minutes: event.travelBackMinutes + event.marginMinutes),
      ),
    );
  }
}

final class _ProtectedEvent {
  const _ProtectedEvent({
    required this.id,
    required this.revision,
    required this.start,
    required this.end,
  });

  final String id;
  final int revision;
  final DateTime start;
  final DateTime end;
}
