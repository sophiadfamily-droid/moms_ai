import 'chat_backend_request.dart';
import 'event_model.dart';
import 'memory_lifecycle_state.dart';
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

enum PendingConversationActionType { eventConfirmation, memoryConfirmation }

class PendingConversationAction {
  final PendingConversationActionType type;
  final EventModel? _event;
  final String? proposalId;
  final MemoryLifecycleAction? expectedMemoryAction;
  final DateTime? createdAt;

  const PendingConversationAction.eventConfirmation(EventModel this._event)
      : type = PendingConversationActionType.eventConfirmation,
        proposalId = null,
        expectedMemoryAction = null,
        createdAt = null;

  const PendingConversationAction.memoryConfirmation({
    required this.proposalId,
    required this.createdAt,
    required this.expectedMemoryAction,
  })  : type = PendingConversationActionType.memoryConfirmation,
        _event = null;

  EventModel get event => _event!;
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
