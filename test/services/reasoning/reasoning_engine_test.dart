import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_id_generator.dart';
import 'package:moms_ai/models/conversation_models.dart';
import 'package:moms_ai/models/life_context/life_context_domains.dart';
import 'package:moms_ai/models/life_context/life_context_projection.dart';
import 'package:moms_ai/models/reasoning/reasoning_assessment.dart';
import 'package:moms_ai/models/reasoning/reasoning_input.dart';
import 'package:moms_ai/services/reasoning/reasoning_engine.dart';

void main() {
  final now = DateTime.utc(2026, 8, 4, 19);

  test('composes one coherent deterministic RE.1-3 evaluation', () {
    final result = ReasoningEngine(
      idGenerator: const _Id(),
      clock: () => now,
    ).evaluate(
      accountScopeId: 'account-a',
      purpose: ReasoningPurpose.organizeAcrossDomains,
      conversationState: const ConversationState(),
      sessionGeneration: 2,
      lifeContext: _projection(now),
    );

    expect(result.input.inputId, 'reasoning-1');
    expect(result.observations.inputId, result.input.inputId);
    expect(result.assessment.inputId, result.input.inputId);
    expect(
      result.assessment.outcome,
      ReasoningAssessmentOutcome.insufficientCrossDomainEvidence,
    );
  });

  test('propagates partial context to the closed limited assessment', () {
    final result = ReasoningEngine(
      idGenerator: const _Id(),
      clock: () => now,
    ).evaluate(
      accountScopeId: 'account-a',
      purpose: ReasoningPurpose.exploreScenario,
      conversationState: const ConversationState(),
      sessionGeneration: 0,
      lifeContext: _projection(now, partial: true),
    );

    expect(result.input.state, ReasoningInputState.partial);
    expect(
      result.assessment.outcome,
      ReasoningAssessmentOutcome.limitedByContext,
    );
  });
}

final class _Id implements EntityIdGenerator {
  const _Id();

  @override
  String generate() => 'reasoning-1';
}

LifeContextProjection _projection(DateTime now, {bool partial = false}) =>
    LifeContextProjection(
      projectionId: 'projection-1',
      sourceSnapshotId: 'snapshot-1',
      accountScopeId: 'account-a',
      purpose: LifeContextConsumerPurpose.conversation,
      generatedAt: now,
      state: partial
          ? LifeContextProjectionState.partial
          : LifeContextProjectionState.complete,
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
          omittedCount: partial ? 1 : 0,
          truncated: partial,
          warningCode: partial ? 'projection_truncated' : null,
        ),
      ],
      omittedCount: partial ? 1 : 0,
      warningCodes: partial ? const ['projection_truncated'] : const [],
    );
