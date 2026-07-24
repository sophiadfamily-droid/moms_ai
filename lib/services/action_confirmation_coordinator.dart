import 'dart:async';

import '../models/action_autonomy_policy.dart';
import '../models/action_confirmation.dart';
import '../models/action_ledger.dart';

typedef ActionConfirmationPolicyLoader = Future<ActionAutonomyPolicy>
    Function();
typedef ActionConfirmationValidator = FutureOr<bool> Function(
  ActionConfirmation confirmation,
);

final class ActionConfirmationProposal {
  const ActionConfirmationProposal({
    required this.accountScopeId,
    required this.sessionGeneration,
    this.requestId,
    required this.actionPendingId,
    this.ledgerEntryId,
    required this.actionType,
    required this.actionDomain,
    required this.actionOrigin,
    required this.riskLevel,
    required this.scope,
    required this.requirements,
    required this.mutationId,
    required this.policyMode,
    required this.policyVersion,
    required this.presentation,
    required this.provenance,
    this.validity,
  });

  final String accountScopeId;
  final int sessionGeneration;
  final String? requestId;
  final String actionPendingId;
  final String? ledgerEntryId;
  final ActionType actionType;
  final ActionLedgerDomain actionDomain;
  final ActionOrigin actionOrigin;
  final ActionRiskLevel riskLevel;
  final ActionConfirmationScope scope;
  final List<ActionConfirmationRequirement> requirements;
  final String mutationId;
  final ActionAutonomyMode policyMode;
  final int policyVersion;
  final ActionConfirmationPresentation presentation;
  final String provenance;
  final Duration? validity;
}

final class ActionConfirmationRequirementAggregator {
  const ActionConfirmationRequirementAggregator();

  List<ActionConfirmationRequirement> aggregate(
    Iterable<ActionConfirmationRequirement> requirements,
  ) {
    final result = <ActionConfirmationRequirement>[];
    for (final requirement in requirements) {
      requirement.validate();
      final duplicate = result.any(
        (item) =>
            item.scope == requirement.scope &&
            item.code == requirement.code &&
            item.policyVersionObserved == requirement.policyVersionObserved,
      );
      if (!duplicate) result.add(requirement);
    }
    if (result.isEmpty || result.length > 8) {
      throw const FormatException('invalid_confirmation_requirements');
    }
    final separateScopes = result
        .where((item) => item.requiresSeparateConfirmation)
        .map((item) => item.scope)
        .toSet();
    if (separateScopes.length > 1) {
      throw const FormatException('confirmation_requirements_not_mergeable');
    }
    result.sort((a, b) {
      final scope = a.scope.index.compareTo(b.scope.index);
      if (scope != 0) return scope;
      final source = a.source.index.compareTo(b.source.index);
      if (source != 0) return source;
      return a.code.compareTo(b.code);
    });
    return List.unmodifiable(result);
  }
}

final class ActionConfirmationCoordinator {
  ActionConfirmationCoordinator({
    required String Function() idGenerator,
    required ActionConfirmationPolicyLoader policyLoader,
    required String? Function() currentAccountScopeId,
    DateTime Function()? now,
    ActionConfirmationRequirementAggregator aggregator =
        const ActionConfirmationRequirementAggregator(),
  })  : _idGenerator = idGenerator,
        _policyLoader = policyLoader,
        _currentAccountScopeId = currentAccountScopeId,
        _now = now ?? DateTime.now,
        _aggregator = aggregator;

  static const Duration simpleMutationValidity = Duration(minutes: 15);
  static const Duration destructiveMutationValidity = Duration(minutes: 5);
  static const Duration conflictResolutionValidity = Duration(minutes: 5);
  static const Duration smartPlanningValidity = Duration(minutes: 10);

  final String Function() _idGenerator;
  final ActionConfirmationPolicyLoader _policyLoader;
  final String? Function() _currentAccountScopeId;
  final DateTime Function() _now;
  final ActionConfirmationRequirementAggregator _aggregator;
  final Map<String, ActionConfirmation> _confirmations = {};
  final Map<String, String> _responseReceipts = {};
  final Map<String, ActionConfirmationResult> _responseResults = {};

  Iterable<ActionConfirmation> get active => _confirmations.values.where(
        (item) =>
            item.state == ActionConfirmationState.awaitingResponse ||
            item.state == ActionConfirmationState.accepted,
      );

  ActionConfirmation? find(String confirmationId) =>
      _confirmations[confirmationId];

  Future<ActionConfirmationResult> issue(
    ActionConfirmationProposal proposal,
  ) async {
    final currentScope = _currentAccountScopeId();
    if (currentScope == null ||
        currentScope.trim().isEmpty ||
        currentScope != proposal.accountScopeId) {
      throw const FormatException('confirmation_account_mismatch');
    }
    if (proposal.actionDomain == ActionLedgerDomain.routine) {
      throw const FormatException('routine_confirmation_unsupported_before_y2');
    }
    if (proposal.actionType == ActionType.thirdPartyUnsupported ||
        proposal.scope.type ==
            ActionConfirmationScopeType.confirmThirdPartyAction ||
        proposal.scope.type == ActionConfirmationScopeType.customUnsupported) {
      throw const FormatException('third_party_confirmation_unsupported');
    }
    final policy = await _policyLoader();
    return issueWithPolicy(proposal, policy: policy);
  }

  ActionConfirmationResult issueWithPolicy(
    ActionConfirmationProposal proposal, {
    required ActionAutonomyPolicy policy,
  }) {
    final currentScope = _currentAccountScopeId();
    if (currentScope == null ||
        currentScope.trim().isEmpty ||
        currentScope != proposal.accountScopeId) {
      throw const FormatException('confirmation_account_mismatch');
    }
    if (proposal.actionDomain == ActionLedgerDomain.routine) {
      throw const FormatException('routine_confirmation_unsupported_before_y2');
    }
    if (proposal.actionType == ActionType.thirdPartyUnsupported ||
        proposal.scope.type ==
            ActionConfirmationScopeType.confirmThirdPartyAction ||
        proposal.scope.type == ActionConfirmationScopeType.customUnsupported) {
      throw const FormatException('third_party_confirmation_unsupported');
    }
    if (policy.accountScopeId != currentScope) {
      throw const FormatException('confirmation_policy_account_mismatch');
    }
    final requirements = _aggregator.aggregate(proposal.requirements);
    final fingerprint = ActionConfirmationFingerprint.compute(
      actionType: proposal.actionType,
      domain: proposal.actionDomain,
      riskLevel: proposal.riskLevel,
      scope: proposal.scope,
      mutationId: proposal.mutationId,
    );
    final existing = active.where(
      (item) =>
          item.accountScopeId == currentScope &&
          item.sessionGeneration == proposal.sessionGeneration &&
          item.actionFingerprint == fingerprint,
    );
    if (existing.isNotEmpty) {
      final confirmation = existing.first;
      return ActionConfirmationResult(
        type: ActionConfirmationResultType.awaitingResponse,
        confirmation: confirmation,
        reasonCode: 'confirmation_deduplicated',
        idempotent: true,
      );
    }
    _supersedeChangedAction(
      accountScopeId: currentScope,
      sessionGeneration: proposal.sessionGeneration,
      actionPendingId: proposal.actionPendingId,
      replacementId: null,
      replacementFingerprint: fingerprint,
    );
    final now = _now().toUtc();
    final confirmationId = _idGenerator();
    final confirmation = ActionConfirmation(
      confirmationId: confirmationId,
      accountScopeId: currentScope,
      sessionGeneration: proposal.sessionGeneration,
      requestId: proposal.requestId,
      actionPendingId: proposal.actionPendingId,
      ledgerEntryId: proposal.ledgerEntryId,
      actionType: proposal.actionType,
      actionDomain: proposal.actionDomain,
      actionOrigin: proposal.actionOrigin,
      riskLevel: proposal.riskLevel,
      confirmationScope: proposal.scope,
      requirements: requirements,
      actionFingerprint: fingerprint,
      mutationId: proposal.mutationId,
      policyModeAtCreation: policy.mode,
      policyVersionAtCreation: policy.schemaVersion,
      createdAt: now,
      expiresAt: now.add(proposal.validity ?? _validity(proposal)),
      state: policy.mode == ActionAutonomyMode.paused
          ? ActionConfirmationState.blockedByPolicy
          : ActionConfirmationState.proposed,
      userPresentation: proposal.presentation,
      provenance: proposal.provenance,
    );
    final ready = confirmation.state == ActionConfirmationState.proposed
        ? confirmation.transition(
            next: ActionConfirmationState.awaitingResponse,
            at: now,
          )
        : confirmation;
    _confirmations[confirmationId] = ready;
    return ActionConfirmationResult(
      type: ready.state == ActionConfirmationState.blockedByPolicy
          ? ActionConfirmationResultType.blockedByPolicy
          : ActionConfirmationResultType.awaitingResponse,
      confirmation: ready,
      reasonCode: ready.state == ActionConfirmationState.blockedByPolicy
          ? 'confirmation_blocked_paused'
          : 'confirmation_awaiting_response',
    );
  }

  Future<ActionConfirmationResult> respond({
    required ActionConfirmationResponse response,
    required int currentSessionGeneration,
    required ActionConfirmationValidator c3Validator,
    required ActionConfirmationValidator domainValidator,
    required ActionConfirmationValidator revisionValidator,
  }) async {
    response.validate();
    final priorReceipt = _responseReceipts[response.responseId];
    if (priorReceipt != null) {
      if (priorReceipt != response.receipt) {
        throw const FormatException('confirmation_response_id_conflict');
      }
      return ActionConfirmationResult(
        type: _responseResults[response.responseId]!.type,
        confirmation: _responseResults[response.responseId]!.confirmation,
        reasonCode: 'confirmation_response_idempotent',
        dispatchAllowed: false,
        idempotent: true,
      );
    }
    var confirmation = _confirmations[response.confirmationId];
    if (confirmation == null) {
      throw const FormatException('confirmation_not_found');
    }
    final currentScope = _currentAccountScopeId();
    if (currentScope == null ||
        currentScope != confirmation.accountScopeId ||
        response.sessionGeneration != currentSessionGeneration ||
        confirmation.sessionGeneration != currentSessionGeneration) {
      return _remember(
        response,
        ActionConfirmationResult(
          type: ActionConfirmationResultType.invalid,
          confirmation: confirmation,
          reasonCode: 'confirmation_stale_account_or_session',
        ),
      );
    }
    if (response.actionFingerprint != confirmation.actionFingerprint) {
      confirmation = _transitionIfAllowed(
        confirmation,
        ActionConfirmationState.staleAction,
        response.respondedAt,
      );
      return _remember(
        response,
        ActionConfirmationResult(
          type: ActionConfirmationResultType.staleAction,
          confirmation: confirmation,
          reasonCode: 'confirmation_fingerprint_mismatch',
        ),
      );
    }
    if (confirmation.isExpiredAt(response.respondedAt.toUtc())) {
      confirmation = _transitionIfAllowed(
        confirmation,
        ActionConfirmationState.expired,
        response.respondedAt,
      );
      return _remember(
        response,
        ActionConfirmationResult(
          type: ActionConfirmationResultType.expired,
          confirmation: confirmation,
          reasonCode: 'confirmation_expired',
        ),
      );
    }
    if (confirmation.state != ActionConfirmationState.awaitingResponse) {
      return _remember(
        response,
        ActionConfirmationResult(
          type: ActionConfirmationResultType.invalid,
          confirmation: confirmation,
          reasonCode: 'confirmation_already_handled',
        ),
      );
    }
    if (response.choice != ActionConfirmationResponseChoice.accept) {
      final state = switch (response.choice) {
        ActionConfirmationResponseChoice.reject =>
          ActionConfirmationState.rejected,
        ActionConfirmationResponseChoice.postpone =>
          confirmation.userPresentation.allowPostpone
              ? ActionConfirmationState.postponed
              : ActionConfirmationState.cancelled,
        ActionConfirmationResponseChoice.cancel =>
          ActionConfirmationState.cancelled,
        ActionConfirmationResponseChoice.accept =>
          throw const FormatException('unreachable_confirmation_choice'),
      };
      confirmation = confirmation.transition(
        next: state,
        at: response.respondedAt.toUtc(),
        responseId: response.responseId,
        incrementAttempt: true,
      );
      _confirmations[confirmation.confirmationId] = confirmation;
      return _remember(
        response,
        ActionConfirmationResult(
          type: switch (state) {
            ActionConfirmationState.rejected =>
              ActionConfirmationResultType.rejected,
            ActionConfirmationState.postponed =>
              ActionConfirmationResultType.postponed,
            _ => ActionConfirmationResultType.cancelled,
          },
          confirmation: confirmation,
          reasonCode: 'confirmation_${state.name}',
        ),
      );
    }

    confirmation = confirmation.transition(
      next: ActionConfirmationState.accepted,
      at: response.respondedAt.toUtc(),
      responseId: response.responseId,
      incrementAttempt: true,
    );
    _confirmations[confirmation.confirmationId] = confirmation;
    final policy = await _policyLoader();
    if (policy.accountScopeId != currentScope ||
        policy.mode == ActionAutonomyMode.paused) {
      confirmation = confirmation.transition(
        next: ActionConfirmationState.blockedByPolicy,
        at: response.respondedAt.toUtc(),
        responseId: response.responseId,
      );
      _confirmations[confirmation.confirmationId] = confirmation;
      return _remember(
        response,
        ActionConfirmationResult(
          type: ActionConfirmationResultType.blockedByPolicy,
          confirmation: confirmation,
          reasonCode: 'confirmation_policy_blocked',
        ),
      );
    }
    if (!await c3Validator(confirmation)) {
      return _block(
        response,
        confirmation,
        ActionConfirmationState.staleAction,
        ActionConfirmationResultType.staleAction,
        'confirmation_c3_revalidation_failed',
      );
    }
    if (!await domainValidator(confirmation)) {
      return _block(
        response,
        confirmation,
        ActionConfirmationState.blockedByConflict,
        ActionConfirmationResultType.blockedByConflict,
        'confirmation_domain_revalidation_failed',
      );
    }
    if (!await revisionValidator(confirmation)) {
      return _block(
        response,
        confirmation,
        ActionConfirmationState.staleAction,
        ActionConfirmationResultType.staleAction,
        'confirmation_revision_changed',
      );
    }
    confirmation = confirmation.transition(
      next: ActionConfirmationState.consumed,
      at: response.respondedAt.toUtc(),
      responseId: response.responseId,
    );
    _confirmations[confirmation.confirmationId] = confirmation;
    return _remember(
      response,
      ActionConfirmationResult(
        type: ActionConfirmationResultType.consumed,
        confirmation: confirmation,
        reasonCode: 'confirmation_consumed',
        dispatchAllowed: true,
      ),
    );
  }

  ActionConfirmationResult complete(
    String confirmationId, {
    required DateTime completedAt,
  }) {
    final current = _confirmations[confirmationId];
    if (current == null) throw const FormatException('confirmation_not_found');
    if (current.state == ActionConfirmationState.completed) {
      return ActionConfirmationResult(
        type: ActionConfirmationResultType.completed,
        confirmation: current,
        reasonCode: 'confirmation_completion_idempotent',
        idempotent: true,
      );
    }
    final completed = current.transition(
      next: ActionConfirmationState.completed,
      at: completedAt.toUtc(),
    );
    _confirmations[confirmationId] = completed;
    return ActionConfirmationResult(
      type: ActionConfirmationResultType.completed,
      confirmation: completed,
      reasonCode: 'confirmation_completed_after_domain_result',
    );
  }

  void invalidateSession(int sessionGeneration) {
    final now = _now().toUtc();
    for (final confirmation in [...active]) {
      if (confirmation.sessionGeneration == sessionGeneration) continue;
      final invalid = _transitionIfAllowed(
        confirmation,
        ActionConfirmationState.superseded,
        now,
      );
      _confirmations[confirmation.confirmationId] = invalid;
    }
  }

  Future<ActionConfirmationResult> _block(
    ActionConfirmationResponse response,
    ActionConfirmation confirmation,
    ActionConfirmationState state,
    ActionConfirmationResultType type,
    String code,
  ) async {
    final blocked = confirmation.transition(
      next: state,
      at: response.respondedAt.toUtc(),
      responseId: response.responseId,
    );
    _confirmations[blocked.confirmationId] = blocked;
    return _remember(
      response,
      ActionConfirmationResult(
        type: type,
        confirmation: blocked,
        reasonCode: code,
      ),
    );
  }

  ActionConfirmationResult _remember(
    ActionConfirmationResponse response,
    ActionConfirmationResult result,
  ) {
    _responseReceipts[response.responseId] = response.receipt;
    _responseResults[response.responseId] = result;
    return result;
  }

  ActionConfirmation _transitionIfAllowed(
    ActionConfirmation confirmation,
    ActionConfirmationState state,
    DateTime at,
  ) {
    if (!ActionConfirmationStateMachine.allows(confirmation.state, state)) {
      return confirmation;
    }
    final next = confirmation.transition(next: state, at: at.toUtc());
    _confirmations[next.confirmationId] = next;
    return next;
  }

  void _supersedeChangedAction({
    required String accountScopeId,
    required int sessionGeneration,
    required String actionPendingId,
    required String? replacementId,
    required String replacementFingerprint,
  }) {
    final now = _now().toUtc();
    for (final current in [...active]) {
      if (current.accountScopeId != accountScopeId ||
          current.sessionGeneration != sessionGeneration ||
          current.actionPendingId != actionPendingId ||
          current.actionFingerprint == replacementFingerprint) {
        continue;
      }
      final next = current.transition(
        next: ActionConfirmationState.superseded,
        at: now,
        supersededByConfirmationId: replacementId,
      );
      _confirmations[current.confirmationId] = next;
    }
  }

  Duration _validity(ActionConfirmationProposal proposal) =>
      switch (proposal.scope.type) {
        ActionConfirmationScopeType.confirmDestructiveMutation =>
          destructiveMutationValidity,
        ActionConfirmationScopeType.confirmConflictResolution =>
          conflictResolutionValidity,
        ActionConfirmationScopeType.confirmSmartPlanningReservation =>
          smartPlanningValidity,
        _ => simpleMutationValidity,
      };
}
