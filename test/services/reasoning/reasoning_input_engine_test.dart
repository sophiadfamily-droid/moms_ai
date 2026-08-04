import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_id_generator.dart';
import 'package:moms_ai/models/conversation_models.dart';
import 'package:moms_ai/models/life_context/life_context_domains.dart';
import 'package:moms_ai/models/life_context/life_context_graph.dart';
import 'package:moms_ai/models/life_context/life_context_projection.dart';
import 'package:moms_ai/models/reasoning/reasoning_input.dart';
import 'package:moms_ai/services/reasoning/reasoning_input_engine.dart';

void main() {
  final now = DateTime.utc(2026, 8, 4, 15);

  test('builds a read-only typed input without conversation content', () {
    final engine = ReasoningInputEngine(
      idGenerator: const _FixedIdGenerator(),
      clock: () => now,
    );
    final input = engine.build(
      accountScopeId: 'account-a',
      purpose: ReasoningPurpose.organizeAcrossDomains,
      conversationState: const ConversationState(
        phase: ConversationPhase.sending,
        currentInstruction: 'private instruction must not cross',
      ),
      sessionGeneration: 4,
      lifeContext: _projection(now),
    );

    expect(input.state, ReasoningInputState.complete);
    expect(input.conversation.hasCurrentInstruction, isTrue);
    expect(input.conversation.sessionGeneration, 4);
    expect(input.toJson().toString(), isNot(contains('private instruction')));
    expect(input.lifeContext.accountScopeId, 'account-a');
  });

  test('fails closed on account and consumer-purpose mismatches', () {
    final engine = ReasoningInputEngine(
      idGenerator: const _FixedIdGenerator(),
      clock: () => now,
    );
    expect(
      () => engine.build(
        accountScopeId: 'account-b',
        purpose: ReasoningPurpose.explainTradeoffs,
        conversationState: const ConversationState(),
        sessionGeneration: 0,
        lifeContext: _projection(now),
      ),
      throwsA(
        isA<ReasoningInputException>().having(
          (error) => error.code,
          'code',
          'reasoning_account_scope_mismatch',
        ),
      ),
    );
    expect(
      () => engine.build(
        accountScopeId: 'account-a',
        purpose: ReasoningPurpose.explainTradeoffs,
        conversationState: const ConversationState(),
        sessionGeneration: 0,
        lifeContext: _projection(
          now,
          purpose: LifeContextConsumerPurpose.planning,
        ),
      ),
      throwsA(
        isA<ReasoningInputException>().having(
          (error) => error.code,
          'code',
          'reasoning_projection_purpose_mismatch',
        ),
      ),
    );
  });

  test('marks partial Life Context explicitly and preserves warning codes', () {
    final input = ReasoningInputEngine(
      idGenerator: const _FixedIdGenerator(),
      clock: () => now,
    ).build(
      accountScopeId: 'account-a',
      purpose: ReasoningPurpose.exploreScenario,
      conversationState: const ConversationState(),
      sessionGeneration: 1,
      lifeContext: _projection(
        now,
        state: LifeContextProjectionState.partial,
        warnings: const ['projection_truncated'],
      ),
    );

    expect(input.state, ReasoningInputState.partial);
    expect(
      input.warningCodes,
      ['life_context_partial', 'projection_truncated'],
    );
  });
}

final class _FixedIdGenerator implements EntityIdGenerator {
  const _FixedIdGenerator();

  @override
  String generate() => 'reasoning-input-1';
}

LifeContextProjection _projection(
  DateTime now, {
  LifeContextConsumerPurpose purpose = LifeContextConsumerPurpose.conversation,
  LifeContextProjectionState state = LifeContextProjectionState.complete,
  List<String> warnings = const [],
}) =>
    LifeContextProjection(
      projectionId: 'projection-1',
      sourceSnapshotId: 'snapshot-1',
      accountScopeId: 'account-a',
      purpose: purpose,
      generatedAt: now,
      state: state,
      budgetRequested: 10,
      budgetUsed: 2,
      sections: [
        LifeContextProjectionSection(
          type: LifeContextProjectionSectionType.human,
          availability: LifeContextAvailability.available,
          freshness: LifeContextFreshness.current,
          items: [
            LifeContextProjectionItem(
              id: 'human-1',
              domain: LifeContextDomain.human,
              type: 'person',
              facts: [
                LifeContextProjectionFact(
                  key: LifeContextProjectionFactKeys.status,
                  value: 'active',
                  sensitivity: LifeContextSensitivityLevel.publicTechnical,
                ),
              ],
              confirmation: LifeContextConfirmation.confirmed,
              freshness: LifeContextFreshness.current,
              provenance: const LifeContextProjectionProvenance(
                sourceDomain: LifeContextDomain.human,
                sourceId: 'human-1',
                sourceSnapshotId: 'snapshot-1',
                sourceKind: LifeContextSourceKind.humanModelLocal,
              ),
            ),
          ],
          budgetLimit: 10,
          budgetUsed: 2,
          omittedCount: 0,
          truncated: false,
        ),
      ],
      omittedCount: 0,
      warningCodes: warnings,
    );
