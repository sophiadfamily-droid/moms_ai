import 'dart:collection';

import 'life_context/life_context_domains.dart';
import 'local_notification_models.dart';

enum ProactiveDetectorType {
  deadline,
  delay,
  conflict,
  potentialOmission,
}

enum ProactiveDetectionReason {
  deadlineApproaching,
  deadlinePassed,
  objectivelyDelayed,
  structuredConflict,
  potentialOmission,
}

enum ProactiveDetectionState {
  candidate,
  eligible,
  scheduled,
  notified,
  resolved,
  suppressed,
  stale,
  expired,
  invalid,
  unsupported,
}

enum DetectionConfidenceLevel { certain, strong, insufficient }

enum DetectionEvidenceLevel { explicit, confirmedStructured, insufficient }

enum DetectionEvidenceSource {
  explicitDeadline,
  explicitPlannedStart,
  explicitPlannedEnd,
  fixedEventInterval,
  protectedPeriod,
  structuredRoutineOccurrence,
  explicitTaskCompletionState,
  dependencyRelationR2,
  consequenceRelationR2,
  currentDomainRevision,
  confirmedConflictResult,
  explicitUserReminder,
}

enum DetectionCoverageKind {
  complete,
  partial,
  stale,
  unavailable,
  unsupported,
  corrupted,
}

enum DetectionSuppressionReason {
  missingRequiredData,
  staleSource,
  unavailableDomain,
  ambiguousTime,
  flexibleWithoutCommitment,
  alreadyResolved,
  duplicate,
  cooldown,
  notificationDisabled,
  permissionMissing,
  conflictingEvidence,
  unsupportedDomain,
  sourceDeleted,
  sourceRevisionChanged,
  accountMismatch,
  technicalLimit,
}

enum DetectionTechnicalSeverity { information, attention, important }

enum DetectionSubjectKind { event, task, routine, explicitReminder }

enum DetectionWarningCode {
  partialCoverage,
  truncatedInput,
  offlineEvidence,
  secondaryReasonsOmitted,
  timezoneUnverified,
}

final class DetectionEvidence {
  const DetectionEvidence({
    required this.sourceType,
    required this.domain,
    required this.sourceId,
    required this.revision,
    required this.freshness,
    required this.availability,
    required this.certainty,
    this.instant,
    this.intervalStart,
    this.intervalEnd,
    this.relationId,
    this.confirmed = false,
  });

  final DetectionEvidenceSource sourceType;
  final LifeContextDomain domain;
  final String sourceId;
  final int revision;
  final LifeContextFreshness freshness;
  final LifeContextAvailability availability;
  final DetectionEvidenceLevel certainty;
  final DateTime? instant;
  final DateTime? intervalStart;
  final DateTime? intervalEnd;
  final String? relationId;
  final bool confirmed;

  factory DetectionEvidence.fromJson(Map<String, Object?> json) {
    const keys = {
      'sourceType',
      'domain',
      'sourceId',
      'revision',
      'freshness',
      'availability',
      'certainty',
      'instant',
      'intervalStart',
      'intervalEnd',
      'relationId',
      'confirmed',
    };
    if (json.keys.toSet().difference(keys).isNotEmpty) {
      throw const FormatException('detection_evidence_invalid');
    }
    T parse<T extends Enum>(List<T> values, Object? raw) =>
        values.where((item) => item.name == raw).single;
    final value = DetectionEvidence(
      sourceType: parse(DetectionEvidenceSource.values, json['sourceType']),
      domain: parse(LifeContextDomain.values, json['domain']),
      sourceId: json['sourceId'] as String,
      revision: json['revision'] as int,
      freshness: parse(LifeContextFreshness.values, json['freshness']),
      availability: parse(LifeContextAvailability.values, json['availability']),
      certainty: parse(DetectionEvidenceLevel.values, json['certainty']),
      instant: json['instant'] == null
          ? null
          : DateTime.parse(json['instant'] as String).toUtc(),
      intervalStart: json['intervalStart'] == null
          ? null
          : DateTime.parse(json['intervalStart'] as String).toUtc(),
      intervalEnd: json['intervalEnd'] == null
          ? null
          : DateTime.parse(json['intervalEnd'] as String).toUtc(),
      relationId: json['relationId'] as String?,
      confirmed: json['confirmed'] as bool,
    );
    value.validate();
    return value;
  }

  void validate() {
    if (sourceId.trim().isEmpty ||
        sourceId.length > 200 ||
        revision < 0 ||
        (intervalStart != null &&
            intervalEnd != null &&
            !intervalEnd!.isAfter(intervalStart!))) {
      throw const FormatException('detection_evidence_invalid');
    }
  }

  Map<String, Object?> toJson() => {
        'sourceType': sourceType.name,
        'domain': domain.name,
        'sourceId': sourceId,
        'revision': revision,
        'freshness': freshness.name,
        'availability': availability.name,
        'certainty': certainty.name,
        if (instant != null) 'instant': instant!.toUtc().toIso8601String(),
        if (intervalStart != null)
          'intervalStart': intervalStart!.toUtc().toIso8601String(),
        if (intervalEnd != null)
          'intervalEnd': intervalEnd!.toUtc().toIso8601String(),
        if (relationId != null) 'relationId': relationId,
        'confirmed': confirmed,
      };
}

final class DetectionCoverageState {
  DetectionCoverageState({
    required this.kind,
    Set<LifeContextDomain> evaluatedDomains = const {},
    Set<LifeContextDomain> unavailableDomains = const {},
    Set<LifeContextDomain> staleDomains = const {},
    required this.numberEvaluated,
    required this.numberTruncated,
    Set<ProactiveDetectorType> evaluableCategories = const {},
    Set<ProactiveDetectorType> nonEvaluableCategories = const {},
    this.nextEvaluationAt,
  })  : evaluatedDomains = UnmodifiableSetView(evaluatedDomains),
        unavailableDomains = UnmodifiableSetView(unavailableDomains),
        staleDomains = UnmodifiableSetView(staleDomains),
        evaluableCategories = UnmodifiableSetView(evaluableCategories),
        nonEvaluableCategories = UnmodifiableSetView(nonEvaluableCategories) {
    if (numberEvaluated < 0 || numberTruncated < 0) {
      throw const FormatException('detection_coverage_invalid');
    }
  }

  final DetectionCoverageKind kind;
  final Set<LifeContextDomain> evaluatedDomains;
  final Set<LifeContextDomain> unavailableDomains;
  final Set<LifeContextDomain> staleDomains;
  final int numberEvaluated;
  final int numberTruncated;
  final Set<ProactiveDetectorType> evaluableCategories;
  final Set<ProactiveDetectorType> nonEvaluableCategories;
  final DateTime? nextEvaluationAt;

  bool get supportsCertainDetection =>
      kind == DetectionCoverageKind.complete ||
      kind == DetectionCoverageKind.partial;
}

final class DetectionSubject {
  DetectionSubject({
    required this.kind,
    required this.domain,
    required this.sourceId,
    required this.revision,
    required this.freshness,
    required this.availability,
    required this.active,
    required this.completed,
    required this.deleted,
    required this.mandatory,
    required this.flexible,
    required List<DetectionEvidence> evidence,
    this.deadline,
    this.plannedStart,
    this.plannedEnd,
    this.priorityRank = 0,
  }) : evidence = UnmodifiableListView(evidence) {
    if (sourceId.trim().isEmpty ||
        revision < 0 ||
        priorityRank < 0 ||
        priorityRank > 100 ||
        evidence.length > 12) {
      throw const FormatException('detection_subject_invalid');
    }
    for (final item in evidence) {
      item.validate();
    }
  }

  final DetectionSubjectKind kind;
  final LifeContextDomain domain;
  final String sourceId;
  final int revision;
  final LifeContextFreshness freshness;
  final LifeContextAvailability availability;
  final bool active;
  final bool completed;
  final bool deleted;
  final bool mandatory;
  final bool flexible;
  final List<DetectionEvidence> evidence;
  final DateTime? deadline;
  final DateTime? plannedStart;
  final DateTime? plannedEnd;
  final int priorityRank;

  bool get isCurrent =>
      freshness == LifeContextFreshness.current &&
      (availability == LifeContextAvailability.available ||
          availability == LifeContextAvailability.empty);
}

final class StructuredConflictObservation {
  StructuredConflictObservation({
    required this.conflictId,
    required this.firstSourceId,
    required this.secondSourceId,
    required this.firstRevision,
    required this.secondRevision,
    required this.confirmedByCanonicalEngine,
    required List<DetectionEvidence> evidence,
    this.resolved = false,
  }) : evidence = UnmodifiableListView(evidence) {
    if (conflictId.trim().isEmpty ||
        firstSourceId == secondSourceId ||
        firstRevision < 0 ||
        secondRevision < 0 ||
        evidence.isEmpty ||
        evidence.length > 8) {
      throw const FormatException('detection_conflict_invalid');
    }
  }

  final String conflictId;
  final String firstSourceId;
  final String secondSourceId;
  final int firstRevision;
  final int secondRevision;
  final bool confirmedByCanonicalEngine;
  final List<DetectionEvidence> evidence;
  final bool resolved;
}

final class ProactiveDetectionSignal {
  static const currentSchemaVersion = 1;

  ProactiveDetectionSignal({
    this.schemaVersion = currentSchemaVersion,
    required this.detectionId,
    required this.accountScopeId,
    required this.detectorType,
    required this.reasonCode,
    required this.state,
    required this.confidenceLevel,
    required this.evidenceLevel,
    required List<DetectionEvidence> evidence,
    required Map<String, int> sourceRevisions,
    required this.detectedAt,
    required this.validFrom,
    required this.validUntil,
    required this.observedAt,
    this.scheduledEvaluationAt,
    this.resolvedAt,
    this.suppressionReason,
    required this.replacementKey,
    required this.incidentFingerprint,
    this.notificationLogicalId,
    required this.interactionDestination,
    required this.policyVersion,
    required this.coverageState,
    Set<DetectionWarningCode> warningCodes = const {},
    Set<ProactiveDetectionReason> secondaryReasons = const {},
    required this.technicalSeverity,
  })  : evidence = UnmodifiableListView(evidence),
        sourceRevisions = UnmodifiableMapView(sourceRevisions),
        warningCodes = UnmodifiableSetView(warningCodes),
        secondaryReasons = UnmodifiableSetView(secondaryReasons) {
    validate();
  }

  final int schemaVersion;
  final String detectionId;
  final String accountScopeId;
  final ProactiveDetectorType detectorType;
  final ProactiveDetectionReason reasonCode;
  final ProactiveDetectionState state;
  final DetectionConfidenceLevel confidenceLevel;
  final DetectionEvidenceLevel evidenceLevel;
  final List<DetectionEvidence> evidence;
  final Map<String, int> sourceRevisions;
  final DateTime detectedAt;
  final DateTime validFrom;
  final DateTime validUntil;
  final DateTime observedAt;
  final DateTime? scheduledEvaluationAt;
  final DateTime? resolvedAt;
  final DetectionSuppressionReason? suppressionReason;
  final String replacementKey;
  final String incidentFingerprint;
  final String? notificationLogicalId;
  final NotificationDestinationType interactionDestination;
  final int policyVersion;
  final DetectionCoverageKind coverageState;
  final Set<DetectionWarningCode> warningCodes;
  final Set<ProactiveDetectionReason> secondaryReasons;
  final DetectionTechnicalSeverity technicalSeverity;

  factory ProactiveDetectionSignal.fromJson(
    Map<String, Object?> json, {
    required String accountScopeId,
  }) {
    const keys = {
      'schemaVersion',
      'detectionId',
      'detectorType',
      'reasonCode',
      'state',
      'confidenceLevel',
      'evidenceLevel',
      'evidence',
      'sourceRevisions',
      'detectedAt',
      'validFrom',
      'validUntil',
      'observedAt',
      'scheduledEvaluationAt',
      'resolvedAt',
      'suppressionReason',
      'replacementKey',
      'incidentFingerprint',
      'notificationLogicalId',
      'interactionDestination',
      'policyVersion',
      'coverageState',
      'warningCodes',
      'secondaryReasons',
      'technicalSeverity',
    };
    if (json.keys.toSet().difference(keys).isNotEmpty ||
        json['schemaVersion'] != currentSchemaVersion) {
      throw const FormatException('proactive_detection_signal_invalid');
    }
    T parse<T extends Enum>(List<T> values, Object? raw) =>
        values.where((item) => item.name == raw).single;
    DateTime time(String key) => DateTime.parse(json[key] as String).toUtc();
    final sourceRevisions = Map<String, Object?>.from(
      json['sourceRevisions'] as Map,
    ).map((key, value) => MapEntry(key, value as int));
    return ProactiveDetectionSignal(
      detectionId: json['detectionId'] as String,
      accountScopeId: accountScopeId,
      detectorType: parse(ProactiveDetectorType.values, json['detectorType']),
      reasonCode: parse(ProactiveDetectionReason.values, json['reasonCode']),
      state: parse(ProactiveDetectionState.values, json['state']),
      confidenceLevel:
          parse(DetectionConfidenceLevel.values, json['confidenceLevel']),
      evidenceLevel:
          parse(DetectionEvidenceLevel.values, json['evidenceLevel']),
      evidence: (json['evidence'] as List)
          .map(
            (item) => DetectionEvidence.fromJson(
              Map<String, Object?>.from(item as Map),
            ),
          )
          .toList(),
      sourceRevisions: sourceRevisions,
      detectedAt: time('detectedAt'),
      validFrom: time('validFrom'),
      validUntil: time('validUntil'),
      observedAt: time('observedAt'),
      scheduledEvaluationAt: json['scheduledEvaluationAt'] == null
          ? null
          : time('scheduledEvaluationAt'),
      resolvedAt: json['resolvedAt'] == null ? null : time('resolvedAt'),
      suppressionReason: json['suppressionReason'] == null
          ? null
          : parse(
              DetectionSuppressionReason.values,
              json['suppressionReason'],
            ),
      replacementKey: json['replacementKey'] as String,
      incidentFingerprint: json['incidentFingerprint'] as String,
      notificationLogicalId: json['notificationLogicalId'] as String?,
      interactionDestination: parse(
        NotificationDestinationType.values,
        json['interactionDestination'],
      ),
      policyVersion: json['policyVersion'] as int,
      coverageState: parse(DetectionCoverageKind.values, json['coverageState']),
      warningCodes: (json['warningCodes'] as List)
          .map(
            (item) => parse(
              DetectionWarningCode.values,
              item,
            ),
          )
          .toSet(),
      secondaryReasons: (json['secondaryReasons'] as List)
          .map(
            (item) => parse(
              ProactiveDetectionReason.values,
              item,
            ),
          )
          .toSet(),
      technicalSeverity: parse(
        DetectionTechnicalSeverity.values,
        json['technicalSeverity'],
      ),
    );
  }

  void validate() {
    if (schemaVersion != currentSchemaVersion ||
        detectionId.trim().isEmpty ||
        accountScopeId.trim().isEmpty ||
        replacementKey.trim().isEmpty ||
        incidentFingerprint.trim().isEmpty ||
        evidence.isEmpty ||
        evidence.length > 12 ||
        sourceRevisions.isEmpty ||
        sourceRevisions.length > 8 ||
        warningCodes.length > 8 ||
        secondaryReasons.length > 4 ||
        policyVersion < 1 ||
        !validUntil.isAfter(validFrom)) {
      throw const FormatException('proactive_detection_signal_invalid');
    }
    for (final item in evidence) {
      item.validate();
    }
  }

  bool get isNotifiable =>
      state == ProactiveDetectionState.eligible &&
      confidenceLevel != DetectionConfidenceLevel.insufficient &&
      evidenceLevel != DetectionEvidenceLevel.insufficient &&
      coverageState != DetectionCoverageKind.stale &&
      coverageState != DetectionCoverageKind.unavailable &&
      coverageState != DetectionCoverageKind.corrupted;

  ProactiveDetectionSignal copyWith({
    ProactiveDetectionState? state,
    DateTime? resolvedAt,
    DetectionSuppressionReason? suppressionReason,
    String? notificationLogicalId,
  }) =>
      ProactiveDetectionSignal(
        detectionId: detectionId,
        accountScopeId: accountScopeId,
        detectorType: detectorType,
        reasonCode: reasonCode,
        state: state ?? this.state,
        confidenceLevel: confidenceLevel,
        evidenceLevel: evidenceLevel,
        evidence: evidence,
        sourceRevisions: sourceRevisions,
        detectedAt: detectedAt,
        validFrom: validFrom,
        validUntil: validUntil,
        observedAt: observedAt,
        scheduledEvaluationAt: scheduledEvaluationAt,
        resolvedAt: resolvedAt ?? this.resolvedAt,
        suppressionReason: suppressionReason ?? this.suppressionReason,
        replacementKey: replacementKey,
        incidentFingerprint: incidentFingerprint,
        notificationLogicalId:
            notificationLogicalId ?? this.notificationLogicalId,
        interactionDestination: interactionDestination,
        policyVersion: policyVersion,
        coverageState: coverageState,
        warningCodes: warningCodes,
        secondaryReasons: secondaryReasons,
        technicalSeverity: technicalSeverity,
      );

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'detectionId': detectionId,
        'detectorType': detectorType.name,
        'reasonCode': reasonCode.name,
        'state': state.name,
        'confidenceLevel': confidenceLevel.name,
        'evidenceLevel': evidenceLevel.name,
        'evidence': evidence.map((item) => item.toJson()).toList(),
        'sourceRevisions': Map.fromEntries(
          sourceRevisions.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key)),
        ),
        'detectedAt': detectedAt.toUtc().toIso8601String(),
        'validFrom': validFrom.toUtc().toIso8601String(),
        'validUntil': validUntil.toUtc().toIso8601String(),
        'observedAt': observedAt.toUtc().toIso8601String(),
        if (scheduledEvaluationAt != null)
          'scheduledEvaluationAt':
              scheduledEvaluationAt!.toUtc().toIso8601String(),
        if (resolvedAt != null)
          'resolvedAt': resolvedAt!.toUtc().toIso8601String(),
        if (suppressionReason != null)
          'suppressionReason': suppressionReason!.name,
        'replacementKey': replacementKey,
        'incidentFingerprint': incidentFingerprint,
        if (notificationLogicalId != null)
          'notificationLogicalId': notificationLogicalId,
        'interactionDestination': interactionDestination.name,
        'policyVersion': policyVersion,
        'coverageState': coverageState.name,
        'warningCodes': warningCodes.map((item) => item.name).toList()..sort(),
        'secondaryReasons': secondaryReasons.map((item) => item.name).toList()
          ..sort(),
        'technicalSeverity': technicalSeverity.name,
      };
}

final class DetectionDecision {
  const DetectionDecision({
    required this.signal,
    required this.suppressionReason,
  });

  final ProactiveDetectionSignal? signal;
  final DetectionSuppressionReason? suppressionReason;
}

final class ProactiveDetectionResult {
  ProactiveDetectionResult({
    required List<ProactiveDetectionSignal> activeSignals,
    required List<ProactiveDetectionSignal> resolvedSignals,
    required this.coverage,
    required this.numberSuppressed,
    required this.evaluatedAt,
  })  : activeSignals = UnmodifiableListView(activeSignals),
        resolvedSignals = UnmodifiableListView(resolvedSignals);

  final List<ProactiveDetectionSignal> activeSignals;
  final List<ProactiveDetectionSignal> resolvedSignals;
  final DetectionCoverageState coverage;
  final int numberSuppressed;
  final DateTime evaluatedAt;
}
