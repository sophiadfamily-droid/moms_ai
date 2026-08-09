import 'dart:collection';

import '../models/life_context/life_context_domains.dart';
import '../models/life_context/life_context_graph.dart';
import '../models/local_notification_models.dart';
import '../models/proactive_detection.dart';

final class ProactiveDetectionPolicy {
  static const currentVersion = 1;

  const ProactiveDetectionPolicy({
    this.version = currentVersion,
    this.maxSubjectsPerDomain = 100,
    this.analysisHorizon = const Duration(days: 14),
    this.minimumScheduleLead = const Duration(minutes: 5),
    this.delayGracePeriod = const Duration(minutes: 15),
    this.cooldown = const Duration(hours: 12),
    this.maxNotificationsPerPass = 4,
    this.maxNotificationsPerCategory = 2,
    this.maxActiveSignalsPerAccount = 32,
    this.signalValidity = const Duration(days: 2),
    this.maxSecondaryReasons = 3,
    this.maxReevaluationsPerPass = 128,
    this.clockMargin = const Duration(minutes: 1),
  });

  final int version;
  final int maxSubjectsPerDomain;
  final Duration analysisHorizon;
  final Duration minimumScheduleLead;
  final Duration delayGracePeriod;
  final Duration cooldown;
  final int maxNotificationsPerPass;
  final int maxNotificationsPerCategory;
  final int maxActiveSignalsPerAccount;
  final Duration signalValidity;
  final int maxSecondaryReasons;
  final int maxReevaluationsPerPass;
  final Duration clockMargin;

  void validate() {
    if (version != currentVersion ||
        maxSubjectsPerDomain < 1 ||
        maxSubjectsPerDomain > 500 ||
        analysisHorizon <= Duration.zero ||
        minimumScheduleLead < Duration.zero ||
        delayGracePeriod < Duration.zero ||
        cooldown < Duration.zero ||
        maxNotificationsPerPass < 1 ||
        maxNotificationsPerCategory < 1 ||
        maxActiveSignalsPerAccount < maxNotificationsPerPass ||
        maxSecondaryReasons < 0 ||
        maxSecondaryReasons > 8 ||
        maxReevaluationsPerPass < 1 ||
        maxReevaluationsPerPass > 500 ||
        signalValidity <= Duration.zero) {
      throw const FormatException('proactive_detection_policy_invalid');
    }
  }
}

final class ProactiveDetectionInput {
  ProactiveDetectionInput({
    required this.accountScopeId,
    required List<DetectionSubject> subjects,
    required List<StructuredConflictObservation> conflicts,
    required List<LifeContextDependency> dependencies,
    required this.coverage,
    required List<ProactiveDetectionSignal> existingSignals,
    required this.observedAt,
    required this.timezoneId,
  })  : subjects = UnmodifiableListView(subjects),
        conflicts = UnmodifiableListView(conflicts),
        dependencies = UnmodifiableListView(dependencies),
        existingSignals = UnmodifiableListView(existingSignals) {
    if (accountScopeId.trim().isEmpty ||
        timezoneId.trim().isEmpty ||
        subjects.length > 1000 ||
        conflicts.length > 200 ||
        dependencies.length > 500) {
      throw const FormatException('proactive_detection_input_invalid');
    }
  }

  final String accountScopeId;
  final List<DetectionSubject> subjects;
  final List<StructuredConflictObservation> conflicts;
  final List<LifeContextDependency> dependencies;
  final DetectionCoverageState coverage;
  final List<ProactiveDetectionSignal> existingSignals;
  final DateTime observedAt;
  final String timezoneId;
}

abstract interface class ProactiveDetector {
  ProactiveDetectorType get type;

  List<DetectionDecision> detect({
    required ProactiveDetectionInput input,
    required ProactiveDetectionPolicy policy,
    required DateTime now,
  });
}

final class DeadlineDetector implements ProactiveDetector {
  const DeadlineDetector();

  @override
  ProactiveDetectorType get type => ProactiveDetectorType.deadline;

  @override
  List<DetectionDecision> detect({
    required ProactiveDetectionInput input,
    required ProactiveDetectionPolicy policy,
    required DateTime now,
  }) {
    if (!input.coverage.evaluableCategories.contains(type)) return const [];
    final decisions = <DetectionDecision>[];
    for (final subject in input.subjects) {
      if (subject.deadline == null) continue;
      if (!subject.isCurrent) {
        decisions.add(DetectionDecision(
          signal: null,
          suppressionReason: _sourceSuppression(subject),
        ));
        continue;
      }
      if (!subject.active || subject.completed || subject.deleted) {
        decisions.add(const DetectionDecision(
          signal: null,
          suppressionReason: DetectionSuppressionReason.alreadyResolved,
        ));
        continue;
      }
      final deadline = subject.deadline!.toUtc();
      if (deadline.isAfter(now.add(policy.analysisHorizon)) ||
          deadline.isBefore(now.subtract(policy.analysisHorizon))) {
        continue;
      }
      final reason = deadline.isAfter(now)
          ? ProactiveDetectionReason.deadlineApproaching
          : ProactiveDetectionReason.deadlinePassed;
      decisions.add(DetectionDecision(
        signal: _signal(
          input: input,
          subject: subject,
          detector: type,
          reason: reason,
          evidenceSource: DetectionEvidenceSource.explicitDeadline,
          instant: deadline,
          now: now,
          policy: policy,
          confidence: DetectionConfidenceLevel.certain,
        ),
        suppressionReason: null,
      ));
    }
    return decisions;
  }
}

final class DelayDetector implements ProactiveDetector {
  const DelayDetector();

  @override
  ProactiveDetectorType get type => ProactiveDetectorType.delay;

  @override
  List<DetectionDecision> detect({
    required ProactiveDetectionInput input,
    required ProactiveDetectionPolicy policy,
    required DateTime now,
  }) {
    if (!input.coverage.evaluableCategories.contains(type)) return const [];
    final decisions = <DetectionDecision>[];
    for (final subject in input.subjects) {
      final plannedEnd = subject.plannedEnd;
      final plannedStart = subject.plannedStart;
      if (plannedEnd == null && plannedStart == null) continue;
      if (!subject.isCurrent) {
        decisions.add(DetectionDecision(
          signal: null,
          suppressionReason: _sourceSuppression(subject),
        ));
        continue;
      }
      if (!subject.active || subject.completed || subject.deleted) continue;
      if (subject.flexible || !subject.mandatory) {
        decisions.add(const DetectionDecision(
          signal: null,
          suppressionReason:
              DetectionSuppressionReason.flexibleWithoutCommitment,
        ));
        continue;
      }
      final reference = (plannedEnd ?? plannedStart)!.toUtc();
      if (reference.isBefore(now.subtract(policy.analysisHorizon))) continue;
      if (now.isBefore(reference.add(policy.delayGracePeriod))) continue;
      decisions.add(DetectionDecision(
        signal: _signal(
          input: input,
          subject: subject,
          detector: type,
          reason: ProactiveDetectionReason.objectivelyDelayed,
          evidenceSource: plannedEnd == null
              ? DetectionEvidenceSource.explicitPlannedStart
              : DetectionEvidenceSource.explicitPlannedEnd,
          instant: reference,
          now: now,
          policy: policy,
          confidence: DetectionConfidenceLevel.strong,
        ),
        suppressionReason: null,
      ));
    }
    return decisions;
  }
}

/// Consumes only conflicts confirmed by the existing canonical planning
/// boundary. It deliberately performs no overlap calculation of its own.
final class ConflictDetector implements ProactiveDetector {
  const ConflictDetector();

  @override
  ProactiveDetectorType get type => ProactiveDetectorType.conflict;

  @override
  List<DetectionDecision> detect({
    required ProactiveDetectionInput input,
    required ProactiveDetectionPolicy policy,
    required DateTime now,
  }) {
    if (!input.coverage.evaluableCategories.contains(type)) return const [];
    return input.conflicts.map((conflict) {
      if (conflict.resolved) {
        return const DetectionDecision(
          signal: null,
          suppressionReason: DetectionSuppressionReason.alreadyResolved,
        );
      }
      if (!conflict.confirmedByCanonicalEngine ||
          conflict.evidence.any(
            (item) =>
                item.freshness != LifeContextFreshness.current ||
                item.availability != LifeContextAvailability.available,
          )) {
        final unavailable = conflict.evidence.any(
          (item) =>
              item.availability == LifeContextAvailability.unavailable ||
              item.availability == LifeContextAvailability.corrupted ||
              item.availability == LifeContextAvailability.accountMismatch,
        );
        return DetectionDecision(
          signal: null,
          suppressionReason: unavailable
              ? DetectionSuppressionReason.unavailableDomain
              : DetectionSuppressionReason.staleSource,
        );
      }
      final intervals = conflict.evidence
          .where(
            (item) => item.intervalStart != null && item.intervalEnd != null,
          )
          .toList(growable: false);
      if (intervals.isNotEmpty &&
          intervals.every(
            (item) =>
                !item.intervalEnd!.toUtc().isAfter(now) ||
                item.intervalStart!.toUtc().isAfter(
                      now.add(policy.analysisHorizon),
                    ),
          )) {
        return const DetectionDecision(
          signal: null,
          suppressionReason: DetectionSuppressionReason.alreadyResolved,
        );
      }
      final sourceIds = [
        conflict.firstSourceId,
        conflict.secondSourceId,
      ]..sort();
      final fingerprint = _stableFingerprint(
        'conflict|${sourceIds.join('|')}|${conflict.firstRevision}|'
        '${conflict.secondRevision}',
      );
      return DetectionDecision(
        signal: ProactiveDetectionSignal(
          detectionId: 'det-$fingerprint',
          accountScopeId: input.accountScopeId,
          detectorType: type,
          reasonCode: ProactiveDetectionReason.structuredConflict,
          state: ProactiveDetectionState.eligible,
          confidenceLevel: DetectionConfidenceLevel.certain,
          evidenceLevel: DetectionEvidenceLevel.confirmedStructured,
          evidence: conflict.evidence,
          sourceRevisions: {
            conflict.firstSourceId: conflict.firstRevision,
            conflict.secondSourceId: conflict.secondRevision,
          },
          detectedAt: now,
          validFrom: now,
          validUntil: now.add(policy.signalValidity),
          observedAt: input.observedAt,
          replacementKey: 'detection:$fingerprint',
          incidentFingerprint: fingerprint,
          interactionDestination: NotificationDestinationType.home,
          policyVersion: policy.version,
          coverageState: input.coverage.kind,
          technicalSeverity: DetectionTechnicalSeverity.important,
        ),
        suppressionReason: null,
      );
    }).toList(growable: false);
  }
}

final class PotentialOmissionDetector implements ProactiveDetector {
  const PotentialOmissionDetector();

  @override
  ProactiveDetectorType get type => ProactiveDetectorType.potentialOmission;

  @override
  List<DetectionDecision> detect({
    required ProactiveDetectionInput input,
    required ProactiveDetectionPolicy policy,
    required DateTime now,
  }) {
    if (!input.coverage.evaluableCategories.contains(type)) return const [];
    final byNodeId = <String, DetectionSubject>{
      for (final subject in input.subjects)
        '${subject.domain.name}:${subject.kind.name}:${subject.sourceId}':
            subject,
    };
    final results = <DetectionDecision>[];
    for (final dependency in input.dependencies) {
      if (dependency.provenance.confirmation !=
              LifeContextConfirmation.confirmed ||
          dependency.provenance.ruleId !=
              LifeContextRegisteredRuleIds.explicitDependency ||
          dependency.type != LifeContextDependencyType.requires &&
              dependency.type != LifeContextDependencyType.blocks &&
              dependency.type !=
                  LifeContextDependencyType.explicitUserDependency) {
        continue;
      }
      final prerequisite = byNodeId[dependency.prerequisiteNodeId];
      final dependent = byNodeId[dependency.dependentNodeId];
      if (prerequisite == null || dependent == null) continue;
      if (!prerequisite.isCurrent ||
          !dependent.isCurrent ||
          prerequisite.completed ||
          prerequisite.deleted ||
          prerequisite.deadline == null ||
          !prerequisite.deadline!.toUtc().isBefore(now) ||
          dependent.plannedStart == null ||
          !dependent.plannedStart!.toUtc().isAfter(now) ||
          dependent.plannedStart!.toUtc().isAfter(
                now.add(policy.analysisHorizon),
              ) ||
          prerequisite.deadline!.toUtc().isBefore(
                now.subtract(policy.analysisHorizon),
              )) {
        continue;
      }
      final evidence = DetectionEvidence(
        sourceType: DetectionEvidenceSource.dependencyRelationR2,
        domain: prerequisite.domain,
        sourceId: prerequisite.sourceId,
        revision: prerequisite.revision,
        freshness: prerequisite.freshness,
        availability: prerequisite.availability,
        certainty: DetectionEvidenceLevel.confirmedStructured,
        instant: prerequisite.deadline,
        relationId: dependency.id,
        confirmed: true,
      );
      results.add(DetectionDecision(
        signal: _signal(
          input: input,
          subject: prerequisite,
          detector: type,
          reason: ProactiveDetectionReason.potentialOmission,
          evidenceSource: DetectionEvidenceSource.dependencyRelationR2,
          instant: prerequisite.deadline!,
          now: now,
          policy: policy,
          confidence: DetectionConfidenceLevel.strong,
          extraEvidence: [evidence],
        ),
        suppressionReason: null,
      ));
    }
    for (final subject in input.subjects.where(
      (item) =>
          item.kind == DetectionSubjectKind.explicitReminder &&
          item.deadline != null &&
          item.active &&
          !item.completed &&
          item.isCurrent,
    )) {
      if (subject.deadline!.toUtc().isAfter(now)) continue;
      results.add(DetectionDecision(
        signal: _signal(
          input: input,
          subject: subject,
          detector: type,
          reason: ProactiveDetectionReason.potentialOmission,
          evidenceSource: DetectionEvidenceSource.explicitUserReminder,
          instant: subject.deadline!,
          now: now,
          policy: policy,
          confidence: DetectionConfidenceLevel.certain,
        ),
        suppressionReason: null,
      ));
    }
    return results;
  }
}

final class ProactiveDetectionEngine {
  const ProactiveDetectionEngine({
    this.deadlineDetector = const DeadlineDetector(),
    this.delayDetector = const DelayDetector(),
    this.conflictDetector = const ConflictDetector(),
    this.potentialOmissionDetector = const PotentialOmissionDetector(),
  });

  final DeadlineDetector deadlineDetector;
  final DelayDetector delayDetector;
  final ConflictDetector conflictDetector;
  final PotentialOmissionDetector potentialOmissionDetector;

  ProactiveDetectionResult evaluate({
    required ProactiveDetectionInput input,
    required ProactiveDetectionPolicy policy,
    required DateTime now,
  }) {
    policy.validate();
    final current = now.toUtc();
    if (input.existingSignals.any(
      (signal) => signal.accountScopeId != input.accountScopeId,
    )) {
      throw const FormatException('detection_account_mismatch');
    }
    final boundedSubjects = <DetectionSubject>[];
    var truncated = 0;
    for (final domain in LifeContextDomain.values) {
      final matches = input.subjects
          .where((item) => item.domain == domain)
          .toList()
        ..sort((a, b) => a.sourceId.compareTo(b.sourceId));
      boundedSubjects.addAll(matches.take(policy.maxSubjectsPerDomain));
      truncated += matches.length > policy.maxSubjectsPerDomain
          ? matches.length - policy.maxSubjectsPerDomain
          : 0;
    }
    final boundedInput = ProactiveDetectionInput(
      accountScopeId: input.accountScopeId,
      subjects: boundedSubjects,
      conflicts: input.conflicts.take(policy.maxReevaluationsPerPass).toList(),
      dependencies:
          input.dependencies.take(policy.maxReevaluationsPerPass).toList(),
      coverage: input.coverage,
      existingSignals: input.existingSignals,
      observedAt: input.observedAt,
      timezoneId: input.timezoneId,
    );
    final decisions = <DetectionDecision>[
      ...deadlineDetector.detect(
          input: boundedInput, policy: policy, now: current),
      ...delayDetector.detect(
          input: boundedInput, policy: policy, now: current),
      ...conflictDetector.detect(
          input: boundedInput, policy: policy, now: current),
      ...potentialOmissionDetector.detect(
          input: boundedInput, policy: policy, now: current),
    ];
    var suppressed = decisions.where((item) => item.signal == null).length;
    final byFingerprint = <String, List<ProactiveDetectionSignal>>{};
    for (final signal in decisions
        .map((item) => item.signal)
        .whereType<ProactiveDetectionSignal>()) {
      byFingerprint
          .putIfAbsent(signal.incidentFingerprint, () => [])
          .add(signal);
    }
    final selected = <ProactiveDetectionSignal>[];
    for (final collision in byFingerprint.values) {
      collision.sort(_compareSignals);
      final primary = collision.first;
      final secondary = collision
          .skip(1)
          .map((item) => item.reasonCode)
          .toSet()
          .take(policy.maxSecondaryReasons)
          .toSet();
      selected.add(_withSecondary(primary, secondary));
      suppressed += collision.length - 1;
    }
    final existingByFingerprint = {
      for (final signal in input.existingSignals)
        signal.incidentFingerprint: signal,
    };
    final eligible = <ProactiveDetectionSignal>[];
    final categoryCounts = <ProactiveDetectorType, int>{};
    for (final signal in selected..sort(_compareSignals)) {
      final previous = existingByFingerprint[signal.incidentFingerprint];
      if (previous != null &&
          previous.state == ProactiveDetectionState.resolved &&
          signal.detectorType != ProactiveDetectorType.conflict &&
          current.difference(previous.resolvedAt ?? previous.detectedAt) <
              policy.cooldown) {
        suppressed++;
        continue;
      }
      final count = categoryCounts[signal.detectorType] ?? 0;
      if (count >= policy.maxNotificationsPerCategory ||
          eligible.length >= policy.maxNotificationsPerPass ||
          eligible.length >= policy.maxActiveSignalsPerAccount) {
        suppressed++;
        continue;
      }
      categoryCounts[signal.detectorType] = count + 1;
      eligible.add(signal);
    }
    final activeFingerprints =
        eligible.map((item) => item.incidentFingerprint).toSet();
    final resolved = input.existingSignals
        .where(
          (item) =>
              item.state != ProactiveDetectionState.resolved &&
              _canResolveFromCoverage(item, input.coverage) &&
              !activeFingerprints.contains(item.incidentFingerprint),
        )
        .map(
          (item) => item.copyWith(
            state: ProactiveDetectionState.resolved,
            resolvedAt: current,
            suppressionReason: DetectionSuppressionReason.alreadyResolved,
          ),
        )
        .toList(growable: false);
    final coverage = DetectionCoverageState(
      kind: input.coverage.kind,
      evaluatedDomains: input.coverage.evaluatedDomains,
      unavailableDomains: input.coverage.unavailableDomains,
      staleDomains: input.coverage.staleDomains,
      numberEvaluated: boundedSubjects.length,
      numberTruncated: input.coverage.numberTruncated + truncated,
      evaluableCategories: input.coverage.evaluableCategories,
      nonEvaluableCategories: input.coverage.nonEvaluableCategories,
      nextEvaluationAt: input.coverage.nextEvaluationAt,
    );
    return ProactiveDetectionResult(
      activeSignals: eligible,
      resolvedSignals: resolved,
      coverage: coverage,
      numberSuppressed: suppressed,
      evaluatedAt: current,
    );
  }

  static int _compareSignals(
    ProactiveDetectionSignal left,
    ProactiveDetectionSignal right,
  ) {
    final severity =
        right.technicalSeverity.index.compareTo(left.technicalSeverity.index);
    if (severity != 0) return severity;
    final priority = _detectorPriority(left.detectorType)
        .compareTo(_detectorPriority(right.detectorType));
    if (priority != 0) return priority;
    return left.incidentFingerprint.compareTo(right.incidentFingerprint);
  }

  static int _detectorPriority(ProactiveDetectorType type) => switch (type) {
        ProactiveDetectorType.conflict => 0,
        ProactiveDetectorType.deadline => 1,
        ProactiveDetectorType.delay => 2,
        ProactiveDetectorType.potentialOmission => 3,
      };

  static bool _canResolveFromCoverage(
    ProactiveDetectionSignal signal,
    DetectionCoverageState coverage,
  ) {
    if (!coverage.evaluableCategories.contains(signal.detectorType)) {
      return false;
    }
    final evidenceDomains = signal.evidence.map((item) => item.domain).toSet();
    return evidenceDomains.intersection(coverage.unavailableDomains).isEmpty &&
        evidenceDomains.intersection(coverage.staleDomains).isEmpty;
  }
}

ProactiveDetectionSignal _signal({
  required ProactiveDetectionInput input,
  required DetectionSubject subject,
  required ProactiveDetectorType detector,
  required ProactiveDetectionReason reason,
  required DetectionEvidenceSource evidenceSource,
  required DateTime instant,
  required DateTime now,
  required ProactiveDetectionPolicy policy,
  required DetectionConfidenceLevel confidence,
  List<DetectionEvidence> extraEvidence = const [],
}) {
  final fingerprint = _stableFingerprint(
    '${subject.domain.name}|${subject.sourceId}|${subject.revision}',
  );
  final matching = subject.evidence
      .where((item) => item.sourceType == evidenceSource)
      .toList(growable: false);
  final evidence = [
    ...matching,
    ...extraEvidence,
  ];
  if (evidence.isEmpty) {
    evidence.add(DetectionEvidence(
      sourceType: evidenceSource,
      domain: subject.domain,
      sourceId: subject.sourceId,
      revision: subject.revision,
      freshness: subject.freshness,
      availability: subject.availability,
      certainty: DetectionEvidenceLevel.explicit,
      instant: instant,
      confirmed: true,
    ));
  }
  return ProactiveDetectionSignal(
    detectionId: 'det-$fingerprint-${reason.name}',
    accountScopeId: input.accountScopeId,
    detectorType: detector,
    reasonCode: reason,
    state: ProactiveDetectionState.eligible,
    confidenceLevel: confidence,
    evidenceLevel: evidence
        .map((item) => item.certainty)
        .reduce((a, b) => a.index < b.index ? a : b),
    evidence: evidence,
    sourceRevisions: {subject.sourceId: subject.revision},
    detectedAt: now,
    validFrom: now,
    validUntil: now.add(policy.signalValidity),
    observedAt: input.observedAt,
    scheduledEvaluationAt: instant.isAfter(now) ? instant : null,
    replacementKey: 'detection:$fingerprint',
    incidentFingerprint: fingerprint,
    interactionDestination: subject.domain == LifeContextDomain.task
        ? NotificationDestinationType.home
        : NotificationDestinationType.home,
    policyVersion: policy.version,
    coverageState: input.coverage.kind,
    technicalSeverity: reason == ProactiveDetectionReason.structuredConflict ||
            reason == ProactiveDetectionReason.deadlinePassed
        ? DetectionTechnicalSeverity.important
        : DetectionTechnicalSeverity.attention,
  );
}

ProactiveDetectionSignal _withSecondary(
  ProactiveDetectionSignal source,
  Set<ProactiveDetectionReason> secondary,
) =>
    ProactiveDetectionSignal(
      detectionId: source.detectionId,
      accountScopeId: source.accountScopeId,
      detectorType: source.detectorType,
      reasonCode: source.reasonCode,
      state: source.state,
      confidenceLevel: source.confidenceLevel,
      evidenceLevel: source.evidenceLevel,
      evidence: source.evidence,
      sourceRevisions: source.sourceRevisions,
      detectedAt: source.detectedAt,
      validFrom: source.validFrom,
      validUntil: source.validUntil,
      observedAt: source.observedAt,
      scheduledEvaluationAt: source.scheduledEvaluationAt,
      replacementKey: source.replacementKey,
      incidentFingerprint: source.incidentFingerprint,
      interactionDestination: source.interactionDestination,
      policyVersion: source.policyVersion,
      coverageState: source.coverageState,
      warningCodes: source.warningCodes,
      secondaryReasons: secondary,
      technicalSeverity: source.technicalSeverity,
    );

String _stableFingerprint(String input) {
  var hash = 0x811c9dc5;
  for (final unit in input.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

DetectionSuppressionReason _sourceSuppression(DetectionSubject subject) =>
    switch (subject.availability) {
      LifeContextAvailability.unavailable ||
      LifeContextAvailability.corrupted ||
      LifeContextAvailability.accountMismatch =>
        DetectionSuppressionReason.unavailableDomain,
      LifeContextAvailability.unsupported =>
        DetectionSuppressionReason.unsupportedDomain,
      _ => DetectionSuppressionReason.staleSource,
    };
