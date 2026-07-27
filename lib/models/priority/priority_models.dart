import 'dart:collection';

import '../life_context/life_context_graph.dart';

enum PriorityCandidateType {
  task,
  eventCommitment,
  eventPreparation,
  routineOccurrence,
  constraint,
  otherStructuredAction,
}

enum PrioritySourceDomain { task, event, routine, constraint }

enum PriorityCandidateStatus {
  active,
  completed,
  cancelled,
  expired,
  invalid,
  historical,
  future,
}

enum PriorityFlexibility { fixed, low, flexible, veryFlexible, unknown }

enum PriorityFreshness { current, stale, unknown }

enum PriorityConsequenceType {
  healthSafety,
  legalAdministrative,
  financial,
  otherPersonCommitment,
  work,
  essentialLogistics,
  comfortPreference,
  unknown,
}

enum PriorityConsequenceLevel { low, moderate, high, critical, unknown }

enum PriorityCategory {
  health,
  administrative,
  financial,
  work,
  logistics,
  personal,
  other,
  unknown,
}

enum PriorityImpactType {
  blocks,
  directDependent,
  responsibility,
  technicalConsequence,
}

enum PriorityDimension {
  urgency,
  importance,
  deadlinePressure,
  effort,
  flexibility,
  directImpact,
  dataQuality,
}

enum PriorityMissingData {
  deadline,
  effort,
  importance,
  flexibility,
  directImpact,
  consequence,
  freshness,
}

enum PriorityConfidence { complete, partial, stronglyUncertain, notCalculable }

enum PriorityCalculationStatus {
  scored,
  partiallyScored,
  notScorable,
  invalidCandidate,
  staleSource,
  unsupportedType,
  accountMismatch,
}

enum PriorityRankingWarning {
  partialScores,
  staleSources,
  excludedCandidates,
  truncated,
}

final class PriorityException implements Exception {
  const PriorityException(this.code);

  final String code;

  @override
  String toString() => 'PriorityException($code)';
}

final class PriorityProvenance {
  const PriorityProvenance({
    required this.sourceSnapshotId,
    required this.sourceItemId,
    required this.sourceKind,
    this.ruleId,
  });

  final String sourceSnapshotId;
  final String sourceItemId;
  final String sourceKind;
  final String? ruleId;

  void validate() {
    if (sourceSnapshotId.trim().isEmpty ||
        sourceItemId.trim().isEmpty ||
        sourceKind.trim().isEmpty) {
      throw const PriorityException('invalid_priority_provenance');
    }
  }

  Map<String, Object?> toJson() => {
        'sourceSnapshotId': sourceSnapshotId,
        'sourceItemId': sourceItemId,
        'sourceKind': sourceKind,
        if (ruleId != null) 'ruleId': ruleId,
      };
}

final class PriorityDirectImpact {
  const PriorityDirectImpact({
    required this.id,
    required this.type,
    required this.depth,
    required this.confirmation,
    required this.provenance,
  });

  final String id;
  final PriorityImpactType type;
  final int depth;
  final LifeContextConfirmation confirmation;
  final PriorityProvenance provenance;

  void validate() {
    if (id.trim().isEmpty || depth < 1) {
      throw const PriorityException('invalid_priority_impact');
    }
    provenance.validate();
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'type': type.name,
        'depth': depth,
        'confirmation': confirmation.name,
        'provenance': provenance.toJson(),
      };
}

final class PriorityCandidate {
  static const int currentSchemaVersion = 1;

  PriorityCandidate({
    this.schemaVersion = currentSchemaVersion,
    required this.id,
    required this.accountScopeId,
    required this.sourceDomain,
    required this.sourceId,
    required this.type,
    required this.status,
    required this.confirmation,
    required this.freshness,
    required this.provenance,
    this.deadline,
    this.temporalStart,
    this.createdAt,
    this.effortMinutes,
    this.travelGoMinutes,
    this.marginMinutes,
    this.flexibility = PriorityFlexibility.unknown,
    this.explicitImportance,
    this.explicitUrgency,
    this.consequenceType = PriorityConsequenceType.unknown,
    this.consequenceLevel = PriorityConsequenceLevel.unknown,
    this.category = PriorityCategory.unknown,
    this.subjectEntityId,
    this.sourceRevision,
    this.syncStatus = 'unknown',
    List<PriorityDirectImpact> directImpacts = const [],
  }) : directImpacts = UnmodifiableListView(
          List<PriorityDirectImpact>.of(directImpacts)
            ..sort((a, b) => a.id.compareTo(b.id)),
        ) {
    validate();
  }

  final int schemaVersion;
  final String id;
  final String accountScopeId;
  final PrioritySourceDomain sourceDomain;
  final String sourceId;
  final PriorityCandidateType type;
  final PriorityCandidateStatus status;
  final DateTime? deadline;
  final DateTime? temporalStart;
  final DateTime? createdAt;
  final int? effortMinutes;
  final int? travelGoMinutes;
  final int? marginMinutes;
  final PriorityFlexibility flexibility;
  final double? explicitImportance;
  final double? explicitUrgency;
  final PriorityConsequenceType consequenceType;
  final PriorityConsequenceLevel consequenceLevel;
  final PriorityCategory category;
  final String? subjectEntityId;
  final List<PriorityDirectImpact> directImpacts;
  final LifeContextConfirmation confirmation;
  final PriorityFreshness freshness;
  final PriorityProvenance provenance;
  final int? sourceRevision;
  final String syncStatus;

  void validate() {
    if (schemaVersion != currentSchemaVersion) {
      throw const PriorityException('unsupported_priority_candidate_version');
    }
    if (id.trim().isEmpty ||
        accountScopeId.trim().isEmpty ||
        sourceId.trim().isEmpty ||
        syncStatus.trim().isEmpty ||
        effortMinutes != null && effortMinutes! <= 0 ||
        travelGoMinutes != null && travelGoMinutes! < 0 ||
        marginMinutes != null && marginMinutes! < 0 ||
        sourceRevision != null && sourceRevision! < 0 ||
        subjectEntityId != null && subjectEntityId!.trim().isEmpty ||
        (consequenceType == PriorityConsequenceType.unknown) !=
            (consequenceLevel == PriorityConsequenceLevel.unknown) ||
        !_validUnitValue(explicitImportance) ||
        !_validUnitValue(explicitUrgency)) {
      throw const PriorityException('invalid_priority_candidate');
    }
    provenance.validate();
    for (final impact in directImpacts) {
      impact.validate();
    }
  }

  static bool _validUnitValue(double? value) =>
      value == null || value.isFinite && value >= 0 && value <= 1;

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'id': id,
        'sourceDomain': sourceDomain.name,
        'sourceId': sourceId,
        'type': type.name,
        'status': status.name,
        if (deadline != null) 'deadline': deadline!.toUtc().toIso8601String(),
        if (temporalStart != null)
          'temporalStart': temporalStart!.toUtc().toIso8601String(),
        if (createdAt != null)
          'createdAt': createdAt!.toUtc().toIso8601String(),
        if (effortMinutes != null) 'effortMinutes': effortMinutes,
        if (travelGoMinutes != null) 'travelGoMinutes': travelGoMinutes,
        if (marginMinutes != null) 'marginMinutes': marginMinutes,
        'flexibility': flexibility.name,
        if (explicitImportance != null)
          'explicitImportance': explicitImportance,
        if (explicitUrgency != null) 'explicitUrgency': explicitUrgency,
        'consequenceType': consequenceType.name,
        'consequenceLevel': consequenceLevel.name,
        'category': category.name,
        if (subjectEntityId != null) 'subjectEntityId': subjectEntityId,
        'directImpacts':
            directImpacts.map((impact) => impact.toJson()).toList(),
        'confirmation': confirmation.name,
        'freshness': freshness.name,
        'provenance': provenance.toJson(),
        if (sourceRevision != null) 'sourceRevision': sourceRevision,
        'syncStatus': syncStatus,
      };
}

final class PriorityScoreComponent {
  PriorityScoreComponent({
    required this.dimension,
    required this.rawValue,
    required this.normalizedValue,
    required this.weight,
    required this.contribution,
    required this.provenance,
    required this.confidence,
    required List<PriorityMissingData> missingData,
    required List<String> reasonCodes,
  })  : missingData = UnmodifiableListView(
          List<PriorityMissingData>.of(missingData)
            ..sort((a, b) => a.index.compareTo(b.index)),
        ),
        reasonCodes =
            UnmodifiableListView(List<String>.of(reasonCodes)..sort()) {
    if (![rawValue, normalizedValue, weight, contribution]
            .every((value) => value.isFinite) ||
        normalizedValue < 0 ||
        normalizedValue > 1 ||
        weight < 0 ||
        weight > 1 ||
        contribution < -1 ||
        contribution > 1) {
      throw const PriorityException('invalid_priority_component');
    }
    provenance.validate();
  }

  final PriorityDimension dimension;
  final double rawValue;
  final double normalizedValue;
  final double weight;
  final double contribution;
  final PriorityProvenance provenance;
  final PriorityConfidence confidence;
  final List<PriorityMissingData> missingData;
  final List<String> reasonCodes;

  Map<String, Object?> toJson() => {
        'dimension': dimension.name,
        'rawValue': rawValue,
        'normalizedValue': normalizedValue,
        'weight': weight,
        'contribution': contribution,
        'provenance': provenance.toJson(),
        'confidence': confidence.name,
        'missingData': missingData.map((item) => item.name).toList(),
        'reasonCodes': reasonCodes,
      };
}

final class PriorityScore {
  static const int currentSchemaVersion = 1;

  PriorityScore({
    this.schemaVersion = currentSchemaVersion,
    required this.candidateId,
    required this.formulaVersion,
    required this.finalScore,
    required this.status,
    required this.confidence,
    required List<PriorityScoreComponent> components,
    required List<PriorityMissingData> missingData,
  })  : components = UnmodifiableListView(
          List<PriorityScoreComponent>.of(components)
            ..sort((a, b) => a.dimension.index.compareTo(b.dimension.index)),
        ),
        missingData = UnmodifiableListView(
          List<PriorityMissingData>.of(missingData)
            ..sort((a, b) => a.index.compareTo(b.index)),
        ) {
    if (schemaVersion != currentSchemaVersion) {
      throw const PriorityException('unsupported_priority_score_version');
    }
    if (candidateId.trim().isEmpty ||
        formulaVersion < 1 ||
        !finalScore.isFinite ||
        finalScore < 0 ||
        finalScore > 100 ||
        components.isEmpty) {
      throw const PriorityException('invalid_priority_score');
    }
  }

  final int schemaVersion;
  final String candidateId;
  final int formulaVersion;
  final double finalScore;
  final PriorityCalculationStatus status;
  final PriorityConfidence confidence;
  final List<PriorityScoreComponent> components;
  final List<PriorityMissingData> missingData;

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'candidateId': candidateId,
        'formulaVersion': formulaVersion,
        'finalScore': finalScore,
        'status': status.name,
        'confidence': confidence.name,
        'components':
            components.map((component) => component.toJson()).toList(),
        'missingData': missingData.map((item) => item.name).toList(),
      };
}

final class PriorityRankedCandidate {
  const PriorityRankedCandidate({
    required this.rank,
    required this.candidate,
    required this.score,
  });

  final int rank;
  final PriorityCandidate candidate;
  final PriorityScore score;
}

final class PriorityRanking {
  static const int currentSchemaVersion = 1;

  PriorityRanking({
    this.schemaVersion = currentSchemaVersion,
    required this.formulaVersion,
    required this.evaluatedAt,
    required List<PriorityRankedCandidate> items,
    required this.omittedCount,
    List<PriorityRankingWarning> warnings = const [],
  })  : items = UnmodifiableListView(items),
        warnings = UnmodifiableListView(
          List<PriorityRankingWarning>.of(warnings)
            ..sort((left, right) => left.index.compareTo(right.index)),
        ) {
    if (schemaVersion != currentSchemaVersion ||
        formulaVersion < 1 ||
        omittedCount < 0 ||
        items
            .asMap()
            .entries
            .any((entry) => entry.value.rank != entry.key + 1)) {
      throw const PriorityException('invalid_priority_ranking');
    }
  }

  final int schemaVersion;
  final int formulaVersion;
  final DateTime evaluatedAt;
  final List<PriorityRankedCandidate> items;
  final int omittedCount;
  final List<PriorityRankingWarning> warnings;
}
