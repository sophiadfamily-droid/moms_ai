import 'dart:collection';

import '../action_autonomy_policy.dart';
import '../conversation_models.dart';
import '../life_context/life_context_projection.dart';

enum ReasoningPurpose {
  organizeAcrossDomains,
  explainTradeoffs,
  exploreScenario,
}

enum ReasoningInputState { complete, partial }

final class ReasoningInputException implements Exception {
  const ReasoningInputException(this.code);

  final String code;

  @override
  String toString() => 'ReasoningInputException($code)';
}

/// A content-free projection of the active conversation workflow.
///
/// It deliberately excludes the raw instruction, visible messages and every
/// domain payload. The Reasoning boundary may observe workflow state, but it
/// cannot acquire mutation authority or reconstruct an action from it.
final class ReasoningConversationState {
  const ReasoningConversationState({
    required this.phase,
    required this.hasCurrentInstruction,
    required this.pendingActionType,
    required this.pendingActionRisk,
    required this.hasCanonicalConfirmation,
    required this.sessionGeneration,
  });

  factory ReasoningConversationState.fromConversationState(
    ConversationState state, {
    required int sessionGeneration,
  }) {
    if (sessionGeneration < 0) {
      throw const ReasoningInputException('invalid_session_generation');
    }
    final pending = state.pendingAction;
    return ReasoningConversationState(
      phase: state.phase,
      hasCurrentInstruction: state.currentInstruction.trim().isNotEmpty,
      pendingActionType: pending?.type,
      pendingActionRisk: pending?.autonomyMetadata.riskLevel,
      hasCanonicalConfirmation: pending?.canonicalConfirmation != null,
      sessionGeneration: sessionGeneration,
    );
  }

  final ConversationPhase phase;
  final bool hasCurrentInstruction;
  final PendingConversationActionType? pendingActionType;
  final ActionRiskLevel? pendingActionRisk;
  final bool hasCanonicalConfirmation;
  final int sessionGeneration;

  Map<String, Object?> toJson() => {
        'phase': phase.name,
        'hasCurrentInstruction': hasCurrentInstruction,
        'pendingActionType': pendingActionType?.name,
        'pendingActionRisk': pendingActionRisk?.name,
        'hasCanonicalConfirmation': hasCanonicalConfirmation,
        'sessionGeneration': sessionGeneration,
      };
}

/// V1-RE.1 read-only input contract for future cross-domain reasoning.
final class ReasoningInput {
  static const int currentSchemaVersion = 1;

  ReasoningInput({
    this.schemaVersion = currentSchemaVersion,
    required this.inputId,
    required this.accountScopeId,
    required this.purpose,
    required this.generatedAt,
    required this.state,
    required this.conversation,
    required this.lifeContext,
    List<String> warningCodes = const [],
  }) : warningCodes = UnmodifiableListView(
          List<String>.of(warningCodes)..sort(),
        ) {
    if (schemaVersion != currentSchemaVersion) {
      throw const ReasoningInputException('unsupported_reasoning_version');
    }
    if (inputId.trim().isEmpty || accountScopeId.trim().isEmpty) {
      throw const ReasoningInputException('invalid_reasoning_identity');
    }
    if (lifeContext.accountScopeId != accountScopeId) {
      throw const ReasoningInputException('reasoning_account_scope_mismatch');
    }
    if (lifeContext.purpose != LifeContextConsumerPurpose.conversation) {
      throw const ReasoningInputException(
        'reasoning_projection_purpose_mismatch',
      );
    }
    if (generatedAt.isBefore(lifeContext.generatedAt)) {
      throw const ReasoningInputException('reasoning_time_inversion');
    }
    if (warningCodes.length > 20 ||
        warningCodes.toSet().length != warningCodes.length ||
        warningCodes.any(
          (code) =>
              code.isEmpty ||
              code.length > 80 ||
              !RegExp(r'^[a-z0-9_]+$').hasMatch(code),
        )) {
      throw const ReasoningInputException('invalid_reasoning_warnings');
    }
    if (state == ReasoningInputState.complete &&
        (lifeContext.state != LifeContextProjectionState.complete ||
            warningCodes.isNotEmpty)) {
      throw const ReasoningInputException('invalid_complete_reasoning_input');
    }
  }

  final int schemaVersion;
  final String inputId;
  final String accountScopeId;
  final ReasoningPurpose purpose;
  final DateTime generatedAt;
  final ReasoningInputState state;
  final ReasoningConversationState conversation;
  final LifeContextProjection lifeContext;
  final List<String> warningCodes;

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'inputId': inputId,
        'accountScopeId': accountScopeId,
        'purpose': purpose.name,
        'generatedAt': generatedAt.toUtc().toIso8601String(),
        'state': state.name,
        'conversation': conversation.toJson(),
        'lifeContext': lifeContext.toJson(),
        'warningCodes': warningCodes,
      };
}
