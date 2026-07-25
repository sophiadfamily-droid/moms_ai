import 'dart:async';
import 'dart:io';

import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/voice_recognition.dart';
import 'app_diagnostics.dart';

enum SpeechRecognitionPlatformEventType {
  listening,
  notListening,
  partialResult,
  finalResult,
  soundLevel,
  interrupted,
  failure,
}

final class SpeechRecognitionPlatformEvent {
  const SpeechRecognitionPlatformEvent({
    required this.type,
    this.transcript,
    this.failure,
    this.soundLevel,
  });

  final SpeechRecognitionPlatformEventType type;
  final String? transcript;
  final VoiceRecognitionFailure? failure;
  final double? soundLevel;
}

abstract interface class SpeechRecognitionPlatformGateway {
  Future<VoiceRecognitionAvailability> checkAvailability();
  Future<VoicePermissionState> readPermissions();
  Future<VoicePermissionState> requestPermissions();
  Future<bool> openSettings();
  Future<bool> initialize(
    void Function(SpeechRecognitionPlatformEvent event) onEvent,
  );
  Future<String> startListening({
    required String localeId,
    required Duration listenFor,
    required Duration pauseFor,
  });
  Future<void> stopListening();
  Future<void> cancelListening();
  Future<List<String>> supportedLocales();
  Future<String?> currentLocale();
  Future<void> dispose();
}

final class SpeechToTextPlatformGateway
    implements SpeechRecognitionPlatformGateway {
  SpeechToTextPlatformGateway({SpeechToText? speech})
      : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;
  void Function(SpeechRecognitionPlatformEvent event)? _onEvent;
  bool _initialized = false;
  bool _requestedPermissions = false;
  int _platformSessionSequence = 0;

  @override
  Future<VoiceRecognitionAvailability> checkAvailability() async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      return VoiceRecognitionAvailability.unsupportedPlatform;
    }
    try {
      return _speech.isAvailable
          ? VoiceRecognitionAvailability.available
          : VoiceRecognitionAvailability.unknown;
    } catch (_) {
      return VoiceRecognitionAvailability.error;
    }
  }

  @override
  Future<VoicePermissionState> readPermissions() async {
    final microphone = await Permission.microphone.status;
    final speech = Platform.isIOS ? await Permission.speech.status : microphone;
    return _permissionState(
      microphone,
      speech,
      hasRequested: _requestedPermissions,
    );
  }

  @override
  Future<VoicePermissionState> requestPermissions() async {
    _requestedPermissions = true;
    final microphone = await Permission.microphone.request();
    final speech =
        Platform.isIOS ? await Permission.speech.request() : microphone;
    return _permissionState(microphone, speech, hasRequested: true);
  }

  @override
  Future<bool> openSettings() => openAppSettings();

  @override
  Future<bool> initialize(
    void Function(SpeechRecognitionPlatformEvent event) onEvent,
  ) async {
    _onEvent = onEvent;
    if (_initialized) return true;
    _initialized = await _speech.initialize(
      onStatus: _handleStatus,
      onError: _handleError,
      options: [
        SpeechToText.androidNoBluetooth,
        SpeechToText.iosNoBluetooth,
      ],
    );
    return _initialized;
  }

  @override
  Future<String> startListening({
    required String localeId,
    required Duration listenFor,
    required Duration pauseFor,
  }) async {
    if (!_initialized) {
      throw StateError('voice_gateway_not_initialized');
    }
    final platformSessionId = 'speech-${++_platformSessionSequence}';
    _record(
      step: 'native-start',
      code: 'start-listening',
      metadata: {'platformSequence': _platformSessionSequence},
    );
    await _speech.listen(
      onResult: _handleResult,
      onSoundLevelChange: _handleSoundLevel,
      listenFor: listenFor,
      pauseFor: pauseFor,
      localeId: localeId,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.confirmation,
      ),
    );
    return platformSessionId;
  }

  @override
  Future<void> stopListening() {
    _record(step: 'native-stop', code: 'stop-listening');
    return _speech.stop();
  }

  @override
  Future<void> cancelListening() {
    _record(step: 'native-cancel', code: 'cancel-listening');
    return _speech.cancel();
  }

  @override
  Future<List<String>> supportedLocales() async =>
      (await _speech.locales()).map((locale) => locale.localeId).toList();

  @override
  Future<String?> currentLocale() async =>
      (await _speech.systemLocale())?.localeId;

  @override
  Future<void> dispose() async {
    _onEvent = null;
    await _speech.cancel();
  }

  void _handleResult(SpeechRecognitionResult result) {
    final transcript = result.recognizedWords.trim();
    if (transcript.isEmpty) return;
    _record(
      step: 'native-callback',
      code: result.finalResult ? 'final-result' : 'partial-result',
    );
    _onEvent?.call(
      SpeechRecognitionPlatformEvent(
        type: result.finalResult
            ? SpeechRecognitionPlatformEventType.finalResult
            : SpeechRecognitionPlatformEventType.partialResult,
        transcript: transcript,
      ),
    );
  }

  void _handleSoundLevel(double level) {
    if (!level.isFinite) return;
    _onEvent?.call(
      SpeechRecognitionPlatformEvent(
        type: SpeechRecognitionPlatformEventType.soundLevel,
        soundLevel: level,
      ),
    );
  }

  void _handleStatus(String status) {
    final type = switch (status) {
      SpeechToText.listeningStatus =>
        SpeechRecognitionPlatformEventType.listening,
      SpeechToText.doneStatus ||
      SpeechToText.notListeningStatus =>
        SpeechRecognitionPlatformEventType.notListening,
      _ => null,
    };
    if (type != null) {
      _record(
        step: 'native-callback',
        code: type == SpeechRecognitionPlatformEventType.listening
            ? 'listening'
            : 'not-listening',
      );
      _onEvent?.call(SpeechRecognitionPlatformEvent(type: type));
    }
  }

  void _handleError(SpeechRecognitionError error) {
    final code = _failureCode(error.errorMsg);
    _record(
      step: 'native-callback',
      code: code.name,
      metadata: {'recoverable': !error.permanent},
    );
    _onEvent?.call(
      SpeechRecognitionPlatformEvent(
        type: SpeechRecognitionPlatformEventType.failure,
        failure: VoiceRecognitionFailure(
          code: code,
          isRecoverable: !error.permanent,
        ),
      ),
    );
  }

  static VoicePermissionState _permissionState(
      PermissionStatus microphone, PermissionStatus speech,
      {required bool hasRequested}) {
    final microphoneState =
        _permissionStatus(microphone, hasRequested: hasRequested);
    final speechState = _permissionStatus(speech, hasRequested: hasRequested);
    final canRequest = !hasRequested &&
        (microphone == PermissionStatus.denied ||
            speech == PermissionStatus.denied);
    final canOpenSettings = microphone.isPermanentlyDenied ||
        speech.isPermanentlyDenied ||
        microphone.isRestricted ||
        speech.isRestricted;
    return VoicePermissionState(
      microphone: microphoneState,
      speechRecognition: speechState,
      checkedAt: DateTime.now().toUtc(),
      canRequest: canRequest,
      canOpenSettings: canOpenSettings,
    );
  }

  static VoicePermissionStatus _permissionStatus(
    PermissionStatus status, {
    required bool hasRequested,
  }) =>
      switch (status) {
        PermissionStatus.granted ||
        PermissionStatus.limited ||
        PermissionStatus.provisional =>
          VoicePermissionStatus.authorized,
        PermissionStatus.denied => hasRequested
            ? VoicePermissionStatus.denied
            : VoicePermissionStatus.notDetermined,
        PermissionStatus.permanentlyDenied =>
          VoicePermissionStatus.permanentlyDenied,
        PermissionStatus.restricted => VoicePermissionStatus.restricted,
      };

  static VoiceRecognitionFailureCode _failureCode(String code) =>
      switch (code) {
        'error_permission' => VoiceRecognitionFailureCode.permissionDenied,
        'error_busy' => VoiceRecognitionFailureCode.recognizerBusy,
        'error_no_match' => VoiceRecognitionFailureCode.noMatch,
        'error_speech_timeout' => VoiceRecognitionFailureCode.noSpeech,
        'error_network' => VoiceRecognitionFailureCode.networkUnavailable,
        'error_network_timeout' => VoiceRecognitionFailureCode.networkTimeout,
        'error_audio_error' => VoiceRecognitionFailureCode.audioUnavailable,
        'error_language_not_supported' ||
        'error_language_unavailable' =>
          VoiceRecognitionFailureCode.localeUnsupported,
        _ => VoiceRecognitionFailureCode.platformFailure,
      };

  static void _record({
    required String step,
    required String code,
    Map<String, Object?> metadata = const {},
  }) {
    AppDiagnostics.record(
      component: 'voice-platform',
      step: step,
      code: AppErrorCode.unknown,
      severity: AppErrorSeverity.info,
      metadata: {
        'status': code,
        if (metadata['platformSequence'] case final num sequence)
          'count': sequence,
        if (metadata['recoverable'] case final bool recoverable)
          'retryable': recoverable,
      },
    );
  }
}
