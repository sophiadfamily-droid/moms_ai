import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/action_autonomy_policy.dart';
import 'package:moms_ai/models/action_confirmation.dart';
import 'package:moms_ai/models/action_ledger.dart';
import 'package:moms_ai/services/action_confirmation_coordinator.dart';

void main() {
  late DateTime now;
  late ActionAutonomyMode mode;
  late String scope;
  late int id;
  late ActionConfirmationCoordinator coordinator;

  setUp(() {
    now = DateTime.utc(2026, 7, 24, 10);
    mode = ActionAutonomyMode.suggestions;
    scope = 'scope-a';
    id = 0;
    coordinator = ActionConfirmationCoordinator(
      idGenerator: () => 'confirmation-${++id}',
      policyLoader: () async => ActionAutonomyPolicy(
        mode: mode,
        changedAt: now,
        changeSource: ActionAutonomyChangeSource.explicitUserSetting,
        accountScopeId: scope,
      ),
      currentAccountScopeId: () => scope,
      now: () => now,
    );
  });

  test('canonical confirmation is scoped, expiring and deterministic',
      () async {
    final first = await coordinator.issue(_proposal(now));
    expect(first.confirmation.schemaVersion, 1);
    expect(first.confirmation.sessionGeneration, 4);
    expect(first.confirmation.expiresAt, now.add(const Duration(minutes: 15)));
    expect(first.confirmation.state, ActionConfirmationState.awaitingResponse);
    expect(first.confirmation.toJson(), isNot(contains('accountScopeId')));

    final duplicate = await coordinator.issue(_proposal(now));
    expect(duplicate.idempotent, isTrue);
    expect(
      duplicate.confirmation.confirmationId,
      first.confirmation.confirmationId,
    );
  });

  test('fingerprint ignores field order and changes with payload', () {
    final scopeA = _scope([
      const ActionConfirmationField(
        key: ActionConfirmationFieldKey.title,
        value: 'Dossier',
      ),
      const ActionConfirmationField(
        key: ActionConfirmationFieldKey.dueDate,
        value: null,
      ),
    ]);
    final scopeB = _scope([
      const ActionConfirmationField(
        key: ActionConfirmationFieldKey.dueDate,
        value: null,
      ),
      const ActionConfirmationField(
        key: ActionConfirmationFieldKey.title,
        value: 'Dossier',
      ),
    ]);
    final scopeC = _scope([
      const ActionConfirmationField(
        key: ActionConfirmationFieldKey.title,
        value: 'Autre',
      ),
    ]);
    String fingerprint(ActionConfirmationScope value) =>
        ActionConfirmationFingerprint.compute(
          actionType: ActionType.createTask,
          domain: ActionLedgerDomain.task,
          riskLevel: ActionRiskLevel.reversibleLowRisk,
          scope: value,
          mutationId: 'mutation-1',
        );
    expect(fingerprint(scopeA), fingerprint(scopeB));
    expect(fingerprint(scopeA), isNot(fingerprint(scopeC)));
  });

  test('accept is consumed once after every revalidation', () async {
    final issued = await coordinator.issue(_proposal(now));
    var c3 = 0;
    var domain = 0;
    var revision = 0;
    final response = _response(issued.confirmation, now);
    final result = await coordinator.respond(
      response: response,
      currentSessionGeneration: 4,
      c3Validator: (_) async {
        c3++;
        return true;
      },
      domainValidator: (_) {
        domain++;
        return true;
      },
      revisionValidator: (_) {
        revision++;
        return true;
      },
    );
    expect(result.type, ActionConfirmationResultType.consumed);
    expect(result.dispatchAllowed, isTrue);
    expect([c3, domain, revision], [1, 1, 1]);

    final duplicate = await coordinator.respond(
      response: response,
      currentSessionGeneration: 4,
      c3Validator: (_) => true,
      domainValidator: (_) => true,
      revisionValidator: (_) => true,
    );
    expect(duplicate.idempotent, isTrue);
    expect(duplicate.dispatchAllowed, isFalse);
  });

  test('same response id with another answer is refused', () async {
    final issued = await coordinator.issue(_proposal(now));
    final accepted = _response(issued.confirmation, now);
    await coordinator.respond(
      response: accepted,
      currentSessionGeneration: 4,
      c3Validator: (_) => true,
      domainValidator: (_) => true,
      revisionValidator: (_) => true,
    );
    expect(
      () => coordinator.respond(
        response: ActionConfirmationResponse(
          responseId: accepted.responseId,
          confirmationId: accepted.confirmationId,
          sessionGeneration: accepted.sessionGeneration,
          respondedAt: accepted.respondedAt,
          choice: ActionConfirmationResponseChoice.reject,
          actionFingerprint: accepted.actionFingerprint,
        ),
        currentSessionGeneration: 4,
        c3Validator: (_) => true,
        domainValidator: (_) => true,
        revisionValidator: (_) => true,
      ),
      throwsFormatException,
    );
  });

  test('expiration, old session, changed payload and pause never dispatch',
      () async {
    final expiring = await coordinator.issue(_proposal(now));
    now = now.add(const Duration(minutes: 16));
    final expired = await coordinator.respond(
      response: _response(expiring.confirmation, now),
      currentSessionGeneration: 4,
      c3Validator: (_) => true,
      domainValidator: (_) => true,
      revisionValidator: (_) => true,
    );
    expect(expired.type, ActionConfirmationResultType.expired);

    now = DateTime.utc(2026, 7, 24, 11);
    final stale =
        await coordinator.issue(_proposal(now, mutationId: 'mutation-2'));
    final oldSession = await coordinator.respond(
      response: _response(stale.confirmation, now, responseId: 'response-old'),
      currentSessionGeneration: 5,
      c3Validator: (_) => true,
      domainValidator: (_) => true,
      revisionValidator: (_) => true,
    );
    expect(oldSession.type, ActionConfirmationResultType.invalid);

    final changed =
        await coordinator.issue(_proposal(now, mutationId: 'mutation-3'));
    final staleAction = await coordinator.respond(
      response: ActionConfirmationResponse(
        responseId: 'response-changed',
        confirmationId: changed.confirmation.confirmationId,
        sessionGeneration: 4,
        respondedAt: now,
        choice: ActionConfirmationResponseChoice.accept,
        actionFingerprint: 'a3-other',
      ),
      currentSessionGeneration: 4,
      c3Validator: (_) => true,
      domainValidator: (_) => true,
      revisionValidator: (_) => true,
    );
    expect(staleAction.type, ActionConfirmationResultType.staleAction);

    mode = ActionAutonomyMode.paused;
    final blocked =
        await coordinator.issue(_proposal(now, mutationId: 'mutation-4'));
    expect(blocked.type, ActionConfirmationResultType.blockedByPolicy);
  });

  test('simultaneous responses allow one logical consumption', () async {
    final issued = await coordinator.issue(_proposal(now));
    final gate = Completer<void>();
    var validations = 0;
    Future<bool> validate(ActionConfirmation _) async {
      validations++;
      await gate.future;
      return true;
    }

    final first = coordinator.respond(
      response: _response(issued.confirmation, now, responseId: 'response-a'),
      currentSessionGeneration: 4,
      c3Validator: validate,
      domainValidator: (_) => true,
      revisionValidator: (_) => true,
    );
    final second = coordinator.respond(
      response: _response(issued.confirmation, now, responseId: 'response-b'),
      currentSessionGeneration: 4,
      c3Validator: validate,
      domainValidator: (_) => true,
      revisionValidator: (_) => true,
    );
    gate.complete();
    final results = await Future.wait([first, second]);
    expect(results.where((item) => item.dispatchAllowed), hasLength(1));
    expect(validations, 1);
  });

  test('non mergeable scopes and third party confirmations are refused',
      () async {
    expect(
      () => const ActionConfirmationRequirementAggregator().aggregate([
        _requirement(
          scope: ActionConfirmationScopeType.confirmSensitiveMutation,
          separate: true,
        ),
        _requirement(
          scope: ActionConfirmationScopeType.confirmIdentityLink,
          separate: true,
        ),
      ]),
      throwsFormatException,
    );
    expect(
      () => coordinator.issue(
        _proposal(
          now,
          actionType: ActionType.thirdPartyUnsupported,
          domain: ActionLedgerDomain.routine,
          scope: ActionConfirmationScope(
            type: ActionConfirmationScopeType.confirmThirdPartyAction,
            targetId: 'third-party',
            operation: 'unsupported',
            expectedRevision: 0,
            fields: const [],
          ),
        ),
      ),
      throwsFormatException,
    );
  });

  test('state machine refuses accepted without awaiting response', () {
    expect(
      ActionConfirmationStateMachine.allows(
        ActionConfirmationState.proposed,
        ActionConfirmationState.accepted,
      ),
      isFalse,
    );
    expect(
      ActionConfirmationStateMachine.allows(
        ActionConfirmationState.awaitingResponse,
        ActionConfirmationState.accepted,
      ),
      isTrue,
    );
    expect(
      ActionConfirmationStateMachine.allows(
        ActionConfirmationState.expired,
        ActionConfirmationState.accepted,
      ),
      isFalse,
    );
  });
}

ActionConfirmationProposal _proposal(
  DateTime now, {
  String mutationId = 'mutation-1',
  ActionType actionType = ActionType.createTask,
  ActionLedgerDomain domain = ActionLedgerDomain.task,
  ActionConfirmationScope? scope,
}) =>
    ActionConfirmationProposal(
      accountScopeId: 'scope-a',
      sessionGeneration: 4,
      actionPendingId: 'pending-1',
      actionType: actionType,
      actionDomain: domain,
      actionOrigin: ActionOrigin.explicitUserRequest,
      riskLevel: ActionRiskLevel.reversibleLowRisk,
      scope: scope ?? _scope(const []),
      requirements: [
        _requirement(
          scope:
              scope?.type ?? ActionConfirmationScopeType.executeExactMutation,
        ),
        ActionConfirmationRequirement(
          source: ActionConfirmationRequirementSource.autonomySuggestionsMode,
          code: 'suggestions_confirmation',
          scope:
              scope?.type ?? ActionConfirmationScopeType.executeExactMutation,
          requiresFreshConfirmation: true,
          requiresSeparateConfirmation: false,
          policyVersionObserved: 1,
        ),
      ],
      mutationId: mutationId,
      policyMode: ActionAutonomyMode.suggestions,
      policyVersion: 1,
      presentation: const ActionConfirmationPresentation(
        title: 'Confirmer la tâche',
        summary: 'Créer cette tâche.',
        consequence: 'La liste des tâches sera modifiée.',
        allowPostpone: true,
      ),
      provenance: 'test',
    );

ActionConfirmationScope _scope(List<ActionConfirmationField> fields) =>
    ActionConfirmationScope(
      type: ActionConfirmationScopeType.executeExactMutation,
      targetId: 'task-1',
      operation: 'createTask',
      expectedRevision: 0,
      fields: fields,
    );

ActionConfirmationResponse _response(
  ActionConfirmation confirmation,
  DateTime at, {
  String responseId = 'response-1',
}) =>
    ActionConfirmationResponse(
      responseId: responseId,
      confirmationId: confirmation.confirmationId,
      sessionGeneration: confirmation.sessionGeneration,
      respondedAt: at,
      choice: ActionConfirmationResponseChoice.accept,
      actionFingerprint: confirmation.actionFingerprint,
    );

ActionConfirmationRequirement _requirement({
  required ActionConfirmationScopeType scope,
  bool separate = false,
}) =>
    ActionConfirmationRequirement(
      source: ActionConfirmationRequirementSource.domainRequired,
      code: 'domain_confirmation',
      scope: scope,
      requiresFreshConfirmation: true,
      requiresSeparateConfirmation: separate,
      policyVersionObserved: 1,
    );
