import '../../models/life_context/life_context_domains.dart';
import '../../models/proactive_detection.dart';

/// Pure, bounded Event/Event conflict proof over one canonical Life Context
/// generation.
///
/// The Event domain already exposes the resolved travel values used by the
/// canonical protected-range rule. This engine never reads or mutates the
/// Agenda; it only proves overlaps inside the supplied snapshot section.
final class EventLifeContextConflictEngine {
  const EventLifeContextConflictEngine();

  List<StructuredConflictObservation> evaluate({
    required EventDomainSection eventSection,
    required DateTime observedAt,
    int maximumEvents = 100,
    int maximumConflicts = 50,
  }) {
    if (eventSection.metadata.domain != LifeContextDomain.event ||
        maximumEvents < 1 ||
        maximumEvents > 200 ||
        maximumConflicts < 1 ||
        maximumConflicts > 100) {
      throw const FormatException('event_conflict_detection_policy_invalid');
    }
    switch (eventSection.metadata.availability) {
      case LifeContextAvailability.unavailable:
      case LifeContextAvailability.unsupported:
      case LifeContextAvailability.corrupted:
      case LifeContextAvailability.accountMismatch:
        throw const FormatException('event_conflict_source_unavailable');
      case LifeContextAvailability.available:
      case LifeContextAvailability.availableStale:
      case LifeContextAvailability.empty:
        break;
    }

    final current = observedAt.toUtc();
    final events = eventSection.events
        .map(_protectedEvent)
        .whereType<_ProtectedEvent>()
        .where((event) => event.end.isAfter(current))
        .toList(growable: false)
      ..sort((first, second) {
        final byStart = first.start.compareTo(second.start);
        return byStart != 0 ? byStart : first.id.compareTo(second.id);
      });
    final boundedEvents = events.take(maximumEvents).toList(growable: false);
    final conflicts = <StructuredConflictObservation>[];
    for (var first = 0; first < boundedEvents.length; first++) {
      for (var second = first + 1; second < boundedEvents.length; second++) {
        final left = boundedEvents[first];
        final right = boundedEvents[second];
        final overlapStart =
            left.start.isAfter(right.start) ? left.start : right.start;
        final overlapEnd = left.end.isBefore(right.end) ? left.end : right.end;
        if (!overlapEnd.isAfter(overlapStart)) continue;
        conflicts.add(
          StructuredConflictObservation(
            conflictId: '${left.id}:${right.id}:protected-v1',
            firstSourceId: left.id,
            secondSourceId: right.id,
            firstRevision: left.revision,
            secondRevision: right.revision,
            confirmedByCanonicalEngine: true,
            evidence: [
              _evidence(
                event: left,
                eventSection: eventSection,
                overlapStart: overlapStart,
                overlapEnd: overlapEnd,
              ),
              _evidence(
                event: right,
                eventSection: eventSection,
                overlapStart: overlapStart,
                overlapEnd: overlapEnd,
              ),
            ],
          ),
        );
        if (conflicts.length == maximumConflicts) return conflicts;
      }
    }
    return conflicts;
  }

  static DetectionEvidence _evidence({
    required _ProtectedEvent event,
    required EventDomainSection eventSection,
    required DateTime overlapStart,
    required DateTime overlapEnd,
  }) =>
      DetectionEvidence(
        sourceType: DetectionEvidenceSource.confirmedConflictResult,
        domain: LifeContextDomain.event,
        sourceId: event.id,
        revision: event.revision,
        freshness: eventSection.metadata.freshness,
        availability: eventSection.metadata.availability,
        certainty: DetectionEvidenceLevel.confirmedStructured,
        intervalStart: overlapStart,
        intervalEnd: overlapEnd,
        confirmed: true,
      );

  static _ProtectedEvent? _protectedEvent(EventContextItem event) {
    if (event.id.trim().isEmpty) return null;
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
