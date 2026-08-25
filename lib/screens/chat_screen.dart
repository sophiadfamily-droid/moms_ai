import 'package:flutter/material.dart';

import '../models/conversation_session_models.dart';
import '../models/user_profile.dart';
import '../models/voice_recognition.dart';
import '../services/chat_backend_client.dart';
import '../services/conversation_context_service.dart';
import '../services/conversation_session_controller.dart';
import '../services/identity/identity_production_services.dart';
import '../services/priority/proactive_interaction_registry.dart';
import '../services/voice_recognition_coordinator.dart';
import '../widgets/voice_input_control.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.profile,
    this.initialAssistantMessage,
    this.backendClient,
    this.conversationContextProvider,
    this.identityServices,
    this.sessionController,
    this.voiceCoordinator,
    this.proactiveInteractionRegistry,
  });

  final UserProfile profile;
  final String? initialAssistantMessage;
  final ChatBackendClient? backendClient;
  final ConversationContextProvider? conversationContextProvider;
  final IdentityProductionServices? identityServices;
  final ConversationSessionController? sessionController;
  final VoiceRecognitionCoordinator? voiceCoordinator;
  final ProactiveInteractionRegistry? proactiveInteractionRegistry;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  late final ConversationSessionController _sessionController;
  late final bool _ownsSessionController;
  late final VoiceRecognitionCoordinator _voiceCoordinator;
  late final bool _ownsVoiceCoordinator;

  @override
  void initState() {
    super.initState();
    _ownsSessionController = widget.sessionController == null;
    _sessionController = widget.sessionController ??
        ConversationSessionController.production(
          profile: widget.profile,
          backendClient: widget.backendClient,
          contextProvider: widget.conversationContextProvider,
          identityServices: widget.identityServices,
          proactiveInteractionRegistry: widget.proactiveInteractionRegistry,
          initialAssistantMessage: widget.initialAssistantMessage,
        );
    _ownsVoiceCoordinator = widget.voiceCoordinator == null;
    _voiceCoordinator =
        widget.voiceCoordinator ?? VoiceRecognitionCoordinator.production();
    _sessionController.addListener(_onSessionChanged);
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile != widget.profile) {
      _voiceCoordinator.invalidateForContextChange(
        VoiceInterruptionReason.accountChanged,
      );
    }
    if (oldWidget.initialAssistantMessage != widget.initialAssistantMessage) {
      _sessionController
          .addInitialAssistantMessage(widget.initialAssistantMessage);
    }
  }

  void _onSessionChanged() {
    if (!mounted) return;
    setState(() {});
    for (final effect in _sessionController.state.effects) {
      if (effect.sessionGeneration !=
          _sessionController.state.sessionGeneration) {
        _sessionController.dispatch(ConsumeConversationEffect(effect.id));
        continue;
      }
      if (effect.type == ConversationUiEffectType.scrollToLatest) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToLatest());
      }
      _sessionController.dispatch(ConsumeConversationEffect(effect.id));
    }
  }

  Future<void> _submit() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _sessionController.state.isBusy) return;
    _textController.clear();
    await _voiceCoordinator.stop();
    await _sessionController.dispatch(SubmitConversationText(text));
  }

  void _useVoiceTranscript(String text) {
    if (!mounted) return;
    final transcript = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (transcript.isEmpty) return;
    final current = _textController.text;
    final selection = _textController.selection;
    final reliableCursor = selection.isValid &&
        selection.isCollapsed &&
        selection.start >= 0 &&
        selection.start <= current.length;
    final offset = reliableCursor ? selection.start : current.length;
    final needsLeadingSpace =
        offset > 0 && !_isWhitespace(current.codeUnitAt(offset - 1));
    final needsTrailingSpace =
        offset < current.length && !_isWhitespace(current.codeUnitAt(offset));
    final insertion =
        '${needsLeadingSpace ? ' ' : ''}$transcript${needsTrailingSpace ? ' ' : ''}';
    final updated = current.replaceRange(offset, offset, insertion);
    final cursorOffset =
        offset + (needsLeadingSpace ? 1 : 0) + transcript.length;
    setState(() {
      _textController
        ..text = updated
        ..selection = TextSelection.collapsed(offset: cursorOffset);
    });
    _focusNode.requestFocus();
  }

  bool _isWhitespace(int codeUnit) =>
      String.fromCharCode(codeUnit).trim().isEmpty;

  void _scrollToLatest() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _sessionController.removeListener(_onSessionChanged);
    if (_ownsSessionController) _sessionController.dispose();
    if (_ownsVoiceCoordinator) _voiceCoordinator.dispose();
    _textController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _sessionController.state;
    final hasText = _textController.text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: const Color(0xFFF8EFEA),
      appBar: AppBar(title: const Text('Zelia 💕')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(18),
                itemCount: state.messages.length,
                itemBuilder: (context, index) {
                  final message = state.messages[index];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _MessageBubble(message: message),
                      if (state.quickReplyMessageId == message.id &&
                          state.quickReplies.isNotEmpty)
                        _QuickReplyChoices(
                          replies: state.quickReplies,
                          enabled: !state.isBusy,
                          onSelected: (replyId) => _sessionController.dispatch(
                            SelectConversationQuickReply(replyId),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            if (state.isBusy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: CircularProgressIndicator(),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  VoiceInputControl(
                    coordinator: _voiceCoordinator,
                    conversationSessionGeneration: state.sessionGeneration,
                    onTranscriptReady: _useVoiceTranscript,
                    enabled: !state.isBusy,
                    idleBuilder: (context, startDictation) => Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _textController,
                            focusNode: _focusNode,
                            minLines: 1,
                            maxLines: 5,
                            textInputAction: TextInputAction.send,
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) => _submit(),
                            decoration: const InputDecoration(
                              hintText: 'Écris ton message…',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          key: const Key('voice-primary'),
                          tooltip: 'Dicter un message',
                          onPressed: startDictation,
                          icon: const Icon(Icons.mic),
                        ),
                        const SizedBox(width: 8),
                        Semantics(
                          button: true,
                          label: 'Envoyer le message',
                          child: CircleAvatar(
                            radius: 28,
                            backgroundColor: const Color(0xFFC78372),
                            child: IconButton(
                              onPressed:
                                  state.isBusy || !hasText ? null : _submit,
                              icon: const Icon(Icons.send, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ConversationVisibleMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ConversationMessageRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFFC78372) : Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: isUser ? Colors.white : const Color(0xFF3D241E),
            fontSize: 16,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

class _QuickReplyChoices extends StatelessWidget {
  const _QuickReplyChoices({
    required this.replies,
    required this.enabled,
    required this.onSelected,
  });

  final List<ConversationQuickReply> replies;
  final bool enabled;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final reply in replies)
              ActionChip(
                key: Key('conversation-quick-reply-${reply.id}'),
                label: Text(reply.label),
                onPressed: enabled ? () => onSelected(reply.id) : null,
                backgroundColor: const Color(0xFFFBEAE6),
                disabledColor: const Color(0xFFFBEAE6),
                surfaceTintColor: Colors.transparent,
                side: const BorderSide(color: Color(0xFFD9A092)),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                labelStyle: const TextStyle(
                  color: Color(0xFF6A3F36),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                shape: const StadiumBorder(),
              ),
          ],
        ),
      );
}
