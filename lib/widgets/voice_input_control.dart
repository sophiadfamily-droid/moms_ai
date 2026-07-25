import 'dart:async';

import 'package:flutter/material.dart';

import '../models/voice_recognition.dart';
import '../services/voice_recognition_coordinator.dart';

typedef VoiceIdleComposerBuilder = Widget Function(
  BuildContext context,
  VoidCallback? startDictation,
);

final class VoiceInputControl extends StatefulWidget {
  const VoiceInputControl({
    super.key,
    required this.coordinator,
    required this.conversationSessionGeneration,
    required this.onTranscriptReady,
    required this.idleBuilder,
    this.enabled = true,
  });

  final VoiceRecognitionCoordinator coordinator;
  final int conversationSessionGeneration;
  final ValueChanged<String> onTranscriptReady;
  final VoiceIdleComposerBuilder idleBuilder;
  final bool enabled;

  @override
  State<VoiceInputControl> createState() => _VoiceInputControlState();
}

final class _VoiceInputControlState extends State<VoiceInputControl>
    with WidgetsBindingObserver {
  Timer? _durationTimer;
  DateTime? _startedAt;
  bool _recordingUi = false;
  bool _validating = false;
  String? _committedVoiceSessionId;
  double _minimumSoundLevel = double.infinity;
  double _maximumSoundLevel = double.negativeInfinity;
  double _visualLevel = 0.12;

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
      _leaveRecordingUi();
      unawaited(widget.coordinator.invalidateForContextChange(
        VoiceInterruptionReason.conversationChanged,
      ));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _leaveRecordingUi();
    unawaited(widget.coordinator.onLifecycleChanged(state));
  }

  void _onChanged() {
    if (!mounted) return;
    final level = widget.coordinator.soundLevel;
    if (_recordingUi && level.isFinite) {
      _minimumSoundLevel =
          level < _minimumSoundLevel ? level : _minimumSoundLevel;
      _maximumSoundLevel =
          level > _maximumSoundLevel ? level : _maximumSoundLevel;
      final range = _maximumSoundLevel - _minimumSoundLevel;
      if (range > 0.01) {
        _visualLevel = ((level - _minimumSoundLevel) / range).clamp(0.08, 1.0);
      }
    }
    setState(() {});
  }

  Future<void> _start() async {
    if (!widget.enabled || _recordingUi) return;
    setState(() {
      _recordingUi = true;
      _validating = false;
      _startedAt = DateTime.now();
      _minimumSoundLevel = double.infinity;
      _maximumSoundLevel = double.negativeInfinity;
      _visualLevel = 0.12;
    });
    _durationTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (mounted && _recordingUi) setState(() {});
      },
    );
    await widget.coordinator.begin(
      conversationSessionGeneration: widget.conversationSessionGeneration,
    );
    if (!mounted) return;
    if (widget.coordinator.permissionExplanationRequired) {
      final accepted = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Autoriser la dictée'),
              content: const Text(
                'Pour dicter un message, Zélia a besoin d’accéder au '
                'microphone et à la reconnaissance vocale. Aucun '
                'enregistrement audio n’est conservé.',
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
      if (accepted) {
        await widget.coordinator.requestPermissionsAndBegin();
      } else {
        await _cancel();
      }
    }
    if (mounted &&
        widget.coordinator.session == null &&
        !widget.coordinator.permissionExplanationRequired) {
      _leaveRecordingUi();
    }
  }

  Future<void> _cancel() async {
    if (!_recordingUi) return;
    _leaveRecordingUi();
    await widget.coordinator.cancel();
  }

  Future<void> _validate() async {
    if (!_recordingUi || _validating) return;
    setState(() => _validating = true);
    await widget.coordinator.stop();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted || !_recordingUi) return;
    final active = widget.coordinator.session;
    final transcript = widget.coordinator.takeFinalTranscript();
    final alreadyCommitted =
        active != null && _committedVoiceSessionId == active.voiceSessionId;
    if (active != null && transcript != null && !alreadyCommitted) {
      _committedVoiceSessionId = active.voiceSessionId;
      widget.onTranscriptReady(transcript);
    }
    _leaveRecordingUi();
    await widget.coordinator.cancel();
    if (!mounted) return;
    if (transcript == null || transcript.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Je n’ai pas bien entendu. Réessaie.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _leaveRecordingUi() {
    _durationTimer?.cancel();
    _durationTimer = null;
    if (!mounted) return;
    setState(() {
      _recordingUi = false;
      _validating = false;
      _startedAt = null;
    });
  }

  String get _durationLabel {
    final startedAt = _startedAt;
    final seconds =
        startedAt == null ? 0 : DateTime.now().difference(startedAt).inSeconds;
    final minutes = seconds ~/ 60;
    return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (!_recordingUi) {
      final failure = widget.coordinator.failure;
      final permissionFailure =
          failure?.code == VoiceRecognitionFailureCode.permissionDenied ||
              failure?.code ==
                  VoiceRecognitionFailureCode.permissionPermanentlyDenied;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          widget.idleBuilder(context, widget.enabled ? _start : null),
          if (permissionFailure)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                failure!.userMessage,
                key: const Key('voice-safe-error'),
                style: const TextStyle(color: Color(0xFF8A3028)),
              ),
            ),
          if (failure?.code ==
              VoiceRecognitionFailureCode.permissionPermanentlyDenied)
            TextButton(
              key: const Key('voice-open-settings'),
              onPressed: widget.coordinator.openSettings,
              child: const Text('Ouvrir les réglages'),
            ),
        ],
      );
    }
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Dictée en cours, durée $_durationLabel',
      child: Container(
        key: const Key('voice-recording-capsule'),
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBF8),
          border: Border.all(color: const Color(0xFFD9A397)),
          borderRadius: BorderRadius.circular(30),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1AC78372),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            TextButton(
              key: const Key('voice-cancel'),
              onPressed: _validating ? null : _cancel,
              child: const Text('Annuler'),
            ),
            Expanded(
              child: _SoundLevelVisualizer(level: _visualLevel),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                _durationLabel,
                key: const Key('voice-duration'),
                style: const TextStyle(
                  color: Color(0xFF3D241E),
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            IconButton.filled(
              key: const Key('voice-validate'),
              tooltip: 'Valider la dictée',
              onPressed: _validating ? null : _validate,
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                backgroundColor: const Color(0xFFC78372),
              ),
              icon: _validating
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.coordinator.removeListener(_onChanged);
    if (widget.coordinator.isListening) {
      unawaited(widget.coordinator.interrupt(
        VoiceInterruptionReason.conversationChanged,
      ));
    }
    super.dispose();
  }
}

final class _SoundLevelVisualizer extends StatelessWidget {
  const _SoundLevelVisualizer({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    const factors = [0.45, 0.75, 1.0, 0.7, 0.5];
    return Semantics(
      label: 'Niveau sonore',
      value: '${(level * 100).round()} %',
      child: SizedBox(
        key: const Key('voice-sound-level'),
        height: 34,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var index = 0; index < factors.length; index++)
              AnimatedContainer(
                key: Key('voice-sound-bar-$index'),
                duration: const Duration(milliseconds: 90),
                curve: Curves.easeOut,
                width: 4,
                height: 6 + 25 * level * factors[index],
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFC78372),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
