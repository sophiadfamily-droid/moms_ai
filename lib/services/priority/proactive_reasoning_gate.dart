import '../../models/reasoning/reasoning_assessment.dart';

final class ProactiveReasoningGateDecision {
  const ProactiveReasoningGateDecision._(this.allowed, this.code);

  const ProactiveReasoningGateDecision.allow()
      : this._(true, 'reasoning_ready');

  const ProactiveReasoningGateDecision.block(String code) : this._(false, code);

  final bool allowed;
  final String code;
}

/// A read-only safety gate. Reasoning may block presentation but never create
/// or rank a proactive suggestion.
final class ProactiveReasoningGate {
  const ProactiveReasoningGate();

  ProactiveReasoningGateDecision evaluate(
    ReasoningAssessment assessment, {
    required bool requiresCrossDomainContext,
  }) =>
      switch (assessment.outcome) {
        ReasoningAssessmentOutcome.limitedByContext
            when requiresCrossDomainContext =>
          const ProactiveReasoningGateDecision.block(
            'reasoning_context_limited',
          ),
        ReasoningAssessmentOutcome.limitedByContext =>
          const ProactiveReasoningGateDecision.allow(),
        ReasoningAssessmentOutcome.activeWorkflowTakesPrecedence =>
          const ProactiveReasoningGateDecision.block(
            'reasoning_active_workflow',
          ),
        ReasoningAssessmentOutcome.readyForCrossDomainReasoning ||
        ReasoningAssessmentOutcome.insufficientCrossDomainEvidence =>
          const ProactiveReasoningGateDecision.allow(),
      };
}
