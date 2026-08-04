import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_id_generator.dart';
import 'package:moms_ai/models/conversation_models.dart';
import 'package:moms_ai/models/life_context/life_context_domains.dart';
import 'package:moms_ai/models/life_context/life_context_projection.dart';
import 'package:moms_ai/models/reasoning/reasoning_assessment.dart';
import 'package:moms_ai/models/reasoning/reasoning_input.dart';
import 'package:moms_ai/services/reasoning/reasoning_application_service.dart';
import 'package:moms_ai/services/reasoning/reasoning_engine.dart';

void main() {
  final now = DateTime.utc(2026, 8, 4, 20);

  test('loads bounded conversation context and runs RE.1-4', () async {
    String? requestedAccount;
    final service = ReasoningApplicationService(
      loadProjection: (accountScopeId) async {
        requestedAccount = accountScopeId;
        return _projection(now);
      },
      engine: ReasoningEngine(
        idGenerator: const _Id(),
        clock: () => now,
      ),
    );

    final result = await service.evaluate(
      accountScopeId: 'account-a',
      purpose: ReasoningPurpose.organizeAcrossDomains,
      conversationState: const ConversationState(),
      sessionGeneration: 3,
    );

    expect(requestedAccount, 'account-a');
    expect(result.input.conversation.sessionGeneration, 3);
    expect(
      result.assessment.outcome,
      ReasoningAssessmentOutcome.insufficientCrossDomainEvidence,
    );
  });

  test('rejects an empty account before loading context', () async {
    var loads = 0;
    final service = ReasoningApplicationService(
      loadProjection: (_) async {
        loads++;
        return _projection(now);
      },
    );

    await expectLater(
      service.evaluate(
        accountScopeId: ' ',
        purpose: ReasoningPurpose.explainTradeoffs,
        conversationState: const ConversationState(),
        sessionGeneration: 0,
      ),
      throwsA(isA<ReasoningInputException>()),
    );
    expect(loads, 0);
  });

  test('fails closed when production context belongs to another account',
      () async {
    final service = ReasoningApplicationService(
      loadProjection: (_) async => _projection(now, account: 'account-b'),
      engine: ReasoningEngine(
        idGenerator: const _Id(),
        clock: () => now,
      ),
    );

    await expectLater(
      service.evaluate(
        accountScopeId: 'account-a',
        purpose: ReasoningPurpose.exploreScenario,
        conversationState: const ConversationState(),
        sessionGeneration: 0,
      ),
      throwsA(
        isA<ReasoningInputException>().having(
          (error) => error.code,
          'code',
          'reasoning_account_scope_mismatch',
        ),
      ),
    );
  });
}

final class _Id implements EntityIdGenerator {
  const _Id();

  @override
  String generate() => 'reasoning-application-1';
}

LifeContextProjection _projection(
  DateTime now, {
  String account = 'account-a',
}) =>
    LifeContextProjection(
      projectionId: 'projection-1',
      sourceSnapshotId: 'snapshot-1',
      accountScopeId: account,
      purpose: LifeContextConsumerPurpose.conversation,
      generatedAt: now,
      state: LifeContextProjectionState.complete,
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
          omittedCount: 0,
          truncated: false,
        ),
      ],
      omittedCount: 0,
      warningCodes: const [],
    );
