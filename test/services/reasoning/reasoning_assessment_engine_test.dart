import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/conversation_models.dart';
import 'package:moms_ai/models/life_context/life_context_domains.dart';
import 'package:moms_ai/models/life_context/life_context_projection.dart';
import 'package:moms_ai/models/reasoning/reasoning_assessment.dart';
import 'package:moms_ai/models/reasoning/reasoning_input.dart';
import 'package:moms_ai/models/reasoning/reasoning_observation.dart';
import 'package:moms_ai/services/reasoning/reasoning_assessment_engine.dart';

void main() {
  final now = DateTime.utc(2026, 8, 4, 17);

  test('returns ready with the exact multi-domain explanation source', () {
    final input = _input(now);
    final observation = _observation(
      input,
      ReasoningObservationType.multiDomainEvidence,
    );

    final output = const ReasoningAssessmentEngine().assess(
      input: input,
      observations: _set(input, [observation]),
    );

    expect(
      output.outcome,
      ReasoningAssessmentOutcome.readyForCrossDomainReasoning,
    );
    expect(output.reasonCode, 'cross_domain_context_ready');
    expect(output.sourceObservationIds, [observation.observationId]);
  });

  test('limited context takes precedence and remains bounded', () {
    final input = _input(now, state: ReasoningInputState.partial);
    final multi = _observation(
      input,
      ReasoningObservationType.multiDomainEvidence,
    );
    final limited = _observation(
      input,
      ReasoningObservationType.limitedContext,
      reliability: ReasoningObservationReliability.limited,
    );

    final output = const ReasoningAssessmentEngine().assess(
      input: input,
      observations: _set(input, [multi, limited], limited: true),
    );

    expect(output.outcome, ReasoningAssessmentOutcome.limitedByContext);
    expect(output.sourceObservationIds, [limited.observationId]);
    expect(output.toJson().toString(), isNot(contains('private-value')));
  });

  test('active typed workflow takes precedence over multi-domain context', () {
    final input = _input(now);
    final multi = _observation(
      input,
      ReasoningObservationType.multiDomainEvidence,
    );
    final workflow = _observation(
      input,
      ReasoningObservationType.activeWorkflow,
    );

    final output = const ReasoningAssessmentEngine().assess(
      input: input,
      observations: _set(input, [multi, workflow]),
    );

    expect(
      output.outcome,
      ReasoningAssessmentOutcome.activeWorkflowTakesPrecedence,
    );
    expect(output.sourceObservationIds, [workflow.observationId]);
  });

  test('returns insufficient evidence without inventing an explanation source',
      () {
    final input = _input(now);

    final output = const ReasoningAssessmentEngine().assess(
      input: input,
      observations: _set(input, const []),
    );

    expect(
      output.outcome,
      ReasoningAssessmentOutcome.insufficientCrossDomainEvidence,
    );
    expect(output.sourceObservationIds, isEmpty);
  });

  test('fails closed when input and observations do not share one scope', () {
    final input = _input(now);

    expect(
      () => const ReasoningAssessmentEngine().assess(
        input: input,
        observations: ReasoningObservationSet(
          inputId: input.inputId,
          accountScopeId: 'account-b',
          generatedAt: input.generatedAt,
          state: ReasoningObservationSetState.empty,
          observations: const [],
        ),
      ),
      throwsA(
        isA<ReasoningAssessmentException>().having(
          (error) => error.code,
          'code',
          'reasoning_assessment_source_mismatch',
        ),
      ),
    );
  });
}

ReasoningInput _input(
  DateTime now, {
  ReasoningInputState state = ReasoningInputState.complete,
}) =>
    ReasoningInput(
      inputId: 'input-1',
      accountScopeId: 'account-a',
      purpose: ReasoningPurpose.organizeAcrossDomains,
      generatedAt: now,
      state: state,
      conversation: const ReasoningConversationState(
        phase: ConversationPhase.idle,
        hasCurrentInstruction: false,
        pendingActionType: null,
        pendingActionRisk: null,
        hasCanonicalConfirmation: false,
        sessionGeneration: 0,
      ),
      lifeContext: LifeContextProjection(
        projectionId: 'projection-1',
        sourceSnapshotId: 'snapshot-1',
        accountScopeId: 'account-a',
        purpose: LifeContextConsumerPurpose.conversation,
        generatedAt: now,
        state: state == ReasoningInputState.complete
            ? LifeContextProjectionState.complete
            : LifeContextProjectionState.partial,
        budgetRequested: 10,
        budgetUsed: 0,
        sections: [
          LifeContextProjectionSection(
            type: LifeContextProjectionSectionType.task,
            availability: LifeContextAvailability.available,
            freshness: LifeContextFreshness.current,
            items: const [],
            budgetLimit: 10,
            budgetUsed: 0,
            omittedCount: state == ReasoningInputState.complete ? 0 : 1,
            truncated: state == ReasoningInputState.partial,
            warningCode: state == ReasoningInputState.partial
                ? 'projection_truncated'
                : null,
          ),
        ],
        omittedCount: state == ReasoningInputState.complete ? 0 : 1,
        warningCodes: state == ReasoningInputState.complete
            ? const []
            : const ['projection_truncated'],
      ),
      warningCodes: state == ReasoningInputState.complete
          ? const []
          : const ['projection_truncated'],
    );

ReasoningObservation _observation(
  ReasoningInput input,
  ReasoningObservationType type, {
  ReasoningObservationReliability reliability =
      ReasoningObservationReliability.confirmed,
}) =>
    ReasoningObservation(
      observationId: '${input.inputId}:${type.name}',
      type: type,
      reliability: reliability,
      evidence: ReasoningObservationEvidence(
        sourceProjectionId: input.lifeContext.projectionId,
        sectionTypes: const [LifeContextProjectionSectionType.task],
        sourceItemIds: const [],
      ),
    );

ReasoningObservationSet _set(
  ReasoningInput input,
  List<ReasoningObservation> observations, {
  bool limited = false,
}) =>
    ReasoningObservationSet(
      inputId: input.inputId,
      accountScopeId: input.accountScopeId,
      generatedAt: input.generatedAt,
      state: observations.isEmpty
          ? ReasoningObservationSetState.empty
          : limited
              ? ReasoningObservationSetState.limited
              : ReasoningObservationSetState.observed,
      observations: observations,
    );
