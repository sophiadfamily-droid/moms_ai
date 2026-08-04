import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/reasoning/reasoning_assessment.dart';
import 'package:moms_ai/models/reasoning/reasoning_input.dart';
import 'package:moms_ai/services/priority/proactive_reasoning_gate.dart';

void main() {
  const gate = ProactiveReasoningGate();

  test('blocks limited context and an active workflow', () {
    expect(
      gate
          .evaluate(
            _assessment(ReasoningAssessmentOutcome.limitedByContext),
            requiresCrossDomainContext: true,
          )
          .code,
      'reasoning_context_limited',
    );
    expect(
      gate
          .evaluate(
            _assessment(
              ReasoningAssessmentOutcome.activeWorkflowTakesPrecedence,
            ),
            requiresCrossDomainContext: false,
          )
          .code,
      'reasoning_active_workflow',
    );
  });

  test('allows ready context and harmless insufficient cross-domain evidence',
      () {
    expect(
      gate
          .evaluate(
            _assessment(
              ReasoningAssessmentOutcome.readyForCrossDomainReasoning,
            ),
            requiresCrossDomainContext: true,
          )
          .allowed,
      isTrue,
    );
    expect(
      gate
          .evaluate(
            _assessment(
              ReasoningAssessmentOutcome.insufficientCrossDomainEvidence,
            ),
            requiresCrossDomainContext: false,
          )
          .allowed,
      isTrue,
    );
  });

  test('limited optional context allows a single-domain suggestion', () {
    expect(
      gate
          .evaluate(
            _assessment(ReasoningAssessmentOutcome.limitedByContext),
            requiresCrossDomainContext: false,
          )
          .allowed,
      isTrue,
    );
  });
}

ReasoningAssessment _assessment(ReasoningAssessmentOutcome outcome) =>
    ReasoningAssessment(
      assessmentId: 'assessment-1',
      inputId: 'input-1',
      accountScopeId: 'account-a',
      generatedAt: DateTime.utc(2026, 8, 5),
      purpose: ReasoningPurpose.organizeAcrossDomains,
      outcome: outcome,
      sourceObservationIds:
          outcome == ReasoningAssessmentOutcome.insufficientCrossDomainEvidence
              ? const []
              : const ['observation-1'],
    );
