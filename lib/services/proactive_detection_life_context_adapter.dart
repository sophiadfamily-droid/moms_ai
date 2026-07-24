import '../models/life_context/life_context_domains.dart';
import '../models/life_context/life_context_graph.dart';
import '../models/life_context/life_context_snapshot.dart';
import '../models/proactive_detection.dart';
import 'proactive_detection_engine.dart';
import 'package:timezone/timezone.dart' as tz;

/// Read-only N.2 adapter. It consumes canonical LC.1/LC.2 outputs and does not
/// read repositories or reinterpret text.
final class ProactiveDetectionLifeContextAdapter {
  const ProactiveDetectionLifeContextAdapter();

  ProactiveDetectionInput adapt({
    required LifeContextSnapshot snapshot,
    required LifeContextGraph graph,
    required List<StructuredConflictObservation> confirmedConflicts,
    bool conflictSourceAvailable = true,
    required List<ProactiveDetectionSignal> existingSignals,
    required String timezoneId,
  }) {
    snapshot.validateCanonical();
    graph.validate();
    if (graph.accountScopeId != snapshot.accountScopeId ||
        graph.snapshotId != snapshot.snapshotId) {
      throw const FormatException('detection_life_context_mismatch');
    }
    final subjects = <DetectionSubject>[];
    final taskSection = snapshot.taskDomain!;
    for (final task in taskSection.tasks) {
      final deadline = _deadline(task.dueDate, timezoneId);
      subjects.add(DetectionSubject(
        kind: DetectionSubjectKind.task,
        domain: LifeContextDomain.task,
        sourceId: task.id,
        revision: taskSection.metadata.revision ?? 0,
        freshness: taskSection.metadata.freshness,
        availability: taskSection.metadata.availability,
        active: !task.isCompleted,
        completed: task.isCompleted,
        deleted: false,
        mandatory: false,
        flexible: true,
        evidence: [
          DetectionEvidence(
            sourceType: DetectionEvidenceSource.explicitTaskCompletionState,
            domain: LifeContextDomain.task,
            sourceId: task.id,
            revision: taskSection.metadata.revision ?? 0,
            freshness: taskSection.metadata.freshness,
            availability: taskSection.metadata.availability,
            certainty: DetectionEvidenceLevel.explicit,
            confirmed: true,
          ),
          if (deadline != null)
            DetectionEvidence(
              sourceType: DetectionEvidenceSource.explicitDeadline,
              domain: LifeContextDomain.task,
              sourceId: task.id,
              revision: taskSection.metadata.revision ?? 0,
              freshness: taskSection.metadata.freshness,
              availability: taskSection.metadata.availability,
              certainty: DetectionEvidenceLevel.explicit,
              instant: deadline,
              confirmed: true,
            ),
        ],
        deadline: deadline,
      ));
    }
    final eventSection = snapshot.eventDomain!;
    for (final event in eventSection.events) {
      final start = DateTime.tryParse(event.startDateTimeIso)?.toUtc();
      final end = DateTime.tryParse(event.endDateTimeIso)?.toUtc();
      subjects.add(DetectionSubject(
        kind: DetectionSubjectKind.event,
        domain: LifeContextDomain.event,
        sourceId: event.id,
        revision: event.revision,
        freshness: eventSection.metadata.freshness,
        availability: eventSection.metadata.availability,
        active: true,
        completed: false,
        deleted: false,
        // An Event ending in the past is not evidence that a preparation was
        // left unfinished. Delay requires a separate explicit completion
        // contract, which Event does not currently expose.
        mandatory: false,
        flexible: false,
        evidence: [
          if (start != null && end != null)
            DetectionEvidence(
              sourceType: DetectionEvidenceSource.fixedEventInterval,
              domain: LifeContextDomain.event,
              sourceId: event.id,
              revision: event.revision,
              freshness: eventSection.metadata.freshness,
              availability: eventSection.metadata.availability,
              certainty: DetectionEvidenceLevel.explicit,
              intervalStart: start,
              intervalEnd: end,
              confirmed: true,
            ),
        ],
        plannedStart: start,
        plannedEnd: end,
      ));
    }
    final metadata = [
      snapshot.eventDomain!.metadata,
      snapshot.taskDomain!.metadata,
      snapshot.routineDomain!.metadata,
    ];
    final stale = metadata
        .where((item) => item.freshness != LifeContextFreshness.current)
        .map((item) => item.domain)
        .toSet();
    final unavailable = metadata
        .where(
          (item) =>
              item.availability == LifeContextAvailability.unavailable ||
              item.availability == LifeContextAvailability.corrupted ||
              item.availability == LifeContextAvailability.accountMismatch,
        )
        .map((item) => item.domain)
        .toSet();
    if (!conflictSourceAvailable) {
      unavailable.add(LifeContextDomain.event);
    }
    final corrupted = metadata.any(
      (item) => item.availability == LifeContextAvailability.corrupted,
    );
    final kind = switch (snapshot.globalState!) {
      _ when corrupted => DetectionCoverageKind.corrupted,
      LifeContextGlobalState.complete
          when stale.isEmpty && unavailable.isEmpty =>
        DetectionCoverageKind.complete,
      LifeContextGlobalState.unavailable => DetectionCoverageKind.unavailable,
      _ when unavailable.isNotEmpty => DetectionCoverageKind.partial,
      _ when stale.length == metadata.length => DetectionCoverageKind.stale,
      _ when stale.isNotEmpty => DetectionCoverageKind.partial,
      _ => DetectionCoverageKind.partial,
    };
    final evaluable = <ProactiveDetectorType>{
      if (!stale.contains(LifeContextDomain.task) &&
          !unavailable.contains(LifeContextDomain.task))
        ProactiveDetectorType.deadline,
      if (!unavailable.contains(LifeContextDomain.event))
        ProactiveDetectorType.conflict,
      if (graph.dependencies.isNotEmpty &&
          !stale.contains(LifeContextDomain.task))
        ProactiveDetectorType.potentialOmission,
    };
    return ProactiveDetectionInput(
      accountScopeId: snapshot.accountScopeId!,
      subjects: subjects,
      conflicts: confirmedConflicts,
      dependencies: graph.dependencies,
      coverage: DetectionCoverageState(
        kind: kind,
        evaluatedDomains: metadata.map((item) => item.domain).toSet(),
        unavailableDomains: unavailable,
        staleDomains: stale,
        numberEvaluated: subjects.length,
        numberTruncated: 0,
        evaluableCategories: evaluable,
        nonEvaluableCategories:
            ProactiveDetectorType.values.toSet().difference(evaluable),
      ),
      existingSignals: existingSignals,
      observedAt: snapshot.generatedAt,
      timezoneId: timezoneId,
    );
  }

  static DateTime? _deadline(String? value, String timezoneId) {
    if (value == null || value.trim().isEmpty) return null;
    final raw = value.trim();
    final dateOnly = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw);
    if (!dateOnly) return DateTime.tryParse(raw)?.toUtc();
    try {
      final parts = raw.split('-').map(int.parse).toList();
      final local = tz.TZDateTime(
        tz.getLocation(timezoneId),
        parts[0],
        parts[1],
        parts[2],
        23,
        59,
      );
      return local.toUtc();
    } on Object {
      return null;
    }
  }
}
