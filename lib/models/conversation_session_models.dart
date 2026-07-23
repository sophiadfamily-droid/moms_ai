import 'dart:collection';

enum ConversationSessionPhase {
  initial,
  ready,
  loadingContext,
  sending,
  validatingResponse,
  executingAction,
  awaitingClarification,
  awaitingConfirmation,
  pendingSync,
  recoverableError,
  blockingError,
  offline,
  cancelled,
  disposed,
}

enum ConversationMessageRole { user, assistant }

enum ConversationMessageStatus { visible, sending, sent, failed, pending }

enum ConversationUiEffectType {
  scrollToLatest,
  focusInput,
  showConfirmation,
  showClarification,
  showRecoverableError,
}

final class ConversationVisibleMessage {
  static const int maximumLength = 8000;

  ConversationVisibleMessage({
    required this.id,
    required this.role,
    required String text,
    required this.createdAt,
    this.status = ConversationMessageStatus.visible,
    this.presentationType = 'message',
    this.pendingReferenceId,
  }) : text = text.trim() {
    if (id.trim().isEmpty ||
        this.text.isEmpty ||
        this.text.length > maximumLength ||
        presentationType.trim().isEmpty) {
      throw const FormatException('invalid_conversation_message');
    }
  }

  final String id;
  final ConversationMessageRole role;
  final String text;
  final DateTime createdAt;
  final ConversationMessageStatus status;
  final String presentationType;
  final String? pendingReferenceId;
}

final class ConversationUiEffect {
  ConversationUiEffect({
    required this.id,
    required this.type,
    required this.sessionGeneration,
    this.message,
  }) {
    if (id.trim().isEmpty ||
        sessionGeneration < 0 ||
        message != null && message!.trim().isEmpty) {
      throw const FormatException('invalid_conversation_ui_effect');
    }
  }

  final String id;
  final ConversationUiEffectType type;
  final int sessionGeneration;
  final String? message;
}

final class ConversationSessionState {
  static const int currentSchemaVersion = 1;

  ConversationSessionState({
    this.schemaVersion = currentSchemaVersion,
    required this.sessionId,
    required this.sessionGeneration,
    required this.phase,
    required List<ConversationVisibleMessage> messages,
    required List<ConversationUiEffect> effects,
    this.currentRequestId,
    this.retryAvailable = false,
    this.errorMessage,
    this.hasPendingAction = false,
  })  : messages = UnmodifiableListView(messages),
        effects = UnmodifiableListView(effects) {
    if (schemaVersion != currentSchemaVersion ||
        sessionId.trim().isEmpty ||
        sessionGeneration < 0 ||
        currentRequestId != null && currentRequestId!.trim().isEmpty ||
        errorMessage != null && errorMessage!.trim().isEmpty) {
      throw const FormatException('invalid_conversation_session_state');
    }
  }

  final int schemaVersion;
  final String sessionId;
  final int sessionGeneration;
  final ConversationSessionPhase phase;
  final List<ConversationVisibleMessage> messages;
  final List<ConversationUiEffect> effects;
  final String? currentRequestId;
  final bool retryAvailable;
  final String? errorMessage;
  final bool hasPendingAction;

  bool get isBusy => const {
        ConversationSessionPhase.loadingContext,
        ConversationSessionPhase.sending,
        ConversationSessionPhase.validatingResponse,
        ConversationSessionPhase.executingAction,
      }.contains(phase);

  ConversationSessionState copyWith({
    int? sessionGeneration,
    ConversationSessionPhase? phase,
    List<ConversationVisibleMessage>? messages,
    List<ConversationUiEffect>? effects,
    String? currentRequestId,
    bool clearCurrentRequest = false,
    bool? retryAvailable,
    String? errorMessage,
    bool clearError = false,
    bool? hasPendingAction,
  }) =>
      ConversationSessionState(
        sessionId: sessionId,
        sessionGeneration: sessionGeneration ?? this.sessionGeneration,
        phase: phase ?? this.phase,
        messages: messages ?? this.messages,
        effects: effects ?? this.effects,
        currentRequestId: clearCurrentRequest
            ? null
            : currentRequestId ?? this.currentRequestId,
        retryAvailable: retryAvailable ?? this.retryAvailable,
        errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
        hasPendingAction: hasPendingAction ?? this.hasPendingAction,
      );
}

sealed class ConversationUiIntent {
  const ConversationUiIntent();
}

final class SubmitConversationText extends ConversationUiIntent {
  SubmitConversationText(String text) : text = text.trim() {
    if (this.text.isEmpty ||
        this.text.length > ConversationVisibleMessage.maximumLength) {
      throw const FormatException('invalid_conversation_submission');
    }
  }

  final String text;
}

final class RetryConversationRequest extends ConversationUiIntent {
  const RetryConversationRequest();
}

final class AnswerConversationClarification extends ConversationUiIntent {
  AnswerConversationClarification(String answer) : answer = answer.trim() {
    if (this.answer.isEmpty) {
      throw const FormatException('invalid_clarification_answer');
    }
  }

  final String answer;
}

final class ConfirmPendingConversationAction extends ConversationUiIntent {
  const ConfirmPendingConversationAction();
}

final class RejectPendingConversationAction extends ConversationUiIntent {
  const RejectPendingConversationAction();
}

final class PostponePendingConversationAction extends ConversationUiIntent {
  const PostponePendingConversationAction();
}

final class CancelConversationRequest extends ConversationUiIntent {
  const CancelConversationRequest();
}

final class DismissConversationError extends ConversationUiIntent {
  const DismissConversationError();
}

final class ConsumeConversationEffect extends ConversationUiIntent {
  ConsumeConversationEffect(String effectId) : effectId = effectId.trim() {
    if (this.effectId.isEmpty) {
      throw const FormatException('invalid_conversation_effect_id');
    }
  }

  final String effectId;
}
