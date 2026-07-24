import 'package:flutter/material.dart';

import '../models/voice_recognition.dart';
import '../services/voice_recognition_coordinator.dart';

final class VoiceInputControl extends StatefulWidget {
  const VoiceInputControl({
    super.key,
    required this.coordinator,
    required this.conversationSessionGeneration,
    required this.onTranscriptReady,
    this.enabled = true,
  });

  final VoiceRecognitionCoordinator coordinator;
  final int conversationSessionGeneration;
  final ValueChanged<String> onTranscriptReady;
  final bool enabled;

  @override
  State<VoiceInputControl> createState() => _VoiceInputControlState();
}

final class _VoiceInputControlState extends State<VoiceInputControl>
    with WidgetsBindingObserver {
  String? _committedVoiceSessionId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.coordinator.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant VoiceInputControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coordinator != widget.coordinator) {
      oldWidget.coordinator.removeListener(_onChanged);
      widget.coordinator.addListener(_onChanged);
    }
    if (oldWidget.conversationSessionGeneration !=
        widget.conversationSessionGeneration) {
      widget.coordinator.invalidateForContextChange(
        VoiceInterruptionReason.conversationChanged,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.coordinator.onLifecycleChanged(state);
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _start() async {
    await widget.coordinator.begin(
      conversationSessionGeneration: widget.conversationSessionGeneration,
    );
    if (!mounted || !widget.coordinator.permissionExplanationRequired) return;
    final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Autoriser la dictée'),
            content: const Text(
              'Pour dicter un message, Zélia a besoin d’accéder au microphone '
              'et à la reconnaissance vocale. Aucun enregistrement audio '
              'n’est conservé.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Autoriser le microphone'),
              ),
            ],
          ),
        ) ??
        false;
    if (accepted) await widget.coordinator.requestPermissionsAndBegin();
  }

  void _useText() {
    final active = widget.coordinator.session;
    final transcript = widget.coordinator.takeFinalTranscript();
    if (active == null ||
        transcript == null ||
        _committedVoiceSessionId == active.voiceSessionId) {
      return;
    }
    _committedVoiceSessionId = active.voiceSessionId;
    widget.onTranscriptReady(transcript);
  }

  @override
  Widget build(BuildContext context) {
    final coordinator = widget.coordinator;
    final state = coordinator.session?.state;
    final listening = coordinator.isListening;
    final finalReady = coordinator.session?.isFinal == true &&
            coordinator.visibleTranscript.isNotEmpty ||
        state == VoiceRecognitionSessionState.stoppedWithTranscript &&
            coordinator.visibleTranscript.isNotEmpty;
    final recovered =
        state == VoiceRecognitionSessionState.stoppedWithTranscript;
    final failure = coordinator.failure;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (listening || coordinator.visibleTranscript.isNotEmpty)
          Semantics(
            liveRegion: true,
            label: listening
                ? 'Transcription de la dictée'
                : 'Texte dicté prêt à être utilisé',
            child: Container(
              constraints: const BoxConstraints(maxWidth: 360),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8F4),
                border: Border.all(color: const Color(0xFFC78372)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                coordinator.visibleTranscript.isEmpty
                    ? 'Je t’écoute…'
                    : coordinator.visibleTranscript,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        if (failure != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              failure.userMessage,
              key: const Key('voice-safe-error'),
              style: const TextStyle(color: Color(0xFF8A3028)),
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (finalReady)
              FilledButton.tonalIcon(
                key: const Key('voice-use-text'),
                onPressed: _useText,
                icon: const Icon(Icons.edit),
                label: const Text('Utiliser le texte'),
              ),
            if (listening || recovered)
              IconButton.filledTonal(
                key: const Key('voice-cancel'),
                tooltip:
                    recovered ? 'Effacer le texte dicté' : 'Annuler la dictée',
                onPressed: coordinator.cancel,
                icon: const Icon(Icons.close),
              ),
            Semantics(
              button: true,
              label: listening
                  ? 'Arrêter la dictée'
                  : state == VoiceRecognitionSessionState.interrupted ||
                          recovered
                      ? 'Reprendre la dictée'
                      : 'Démarrer la dictée',
              child: IconButton.filled(
                key: const Key('voice-primary'),
                tooltip: listening
                    ? 'Arrêter'
                    : state == VoiceRecognitionSessionState.interrupted ||
                            recovered
                        ? 'Recommencer'
                        : 'Dicter un message',
                onPressed: !widget.enabled
                    ? null
                    : listening
                        ? coordinator.stop
                        : _start,
                icon: Icon(listening ? Icons.stop : Icons.mic),
              ),
            ),
            if (failure?.code ==
                VoiceRecognitionFailureCode.permissionPermanentlyDenied)
              TextButton(
                key: const Key('voice-open-settings'),
                onPressed: coordinator.openSettings,
                child: const Text('Ouvrir les réglages'),
              ),
          ],
        ),
      ],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.coordinator.removeListener(_onChanged);
    super.dispose();
  }
}
