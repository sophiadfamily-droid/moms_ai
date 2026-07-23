import '../models/action_autonomy_policy.dart';

final class ActionAutonomyActionRegistry {
  const ActionAutonomyActionRegistry();

  ActionRiskLevel riskFor(ActionType type) {
    if (_readOnly.contains(type)) return ActionRiskLevel.readOnly;
    if (_destructive.contains(type)) return ActionRiskLevel.destructive;
    if (_sensitive.contains(type)) return ActionRiskLevel.sensitiveMutation;
    if (type == ActionType.thirdPartyUnsupported) {
      return ActionRiskLevel.thirdParty;
    }
    if (_lowRisk.contains(type)) return ActionRiskLevel.reversibleLowRisk;
    return ActionRiskLevel.mutation;
  }

  bool isProposal(ActionType type) => _proposals.contains(type);

  static const _readOnly = {
    ActionType.answerGeneralQuestion,
    ActionType.readAgenda,
    ActionType.readTasks,
    ActionType.readShopping,
    ActionType.readRoutines,
    ActionType.readMemory,
    ActionType.explainPriority,
    ActionType.inspectProfile,
  };
  static const _proposals = {
    ActionType.proposeEvent,
    ActionType.proposeTask,
    ActionType.proposeShoppingItem,
    ActionType.proposeRoutine,
    ActionType.proposeMemory,
    ActionType.proposePerson,
  };
  static const _lowRisk = {
    ActionType.createTask,
    ActionType.addShoppingItem,
  };
  static const _sensitive = {
    ActionType.confirmMemory,
    ActionType.correctMemory,
    ActionType.createPerson,
    ActionType.updatePerson,
    ActionType.createIdentity,
    ActionType.linkIdentity,
    ActionType.modifyRelationship,
    ActionType.modifyHousehold,
    ActionType.modifyResponsibility,
    ActionType.modifyParticipant,
  };
  static const _destructive = {
    ActionType.deleteEvent,
    ActionType.deleteTask,
    ActionType.removeShoppingItem,
    ActionType.clearShoppingList,
    ActionType.archiveRoutine,
    ActionType.deleteRoutine,
    ActionType.archiveMemory,
    ActionType.deleteMemory,
    ActionType.deleteAllMemory,
    ActionType.archivePerson,
  };
}

final class ActionAutonomyPolicyEngine {
  static const int matrixVersion = 1;

  const ActionAutonomyPolicyEngine({
    this.registry = const ActionAutonomyActionRegistry(),
  });

  final ActionAutonomyActionRegistry registry;

  ActionAuthorizationDecision evaluate({
    required ActionAutonomyPolicy policy,
    required ActionAuthorizationRequest request,
    required DateTime evaluatedAt,
  }) {
    policy.validate();
    if (request.schemaVersion !=
            ActionAuthorizationRequest.currentSchemaVersion ||
        request.sessionGeneration < 0) {
      return _decision(
        request,
        policy,
        evaluatedAt,
        ActionAuthorizationDecisionType.invalidRequest,
        'invalid_request',
      );
    }
    if (request.policyVersionObserved != policy.schemaVersion) {
      return _decision(
        request,
        policy,
        evaluatedAt,
        ActionAuthorizationDecisionType.blockedStalePolicy,
        'stale_policy',
      );
    }
    if (request.origin == ActionOrigin.systemProactive ||
        request.origin == ActionOrigin.externalTrigger ||
        request.origin == ActionOrigin.unknown) {
      return _decision(
        request,
        policy,
        evaluatedAt,
        ActionAuthorizationDecisionType.blockedUnknownOrigin,
        'origin_blocked',
      );
    }
    if (request.actionType == ActionType.thirdPartyUnsupported) {
      return _decision(
        request,
        policy,
        evaluatedAt,
        ActionAuthorizationDecisionType.blockedUnsupported,
        'third_party_unsupported',
      );
    }
    if (!request.isGrounded) {
      return _decision(
        request,
        policy,
        evaluatedAt,
        ActionAuthorizationDecisionType.blockedUngrounded,
        'grounding_required',
      );
    }
    if (!request.isComplete) {
      return _decision(
        request,
        policy,
        evaluatedAt,
        ActionAuthorizationDecisionType.blockedIncomplete,
        'action_incomplete',
      );
    }
    if (!request.domainPolicyAllows) {
      return _decision(
        request,
        policy,
        evaluatedAt,
        ActionAuthorizationDecisionType.blockedDomainPolicy,
        'domain_policy_blocked',
      );
    }
    if (request.hasBlockingConflict) {
      return _decision(
        request,
        policy,
        evaluatedAt,
        ActionAuthorizationDecisionType.blockedConflict,
        'blocking_conflict',
      );
    }
    if (request.isAlreadyExecuted) {
      return _decision(
        request,
        policy,
        evaluatedAt,
        ActionAuthorizationDecisionType.blockedAlreadyExecuted,
        'already_executed',
      );
    }

    final risk = registry.riskFor(request.actionType);
    if (risk == ActionRiskLevel.readOnly) {
      return _decision(
        request,
        policy,
        evaluatedAt,
        ActionAuthorizationDecisionType.allowReadOnly,
        'read_only_allowed',
        mayExecute: true,
      );
    }
    if (policy.mode == ActionAutonomyMode.paused) {
      return _decision(
        request,
        policy,
        evaluatedAt,
        ActionAuthorizationDecisionType.blockedPaused,
        'actions_paused',
        blockingState: ActionPendingPolicyState.blockedByPolicy,
      );
    }
    if (registry.isProposal(request.actionType)) {
      return _decision(
        request,
        policy,
        evaluatedAt,
        ActionAuthorizationDecisionType.allowProposal,
        'proposal_allowed',
        mayCreateProposal: true,
      );
    }

    final alwaysConfirm = risk == ActionRiskLevel.sensitiveMutation ||
        risk == ActionRiskLevel.destructive ||
        request.domainConfirmationRequired;
    final suggestionsConfirmation =
        policy.mode == ActionAutonomyMode.suggestions;
    final confirmationIsValid = request.hasFreshExplicitConfirmation &&
        request.origin == ActionOrigin.explicitUserConfirmation;
    if ((alwaysConfirm || suggestionsConfirmation) && !confirmationIsValid) {
      return _decision(
        request,
        policy,
        evaluatedAt,
        ActionAuthorizationDecisionType.requireExplicitConfirmation,
        'explicit_confirmation_required',
        requiresConfirmation: true,
        mayCreateProposal: true,
      );
    }
    return _decision(
      request,
      policy,
      evaluatedAt,
      ActionAuthorizationDecisionType.allowExecution,
      'execution_allowed',
      mayExecute: true,
    );
  }

  ActionAuthorizationDecision _decision(
    ActionAuthorizationRequest request,
    ActionAutonomyPolicy policy,
    DateTime evaluatedAt,
    ActionAuthorizationDecisionType type,
    String code, {
    bool requiresConfirmation = false,
    bool mayCreateProposal = false,
    bool mayExecute = false,
    ActionPendingPolicyState? blockingState,
  }) =>
      ActionAuthorizationDecision(
        decision: type,
        actionType: request.actionType,
        modeObserved: policy.mode,
        reasonCode: code,
        requiresConfirmation: requiresConfirmation,
        mayCreateProposal: mayCreateProposal,
        mayExecute: mayExecute,
        revalidationRequired: !mayExecute,
        blockingState: blockingState,
        policyVersion: policy.schemaVersion,
        evaluatedAt: evaluatedAt.toUtc(),
      );
}
