import 'dart:collection';

import 'reasoning_input.dart';

enum ReasoningAssessmentOutcome {
  readyForCrossDomainReasoning,
  activeWorkflowTakesPrecedence,
  limitedByContext,
  insufficientCrossDomainEvidence,
}

final class ReasoningAssessmentException implements Exception {
  const ReasoningAssessmentException(this.code);

  final String code;

  @override
  String toString() => 'ReasoningAssessmentException($code)';
}

/// A bounded, explainable and non-executable RE.3 result.
final class ReasoningAssessment {
  static const int currentSchemaVersion = 1;
  static const int maximumSourceObservations = 12;

  ReasoningAssessment({
    this.schemaVersion = currentSchemaVersion,
    required this.assessmentId,
    required this.inputId,
    required this.accountScopeId,
    required this.generatedAt,
    required this.purpose,
    required this.outcome,
    required List<String> sourceObservationIds,
  }) : sourceObservationIds = UnmodifiableListView(
          List<String>.of(sourceObservationIds)..sort(),
        ) {
    if (schemaVersion != currentSchemaVersion) {
      throw const ReasoningAssessmentException(
        'unsupported_reasoning_assessment_version',
      );
    }
    if (assessmentId.trim().isEmpty ||
        assessmentId.length > 200 ||
        inputId.trim().isEmpty ||
        accountScopeId.trim().isEmpty ||
        this.sourceObservationIds.length > maximumSourceObservations ||
        this.sourceObservationIds.toSet().length !=
            this.sourceObservationIds.length ||
        this
            .sourceObservationIds
            .any((id) => id.trim().isEmpty || id.length > 160)) {
      throw const ReasoningAssessmentException(
        'invalid_reasoning_assessment',
      );
    }
    if ((outcome ==
                ReasoningAssessmentOutcome.insufficientCrossDomainEvidence) !=
            this.sourceObservationIds.isEmpty ||
        (outcome == ReasoningAssessmentOutcome.readyForCrossDomainReasoning &&
            this.sourceObservationIds.isEmpty)) {
      throw const ReasoningAssessmentException(
        'invalid_reasoning_assessment_evidence',
      );
    }
  }

  final int schemaVersion;
  final String assessmentId;
  final String inputId;
  final String accountScopeId;
  final DateTime generatedAt;
  final ReasoningPurpose purpose;
  final ReasoningAssessmentOutcome outcome;
  final List<String> sourceObservationIds;

  String get reasonCode => switch (outcome) {
        ReasoningAssessmentOutcome.readyForCrossDomainReasoning =>
          'cross_domain_context_ready',
        ReasoningAssessmentOutcome.activeWorkflowTakesPrecedence =>
          'active_workflow_takes_precedence',
        ReasoningAssessmentOutcome.limitedByContext =>
          'cross_domain_context_limited',
        ReasoningAssessmentOutcome.insufficientCrossDomainEvidence =>
          'cross_domain_evidence_insufficient',
      };

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'assessmentId': assessmentId,
        'inputId': inputId,
        'accountScopeId': accountScopeId,
        'generatedAt': generatedAt.toUtc().toIso8601String(),
        'purpose': purpose.name,
        'outcome': outcome.name,
        'reasonCode': reasonCode,
        'sourceObservationIds': sourceObservationIds,
      };
}
