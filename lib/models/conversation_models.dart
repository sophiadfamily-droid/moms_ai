import 'chat_backend_request.dart';
import 'event_model.dart';
import 'user_profile.dart';

enum ConversationPhase {
  idle,
  sending,
  awaitingActionConfirmation,
  executingAction,
}

class ConversationInput {
  final String message;
  final UserProfile profile;

  const ConversationInput({
    required this.message,
    required this.profile,
  });
}

class PendingConversationAction {
  final EventModel event;

  const PendingConversationAction.eventConfirmation(this.event);
}

class ConversationState {
  final ConversationPhase phase;
  final String currentInstruction;
  final PendingConversationAction? pendingAction;

  const ConversationState({
    this.phase = ConversationPhase.idle,
    this.currentInstruction = '',
    this.pendingAction,
  });

  ConversationState copyWith({
    ConversationPhase? phase,
    String? currentInstruction,
    PendingConversationAction? pendingAction,
    bool clearPendingAction = false,
  }) {
    return ConversationState(
      phase: phase ?? this.phase,
      currentInstruction: currentInstruction ?? this.currentInstruction,
      pendingAction:
          clearPendingAction ? null : pendingAction ?? this.pendingAction,
    );
  }
}

class ConversationActionOutcome {
  final String message;
  final String? planningTitle;

  const ConversationActionOutcome({
    this.message = '',
    this.planningTitle,
  });
}

class ConversationOutcome {
  final String reply;
  final ChatBackendRequest request;

  const ConversationOutcome({
    required this.reply,
    required this.request,
  });
}

class PendingConversationResolution {
  final String message;

  const PendingConversationResolution(this.message);
}
