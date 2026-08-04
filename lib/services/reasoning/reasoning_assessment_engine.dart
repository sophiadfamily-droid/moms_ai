import '../../models/reasoning/reasoning_assessment.dart';
import '../../models/reasoning/reasoning_input.dart';
import '../../models/reasoning/reasoning_observation.dart';

/// V1-RE.3 reduces RE.2 observations to one closed, explainable assessment.
///
/// The result is not user-facing copy, a recommendation, an authorization or
/// an executable action. Current typed workflow always takes precedence over
/// complete contextual evidence, unless the context itself is limited.
final class ReasoningAssessmentEngine {
  const ReasoningAssessmentEngine();

  ReasoningAssessment assess({
    required ReasoningInput input,
    required ReasoningObservationSet observations,
  }) {
    if (observations.inputId != input.inputId ||
        observations.accountScopeId != input.accountScopeId ||
        observations.generatedAt != input.generatedAt) {
      throw const ReasoningAssessmentException(
        'reasoning_assessment_source_mismatch',
      );
    }

    final limited = _ofType(
      observations,
      ReasoningObservationType.limitedContext,
      includeLimitedAvailability: true,
    );
    final workflow = _ofType(
      observations,
      ReasoningObservationType.activeWorkflow,
    );
    final multiDomain = _ofType(
      observations,
      ReasoningObservationType.multiDomainEvidence,
    );

    final outcome = limited.isNotEmpty
        ? ReasoningAssessmentOutcome.limitedByContext
        : workflow.isNotEmpty
            ? ReasoningAssessmentOutcome.activeWorkflowTakesPrecedence
            : multiDomain.isNotEmpty
                ? ReasoningAssessmentOutcome.readyForCrossDomainReasoning
                : ReasoningAssessmentOutcome.insufficientCrossDomainEvidence;
    final sources = switch (outcome) {
      ReasoningAssessmentOutcome.limitedByContext => limited,
      ReasoningAssessmentOutcome.activeWorkflowTakesPrecedence => workflow,
      ReasoningAssessmentOutcome.readyForCrossDomainReasoning => multiDomain,
      ReasoningAssessmentOutcome.insufficientCrossDomainEvidence =>
        const <ReasoningObservation>[],
    };

    return ReasoningAssessment(
      assessmentId: '${input.inputId}:assessment',
      inputId: input.inputId,
      accountScopeId: input.accountScopeId,
      generatedAt: input.generatedAt,
      purpose: input.purpose,
      outcome: outcome,
      sourceObservationIds:
          sources.map((observation) => observation.observationId).toList(),
    );
  }

  List<ReasoningObservation> _ofType(
    ReasoningObservationSet set,
    ReasoningObservationType type, {
    bool includeLimitedAvailability = false,
  }) =>
      set.observations
          .where(
            (observation) =>
                observation.type == type ||
                (includeLimitedAvailability &&
                    observation.type ==
                        ReasoningObservationType.unavailableContextSection),
          )
          .take(ReasoningAssessment.maximumSourceObservations)
          .toList();
}
