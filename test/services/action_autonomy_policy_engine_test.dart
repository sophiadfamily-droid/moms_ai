import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/action_autonomy_policy.dart';
import 'package:moms_ai/services/action_autonomy_policy_engine.dart';

void main() {
  const engine = ActionAutonomyPolicyEngine();
  final now = DateTime.utc(2026, 7, 23, 12);

  ActionAutonomyPolicy policy(ActionAutonomyMode mode) => ActionAutonomyPolicy(
        mode: mode,
        changedAt: now,
        changeSource: ActionAutonomyChangeSource.explicitUserSetting,
        accountScopeId: 'scope-a',
      );

  ActionAuthorizationRequest request(
    ActionType type, {
    ActionOrigin origin = ActionOrigin.explicitUserRequest,
    bool confirmation = false,
    bool grounded = true,
    bool complete = true,
    bool domainAllows = true,
    bool domainConfirmation = false,
    bool conflict = false,
    bool executed = false,
  }) =>
      ActionAuthorizationRequest(
        actionType: type,
        origin: origin,
        riskLevel: const ActionAutonomyActionRegistry().riskFor(type),
        sessionGeneration: 1,
        policyVersionObserved: 1,
        hasFreshExplicitConfirmation: confirmation,
        isGrounded: grounded,
        isComplete: complete,
        domainPolicyAllows: domainAllows,
        domainConfirmationRequired: domainConfirmation,
        hasBlockingConflict: conflict,
        isAlreadyExecuted: executed,
      );

  test('restrictive default is suggestions and serialization is deterministic',
      () {
    final value = ActionAutonomyPolicy.restrictiveDefault(
      accountScopeId: 'scope-a',
      changedAt: now,
    );
    expect(value.mode, ActionAutonomyMode.suggestions);
    expect(value.toBackendSummary(), {
      'schemaVersion': 1,
      'mode': 'suggestions',
    });
    expect(
      ActionAutonomyPolicy.fromJson(
        value.toJson(),
        expectedAccountScopeId: 'scope-a',
      ).mode,
      ActionAutonomyMode.suggestions,
    );
  });

  test('future version and account mismatch are refused', () {
    final json = policy(ActionAutonomyMode.normal).toJson();
    expect(
      () => ActionAutonomyPolicy.fromJson(
        {...json, 'schemaVersion': 2},
        expectedAccountScopeId: 'scope-a',
      ),
      throwsA(isA<ActionAutonomyPolicyException>()),
    );
    expect(
      () => ActionAutonomyPolicy.fromJson(
        json,
        expectedAccountScopeId: 'scope-b',
      ),
      throwsA(isA<ActionAutonomyPolicyException>()),
    );
  });

  test('normal allows explicit low-risk mutation but preserves confirmations',
      () {
    final direct = engine.evaluate(
      policy: policy(ActionAutonomyMode.normal),
      request: request(ActionType.createTask),
      evaluatedAt: now,
    );
    expect(direct.mayExecute, isTrue);
    final event = engine.evaluate(
      policy: policy(ActionAutonomyMode.normal),
      request: request(
        ActionType.createEvent,
        domainConfirmation: true,
      ),
      evaluatedAt: now,
    );
    expect(event.requiresConfirmation, isTrue);
    final destructive = engine.evaluate(
      policy: policy(ActionAutonomyMode.normal),
      request: request(ActionType.deleteAllMemory),
      evaluatedAt: now,
    );
    expect(destructive.requiresConfirmation, isTrue);
  });

  test('suggestions requires a fresh explicit confirmation for every mutation',
      () {
    final proposal = engine.evaluate(
      policy: policy(ActionAutonomyMode.suggestions),
      request: request(ActionType.createTask),
      evaluatedAt: now,
    );
    expect(proposal.decision,
        ActionAuthorizationDecisionType.requireExplicitConfirmation);
    final confirmed = engine.evaluate(
      policy: policy(ActionAutonomyMode.suggestions),
      request: request(
        ActionType.createTask,
        origin: ActionOrigin.explicitUserConfirmation,
        confirmation: true,
      ),
      evaluatedAt: now,
    );
    expect(confirmed.mayExecute, isTrue);
    final retry = engine.evaluate(
      policy: policy(ActionAutonomyMode.suggestions),
      request: request(ActionType.createTask, origin: ActionOrigin.retry),
      evaluatedAt: now,
    );
    expect(retry.mayExecute, isFalse);
  });

  test('paused allows reads and blocks mutations confirmations and retry', () {
    final read = engine.evaluate(
      policy: policy(ActionAutonomyMode.paused),
      request: request(ActionType.readAgenda),
      evaluatedAt: now,
    );
    expect(read.decision, ActionAuthorizationDecisionType.allowReadOnly);
    for (final origin in [
      ActionOrigin.explicitUserRequest,
      ActionOrigin.explicitUserConfirmation,
      ActionOrigin.retry,
      ActionOrigin.restoredPending,
    ]) {
      final result = engine.evaluate(
        policy: policy(ActionAutonomyMode.paused),
        request: request(ActionType.createEvent, origin: origin),
        evaluatedAt: now,
      );
      expect(result.decision, ActionAuthorizationDecisionType.blockedPaused);
    }
  });

  test('the most restrictive guard wins before the autonomy mode', () {
    expect(
      engine
          .evaluate(
            policy: policy(ActionAutonomyMode.normal),
            request: request(ActionType.createTask, grounded: false),
            evaluatedAt: now,
          )
          .decision,
      ActionAuthorizationDecisionType.blockedUngrounded,
    );
    expect(
      engine
          .evaluate(
            policy: policy(ActionAutonomyMode.normal),
            request: request(ActionType.createTask, complete: false),
            evaluatedAt: now,
          )
          .decision,
      ActionAuthorizationDecisionType.blockedIncomplete,
    );
    expect(
      engine
          .evaluate(
            policy: policy(ActionAutonomyMode.normal),
            request: request(ActionType.confirmMemory, domainAllows: false),
            evaluatedAt: now,
          )
          .decision,
      ActionAuthorizationDecisionType.blockedDomainPolicy,
    );
  });

  test('proactive external unknown and third-party origins stay blocked', () {
    for (final origin in [
      ActionOrigin.systemProactive,
      ActionOrigin.externalTrigger,
      ActionOrigin.unknown,
    ]) {
      expect(
        engine
            .evaluate(
              policy: policy(ActionAutonomyMode.normal),
              request: request(ActionType.createTask, origin: origin),
              evaluatedAt: now,
            )
            .mayExecute,
        isFalse,
      );
    }
    expect(
      engine
          .evaluate(
            policy: policy(ActionAutonomyMode.normal),
            request: request(ActionType.thirdPartyUnsupported),
            evaluatedAt: now,
          )
          .decision,
      ActionAuthorizationDecisionType.blockedUnsupported,
    );
  });

  test('typed pending is bounded, immutable and preserves mutation identity',
      () {
    final pending = ActionPending(
      pendingActionId: 'pending-1',
      sessionGeneration: 3,
      actionType: ActionType.createTask,
      origin: ActionOrigin.explicitUserRequest,
      riskLevel: ActionRiskLevel.reversibleLowRisk,
      policyModeAtCreation: ActionAutonomyMode.suggestions,
      policyVersionAtCreation: 1,
      wasGrounded: true,
      wasComplete: true,
      payload: const PendingTaskPayload(title: 'Dossier'),
      originalInstruction: 'Ajoute le dossier',
      mutationId: 'mutation-1',
      createdAt: now,
      expiresAt: now.add(const Duration(minutes: 15)),
    );
    pending.validate();
    final executing = pending.copyWith(
      state: ActionPendingState.executing,
      hasFreshConfirmation: true,
      attemptCount: 1,
    );
    expect(executing.mutationId, pending.mutationId);
    expect(executing.sessionGeneration, 3);
    expect(executing.hasFreshConfirmation, isTrue);
    expect(pending.isExpiredAt(now), isFalse);
    expect(
      pending.isExpiredAt(now.add(const Duration(minutes: 15))),
      isTrue,
    );
    expect(
      () => pending.copyWith(attemptCount: 3).validate(),
      throwsA(isA<ActionAutonomyPolicyException>()),
    );
  });
}
