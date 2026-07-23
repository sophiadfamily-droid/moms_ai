import '../models/conversation_context_envelope.dart';
import '../models/conversation_epistemic_models.dart';

final class ConversationGroundingValidationResult {
  const ConversationGroundingValidationResult._({
    required this.isValid,
    required this.code,
    required this.decision,
  });

  factory ConversationGroundingValidationResult.valid(
    ConversationClarificationDecision decision,
  ) =>
      ConversationGroundingValidationResult._(
        isValid: true,
        code: 'grounding_valid',
        decision: decision,
      );

  factory ConversationGroundingValidationResult.invalid(String code) =>
      ConversationGroundingValidationResult._(
        isValid: false,
        code: code,
        decision: ConversationClarificationDecision.cannotDetermine,
      );

  final bool isValid;
  final String code;
  final ConversationClarificationDecision decision;
}

abstract final class ConversationSafeResponseCatalog {
  static const insufficientInformation =
      'Je n’ai pas assez d’informations pour te répondre avec certitude.';
  static const contextUnavailable =
      'Je ne peux pas vérifier tes informations pour le moment.';
  static const conflicting =
      'Deux informations ne correspondent pas. Laquelle dois-je utiliser ?';
  static const generalCaveat =
      'Je peux te donner une réponse générale, sans confirmer qu’elle '
      'correspond à ta situation.';
  static const clarificationLimit =
      'Les informations restent insuffisantes. Tu peux reformuler ta demande.';
}

final class ConversationClarificationLedger {
  static const int maximumTurns = 3;

  const ConversationClarificationLedger({
    this.turns = 0,
    this.askedCodes = const {},
    this.sessionGeneration = 0,
  });

  final int turns;
  final Set<ConversationMissingInformationCode> askedCodes;
  final int sessionGeneration;

  bool canAsk(
    Iterable<ConversationMissingInformationCode> codes, {
    required int generation,
  }) =>
      generation == sessionGeneration &&
      turns < maximumTurns &&
      codes.any((code) => !askedCodes.contains(code));

  ConversationClarificationLedger record(
    Iterable<ConversationMissingInformationCode> codes,
  ) =>
      ConversationClarificationLedger(
        turns: turns + 1,
        askedCodes: {...askedCodes, ...codes},
        sessionGeneration: sessionGeneration,
      );
}

final class ConversationGroundingPolicy {
  static const int currentVersion = 1;

  const ConversationGroundingPolicy();

  ConversationClarificationDecision decide({
    required ConversationEpistemicState state,
    required List<ConversationMissingInformation> missingInformation,
    required List<ConversationContradiction> contradictions,
    required bool hasAction,
    required ConversationClarificationLedger ledger,
    required int sessionGeneration,
  }) {
    if (contradictions.any((item) => item.blocksAction) && hasAction) {
      return contradictions.any((item) => item.requiresClarification)
          ? ConversationClarificationDecision.clarify
          : ConversationClarificationDecision.refuseAction;
    }
    final requiredMissing =
        missingInformation.where((item) => item.isRequired).toList();
    if (requiredMissing.isNotEmpty) {
      final codes = requiredMissing.map((item) => item.code);
      if (requiredMissing.any((item) => item.canClarify) &&
          ledger.canAsk(codes, generation: sessionGeneration)) {
        return ConversationClarificationDecision.clarify;
      }
      return hasAction
          ? ConversationClarificationDecision.refuseAction
          : ConversationClarificationDecision.cannotDetermine;
    }
    return switch (state) {
      ConversationEpistemicState.grounded =>
        ConversationClarificationDecision.answer,
      ConversationEpistemicState.groundedPartial ||
      ConversationEpistemicState.uncertain ||
      ConversationEpistemicState.stale =>
        ConversationClarificationDecision.answerWithCaveat,
      ConversationEpistemicState.contextUnavailable =>
        ConversationClarificationDecision.retryContext,
      ConversationEpistemicState.conflicting =>
        ConversationClarificationDecision.clarify,
      ConversationEpistemicState.insufficientInformation =>
        ConversationClarificationDecision.cannotDetermine,
      ConversationEpistemicState.unsupported ||
      ConversationEpistemicState.invalid =>
        ConversationClarificationDecision.cannotDetermine,
    };
  }

  ConversationGroundingValidationResult validate({
    required ConversationEpistemicContract contract,
    required ConversationContextEnvelope envelope,
    required List<dynamic> actions,
    int sessionGeneration = 0,
  }) {
    if (contract.contextStateObserved != envelope.state) {
      return ConversationGroundingValidationResult.invalid(
        'context_state_mismatch',
      );
    }
    if (contract.responseKind == ConversationResponseKind.answerWithCaveat &&
        !{
          ConversationEpistemicState.groundedPartial,
          ConversationEpistemicState.uncertain,
          ConversationEpistemicState.stale,
        }.contains(contract.epistemicState)) {
      return ConversationGroundingValidationResult.invalid(
        'caveat_state_mismatch',
      );
    }
    if (contract.responseKind == ConversationResponseKind.contextUnavailable &&
        contract.epistemicState !=
            ConversationEpistemicState.contextUnavailable) {
      return ConversationGroundingValidationResult.invalid(
        'unavailable_state_mismatch',
      );
    }
    if (contract.clarification != null &&
        contract.clarification!.sessionGeneration != sessionGeneration) {
      return ConversationGroundingValidationResult.invalid(
        'clarification_session_mismatch',
      );
    }
    for (final reference in contract.groundingReferences) {
      if (!reference.existsIn(envelope)) {
        return ConversationGroundingValidationResult.invalid(
          'grounding_reference_missing',
        );
      }
      if (reference.freshness == 'stale' &&
          contract.epistemicState != ConversationEpistemicState.stale &&
          contract.epistemicState !=
              ConversationEpistemicState.groundedPartial) {
        return ConversationGroundingValidationResult.invalid(
          'stale_presented_as_current',
        );
      }
    }
    for (final claim in contract.personalClaims) {
      if (claim.sourceReferenceIndexes.any(
        (index) => index >= contract.groundingReferences.length,
      )) {
        return ConversationGroundingValidationResult.invalid(
          'claim_source_missing',
        );
      }
      if (claim.sourceReferenceIndexes.every(
        (index) =>
            contract.groundingReferences[index].sourceType ==
            ConversationGroundingSourceType.generalKnowledge,
      )) {
        return ConversationGroundingValidationResult.invalid(
          'personal_claim_uses_general_knowledge',
        );
      }
    }
    if (contract.epistemicState == ConversationEpistemicState.grounded &&
        contract.personalClaims.isNotEmpty &&
        contract.groundingReferences.isEmpty) {
      return ConversationGroundingValidationResult.invalid(
        'grounded_claim_without_source',
      );
    }
    if (contract.responseKind ==
            ConversationResponseKind.clarificationRequired &&
        (contract.clarification == null ||
            contract.missingInformation.isEmpty &&
                !contract.contradictions
                    .any((item) => item.requiresClarification))) {
      return ConversationGroundingValidationResult.invalid(
        'clarification_without_reason',
      );
    }
    if (contract.responseKind !=
            ConversationResponseKind.clarificationRequired &&
        contract.clarification != null) {
      return ConversationGroundingValidationResult.invalid(
        'unexpected_clarification',
      );
    }
    if ({
          ConversationResponseKind.cannotDetermine,
          ConversationResponseKind.contextUnavailable,
          ConversationResponseKind.safeFailure,
          ConversationResponseKind.unsupportedRequest,
          ConversationResponseKind.clarificationRequired,
        }.contains(contract.responseKind) &&
        actions.isNotEmpty) {
      return ConversationGroundingValidationResult.invalid(
        'non_action_response_contains_action',
      );
    }
    if (actions.any((action) => !_isCompleteAction(action))) {
      return ConversationGroundingValidationResult.invalid(
        'incomplete_action',
      );
    }
    if (actions.isNotEmpty &&
        !{
          ConversationResponseKind.actionProposal,
          ConversationResponseKind.confirmationRequired,
        }.contains(contract.responseKind)) {
      return ConversationGroundingValidationResult.invalid(
        'action_response_kind_mismatch',
      );
    }
    if (contract.responseKind == ConversationResponseKind.actionResult &&
        !contract.usedSourceTypes.contains(
          ConversationGroundingSourceType.confirmedActionResult,
        )) {
      return ConversationGroundingValidationResult.invalid(
        'action_result_without_result_source',
      );
    }
    final decision = decide(
      state: contract.epistemicState,
      missingInformation: contract.missingInformation,
      contradictions: contract.contradictions,
      hasAction: actions.isNotEmpty,
      ledger: ConversationClarificationLedger(
        sessionGeneration: sessionGeneration,
      ),
      sessionGeneration: sessionGeneration,
    );
    if (actions.isNotEmpty &&
        decision != ConversationClarificationDecision.answer) {
      return ConversationGroundingValidationResult.invalid(
        'action_blocked_by_epistemic_state',
      );
    }
    return ConversationGroundingValidationResult.valid(decision);
  }

  static bool _isCompleteAction(dynamic raw) {
    if (raw is! Map) return false;
    final action = Map<Object?, Object?>.from(raw);
    final type = action['type'];
    final title = action['title'];
    if (type == 'event_mutation') {
      return action['operation'] is String && action['target'] is Map;
    }
    if (!const {'event', 'task', 'shopping'}.contains(type) ||
        title is! String ||
        title.trim().isEmpty) {
      return false;
    }
    if (type != 'event') return true;
    return _nonEmpty(action['date']) &&
        _nonEmpty(action['time']) &&
        action['durationMinutes'] is int &&
        (action['durationMinutes'] as int) > 0 &&
        (!action.containsKey('usesSeparateTravelTimes') ||
            action['usesSeparateTravelTimes'] != true ||
            action['travelGoMinutes'] is int &&
                action['travelBackMinutes'] is int);
  }

  static bool _nonEmpty(Object? value) =>
      value is String && value.trim().isNotEmpty;
}
