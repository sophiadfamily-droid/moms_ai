import 'dart:collection';

import 'priority_models.dart';
import 'priority_propagation_models.dart';

enum PriorityExplanationDetailLevel { short, detailed }

enum PriorityExplanationPolarity { positive, neutral, reducing, warning }

enum PriorityExplanationReasonCode {
  overdue,
  dueVerySoon,
  dueToday,
  dueTomorrow,
  dueSoon,
  distantDeadline,
  noDeadline,
  explicitUrgency,
  explicitImportanceHigh,
  explicitImportanceModerate,
  explicitImportanceLow,
  importanceUnknown,
  effortKnown,
  effortUnknown,
  insufficientTime,
  fixed,
  lowFlexibility,
  flexible,
  veryFlexible,
  flexibilityUnknown,
  directImpact,
  noDirectImpact,
  propagatedDependency,
  noPropagation,
  staleData,
  missingData,
  partialCalculation,
  cycleDetected,
  truncatedPropagation,
  uncertainDependency,
  unsupportedCandidate,
  higherAdjustedScore,
  higherDirectScore,
  closerDeadline,
  moreRigid,
  strongerConfirmation,
  fresherData,
  stableTieBreak,
  equivalentRanking,
}

enum PriorityComparisonBasis {
  adjustedScore,
  directScore,
  deadline,
  rigidity,
  confirmation,
  freshness,
  stableOrder,
  equivalent,
}

final class PriorityExplanationReason {
  static const int currentSchemaVersion = 1;

  PriorityExplanationReason({
    this.schemaVersion = currentSchemaVersion,
    required this.code,
    required this.polarity,
    required this.shortText,
    required this.detailedText,
    required this.contribution,
    this.dimension,
    this.depth,
  }) {
    if (schemaVersion != currentSchemaVersion) {
      throw const PriorityException(
        'unsupported_priority_explanation_reason_version',
      );
    }
    if (shortText.trim().isEmpty ||
        detailedText.trim().isEmpty ||
        shortText.length > 180 ||
        detailedText.length > 360 ||
        !contribution.isFinite ||
        contribution < -100 ||
        contribution > 100 ||
        depth != null && depth! < 1) {
      throw const PriorityException('invalid_priority_explanation_reason');
    }
  }

  final int schemaVersion;
  final PriorityExplanationReasonCode code;
  final PriorityExplanationPolarity polarity;
  final String shortText;
  final String detailedText;
  final double contribution;
  final PriorityDimension? dimension;
  final int? depth;

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'code': code.name,
        'polarity': polarity.name,
        'shortText': shortText,
        'detailedText': detailedText,
        'contribution': contribution,
        if (dimension != null) 'dimension': dimension!.name,
        if (depth != null) 'depth': depth,
      };
}

final class PriorityExplanation {
  static const int currentSchemaVersion = 1;
  static const int maximumShortTextLength = 320;
  static const int maximumParagraphLength = 500;
  static const int maximumParagraphs = 8;
  static const int maximumDetailedLength = 2400;

  PriorityExplanation({
    this.schemaVersion = currentSchemaVersion,
    required this.candidateId,
    required this.formulaVersion,
    this.propagationVersion,
    required this.detailLevel,
    required this.calculationStatus,
    required this.confidence,
    required this.shortText,
    required List<String> paragraphs,
    required List<PriorityExplanationReason> primaryReasons,
    required List<PriorityExplanationReason> secondaryReasons,
    required List<PriorityExplanationReason> reducingFactors,
    required List<PriorityMissingData> missingData,
    required List<PriorityExplanationReason> propagationReasons,
    required this.cycleState,
    required this.truncationState,
    required List<PriorityExplanationReason> warnings,
    required this.sourceSnapshotId,
    required this.evaluatedAt,
  })  : paragraphs = UnmodifiableListView(paragraphs),
        primaryReasons = UnmodifiableListView(primaryReasons),
        secondaryReasons = UnmodifiableListView(secondaryReasons),
        reducingFactors = UnmodifiableListView(reducingFactors),
        missingData = UnmodifiableListView(
          List<PriorityMissingData>.of(missingData)
            ..sort((a, b) => a.index.compareTo(b.index)),
        ),
        propagationReasons = UnmodifiableListView(propagationReasons),
        warnings = UnmodifiableListView(warnings) {
    if (schemaVersion != currentSchemaVersion) {
      throw const PriorityException('unsupported_priority_explanation_version');
    }
    final detailedLength = paragraphs.fold<int>(
      0,
      (sum, paragraph) => sum + paragraph.length,
    );
    final allReasons = [
      ...primaryReasons,
      ...secondaryReasons,
      ...reducingFactors,
      ...propagationReasons,
      ...warnings,
    ];
    if (candidateId.trim().isEmpty ||
        formulaVersion < 1 ||
        propagationVersion != null && propagationVersion! < 1 ||
        shortText.trim().isEmpty ||
        shortText.length > maximumShortTextLength ||
        paragraphs.isEmpty ||
        paragraphs.length > maximumParagraphs ||
        paragraphs.any(
          (paragraph) =>
              paragraph.trim().isEmpty ||
              paragraph.length > maximumParagraphLength,
        ) ||
        detailedLength > maximumDetailedLength ||
        allReasons.isEmpty ||
        sourceSnapshotId.trim().isEmpty) {
      throw const PriorityException('invalid_priority_explanation');
    }
  }

  final int schemaVersion;
  final String candidateId;
  final int formulaVersion;
  final int? propagationVersion;
  final PriorityExplanationDetailLevel detailLevel;
  final PriorityCalculationStatus calculationStatus;
  final PriorityConfidence confidence;
  final String shortText;
  final List<String> paragraphs;
  final List<PriorityExplanationReason> primaryReasons;
  final List<PriorityExplanationReason> secondaryReasons;
  final List<PriorityExplanationReason> reducingFactors;
  final List<PriorityMissingData> missingData;
  final List<PriorityExplanationReason> propagationReasons;
  final PriorityPropagationCycleState cycleState;
  final PriorityPropagationTruncationState truncationState;
  final List<PriorityExplanationReason> warnings;
  final String sourceSnapshotId;
  final DateTime evaluatedAt;

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'formulaVersion': formulaVersion,
        if (propagationVersion != null)
          'propagationVersion': propagationVersion,
        'detailLevel': detailLevel.name,
        'calculationStatus': calculationStatus.name,
        'confidence': confidence.name,
        'shortText': shortText,
        'paragraphs': paragraphs,
        'primaryReasons':
            primaryReasons.map((reason) => reason.toJson()).toList(),
        'secondaryReasons':
            secondaryReasons.map((reason) => reason.toJson()).toList(),
        'reducingFactors':
            reducingFactors.map((reason) => reason.toJson()).toList(),
        'missingData': missingData.map((item) => item.name).toList(),
        'propagationReasons':
            propagationReasons.map((reason) => reason.toJson()).toList(),
        'cycleState': cycleState.name,
        'truncationState': truncationState.name,
        'warnings': warnings.map((reason) => reason.toJson()).toList(),
        'sourceSnapshotId': sourceSnapshotId,
        'evaluatedAt': evaluatedAt.toUtc().toIso8601String(),
      };
}

final class PriorityComparisonExplanation {
  static const int currentSchemaVersion = 1;

  PriorityComparisonExplanation({
    this.schemaVersion = currentSchemaVersion,
    required this.firstCandidateId,
    required this.secondCandidateId,
    required this.basis,
    required this.shortText,
    required List<PriorityExplanationReason> reasons,
    required this.evaluatedAt,
  }) : reasons = UnmodifiableListView(reasons) {
    if (schemaVersion != currentSchemaVersion) {
      throw const PriorityException(
        'unsupported_priority_comparison_version',
      );
    }
    if (firstCandidateId.trim().isEmpty ||
        secondCandidateId.trim().isEmpty ||
        firstCandidateId == secondCandidateId ||
        shortText.trim().isEmpty ||
        shortText.length > PriorityExplanation.maximumShortTextLength ||
        reasons.isEmpty) {
      throw const PriorityException('invalid_priority_comparison');
    }
  }

  final int schemaVersion;
  final String firstCandidateId;
  final String secondCandidateId;
  final PriorityComparisonBasis basis;
  final String shortText;
  final List<PriorityExplanationReason> reasons;
  final DateTime evaluatedAt;

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'basis': basis.name,
        'shortText': shortText,
        'reasons': reasons.map((reason) => reason.toJson()).toList(),
        'evaluatedAt': evaluatedAt.toUtc().toIso8601String(),
      };
}

final class PriorityRankingExplanation {
  PriorityRankingExplanation({
    required this.offset,
    required this.totalCount,
    required List<PriorityExplanation> explanations,
    required this.hasMore,
  }) : explanations = UnmodifiableListView(explanations) {
    if (offset < 0 ||
        totalCount < 0 ||
        explanations.length > 10 ||
        offset + explanations.length > totalCount) {
      throw const PriorityException('invalid_priority_ranking_explanation');
    }
  }

  final int offset;
  final int totalCount;
  final List<PriorityExplanation> explanations;
  final bool hasMore;
}
