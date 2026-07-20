import '../models/conversation_models.dart';
import '../models/event_model.dart';
import 'chat_backend_client.dart';
import 'conversation_context_service.dart';
import 'zelia_action_guard_service.dart';
import 'zelia_response_builder.dart';

typedef ConversationActionExecutor = Future<ConversationActionOutcome> Function(
  Map<String, dynamic> action,
);

typedef PendingEventExecutor = Future<String> Function(EventModel event);

class ConversationCoordinator {
  final ChatBackendClient backend;
  final ConversationContextProvider contextProvider;

  ConversationState _state = const ConversationState();
  bool _isSending = false;
  bool _isResolvingPendingAction = false;

  ConversationCoordinator({
    required this.backend,
    required this.contextProvider,
  });

  ConversationState get state => _state;

  void setPendingEventConfirmation(EventModel? event) {
    if (event == null) {
      _state = _state.copyWith(
        phase: ConversationPhase.idle,
        clearPendingAction: true,
      );
      return;
    }

    _state = _state.copyWith(
      phase: ConversationPhase.awaitingActionConfirmation,
      pendingAction: PendingConversationAction.eventConfirmation(event),
    );
  }

  Future<PendingConversationResolution?> resolvePendingEventConfirmation({
    required String answer,
    required bool Function(String value) isPositiveAnswer,
    required bool Function(String value) isNegativeAnswer,
    required String Function(EventModel event) cancellationMessage,
    required String Function() expectedAnswerMessage,
    required PendingEventExecutor execute,
  }) async {
    final pending = _state.pendingAction;
    if (pending == null) return null;

    if (isNegativeAnswer(answer)) {
      _state = _state.copyWith(
        phase: ConversationPhase.idle,
        clearPendingAction: true,
      );
      return PendingConversationResolution(cancellationMessage(pending.event));
    }

    if (!isPositiveAnswer(answer)) {
      return PendingConversationResolution(expectedAnswerMessage());
    }

    if (_isResolvingPendingAction) return null;
    _isResolvingPendingAction = true;
    _state = _state.copyWith(phase: ConversationPhase.executingAction);

    try {
      final message = await execute(pending.event);
      _state = _state.copyWith(
        phase: ConversationPhase.idle,
        clearPendingAction: true,
      );
      return PendingConversationResolution(message);
    } catch (_) {
      _state = _state.copyWith(
        phase: ConversationPhase.awaitingActionConfirmation,
      );
      rethrow;
    } finally {
      _isResolvingPendingAction = false;
    }
  }

  Future<ConversationOutcome?> send({
    required ConversationInput input,
    required ConversationActionExecutor executeAction,
  }) async {
    if (_isSending) return null;
    _isSending = true;
    _state = _state.copyWith(
      phase: ConversationPhase.sending,
      currentInstruction: input.message,
    );

    try {
      final request = await contextProvider.buildRequest(
        message: input.message,
        profile: input.profile,
      );
      final response = await backend.send(request);
      var reply = response.reply;
      final actionMessages = <String>[];
      final shoppingTitles = <String>[];
      final taskTitles = <String>[];
      final eventTitles = <String>[];
      String? planningTitle;

      for (final rawAction in response.actions) {
        final guarded = ZeliaActionGuardService.guard(rawAction);
        if (!guarded.isAccepted || guarded.action == null) continue;

        final action = guarded.action!;
        final type = action['type']?.toString() ?? '';
        final title = action['title']?.toString() ?? '';
        if (type == 'shopping' && title.isNotEmpty) shoppingTitles.add(title);
        if (type == 'task' && title.isNotEmpty) taskTitles.add(title);
        if (type == 'event' && title.isNotEmpty) eventTitles.add(title);

        final outcome = await executeAction(action);
        if (outcome.message.isNotEmpty) actionMessages.add(outcome.message);
        planningTitle = outcome.planningTitle ?? planningTitle;
      }

      for (final memory in response.memories) {
        await contextProvider.saveResponseMemory(memory);
      }

      if (actionMessages.isNotEmpty) {
        reply = actionMessages.join('\n\n');
      } else if (response.actions.isNotEmpty) {
        reply = ZeliaResponseBuilder.buildGroupedActionReply(
          shoppingTitles: shoppingTitles,
          taskTitles: taskTitles,
          eventTitles: eventTitles,
          planningTitle: planningTitle,
        );
      }

      return ConversationOutcome(reply: reply, request: request);
    } finally {
      _isSending = false;
      _state = _state.copyWith(
        phase: _state.pendingAction == null
            ? ConversationPhase.idle
            : ConversationPhase.awaitingActionConfirmation,
      );
    }
  }
}
