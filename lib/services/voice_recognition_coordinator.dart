import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/voice_recognition.dart';
import 'app_diagnostics.dart';
import 'voice_service.dart';

final class VoiceRecognitionCoordinator extends ChangeNotifier {
  VoiceRecognitionCoordinator({
    required SpeechRecognitionPlatformGateway gateway,
    VoiceRecognitionLimits limits = const VoiceRecognitionLimits(),
    DateTime Function()? clock,
    String Function()? idGenerator,
  })  : _gateway = gateway,
        _limits = limits,
        _clock = clock ?? DateTime.now,
        _idGenerator = idGenerator ?? _defaultId;

  factory VoiceRecognitionCoordinator.production() =>
      VoiceRecognitionCoordinator(
        gateway: SpeechToTextPlatformGateway(),
      );

  final SpeechRecognitionPlatformGateway _gateway;
  final VoiceRecognitionLimits _limits;
  final DateTime Function() _clock;
  final String Function() _idGenerator;

  VoiceRecognitionAvailability availability =
      VoiceRecognitionAvailability.unknown;
  VoicePermissionState? permissions;
  VoiceRecognitionSession? session;
  VoiceRecognitionFailure? failure;
  bool permissionExplanationRequired = false;
  bool _disposed = false;
  int _generation = 0;
  Timer? _maximumTimer;
  Timer? _silenceTimer;
  Future<void>? _startOperation;
  int? _nativeStartedGeneration;
  String? _pendingAccountScopeId;
  int _pendingConversationGeneration = 0;
  String _requestedLocale = 'fr_FR';
  double soundLevel = 0;

  bool get isListening => {
        VoiceRecognitionSessionState.starting,
        VoiceRecognitionSessionState.listening,
        VoiceRecognitionSessionState.receivingPartialResult,
      }.contains(session?.state);

  String get visibleTranscript =>
      session?.finalTranscript ?? session?.partialTranscript ?? '';

  Future<void> begin({
    required int conversationSessionGeneration,
    String? accountScopeId,
    String localeId = 'fr_FR',
  }) {
    if (_disposed || _startOperation != null || _blocksNewStart) {
      _record(
        step: 'start-request',
        code: 'start-deduplicated',
        accepted: false,
        sessionGeneration: conversationSessionGeneration,
      );
      return Future.value();
    }
    final operation = _begin(
      conversationSessionGeneration: conversationSessionGeneration,
      accountScopeId: accountScopeId,
      localeId: localeId,
    );
    _startOperation = operation;
    operation.whenComplete(() {
      if (identical(_startOperation, operation)) _startOperation = null;
    });
    return operation;
  }

  Future<void> _begin({
    required int conversationSessionGeneration,
    String? accountScopeId,
    required String localeId,
  }) async {
    _record(
      step: 'start-request',
      code: 'user-start',
      accepted: true,
      sessionGeneration: conversationSessionGeneration,
    );
    _pendingAccountScopeId = accountScopeId;
    _pendingConversationGeneration = conversationSessionGeneration;
    _requestedLocale = localeId;
    failure = null;
    soundLevel = 0;
    permissionExplanationRequired = false;
    availability = VoiceRecognitionAvailability.checking;
    notifyListeners();
    final state = await _gateway.readPermissions();
    if (_disposed) return;
    permissions = state;
    if (!state.isAuthorized) {
      permissionExplanationRequired = state.canRequest;
      failure = state.canOpenSettings
          ? const VoiceRecognitionFailure(
              code: VoiceRecognitionFailureCode.permissionPermanentlyDenied,
              isRecoverable: true,
            )
          : state.canRequest
              ? null
              : const VoiceRecognitionFailure(
                  code: VoiceRecognitionFailureCode.permissionDenied,
                  isRecoverable: true,
                );
      availability = VoiceRecognitionAvailability.unknown;
      notifyListeners();
      return;
    }
    await _initializeAndListen();
  }

  Future<void> requestPermissionsAndBegin() async {
    if (_disposed ||
        !permissionExplanationRequired ||
        _startOperation != null ||
        _blocksNewStart) {
      return;
    }
    final operation = _requestPermissionsAndBegin();
    _startOperation = operation;
    try {
      await operation;
    } finally {
      if (identical(_startOperation, operation)) _startOperation = null;
    }
  }

  Future<void> _requestPermissionsAndBegin() async {
    permissionExplanationRequired = false;
    permissions = await _gateway.requestPermissions();
    if (_disposed) return;
    if (permissions!.isAuthorized) {
      await _initializeAndListen();
      return;
    }
    failure = VoiceRecognitionFailure(
      code: permissions!.canOpenSettings
          ? VoiceRecognitionFailureCode.permissionPermanentlyDenied
          : VoiceRecognitionFailureCode.permissionDenied,
      isRecoverable: true,
    );
    notifyListeners();
  }

  Future<bool> openSettings() => _gateway.openSettings();

  Future<void> _initializeAndListen() async {
    final generation = ++_generation;
    if (_nativeStartedGeneration == generation) return;
    availability = VoiceRecognitionAvailability.checking;
    notifyListeners();
    try {
      final initialized = await _gateway
          .initialize((event) => _onPlatformEvent(generation, event))
          .timeout(_limits.initializationTimeout);
      if (!_isCurrent(generation)) return;
      if (!initialized) {
        _fail(VoiceRecognitionFailureCode.initializationFailed);
        return;
      }
      final locales = await _gateway.supportedLocales();
      if (!_isCurrent(generation)) return;
      final normalizedRequested = _requestedLocale.replaceAll('-', '_');
      String? selected = locales.cast<String?>().firstWhere(
            (locale) =>
                locale?.replaceAll('-', '_').toLowerCase() ==
                normalizedRequested.toLowerCase(),
            orElse: () => null,
          );
      selected ??= await _gateway.currentLocale();
      if (!_isCurrent(generation)) return;
      if (selected == null || !selected.toLowerCase().startsWith('fr')) {
        _fail(VoiceRecognitionFailureCode.localeUnsupported);
        return;
      }
      final now = _clock().toUtc();
      session = VoiceRecognitionSession(
        voiceSessionId: _idGenerator(),
        conversationSessionGeneration: _pendingConversationGeneration,
        accountScopeId: _pendingAccountScopeId,
        localeId: selected,
        state: VoiceRecognitionSessionState.starting,
        startedAt: now,
        silenceDeadline: now.add(_limits.silenceDuration),
        maximumDeadline: now.add(_limits.maximumSessionDuration),
      );
      availability = VoiceRecognitionAvailability.available;
      notifyListeners();
      if (!_isCurrent(generation) ||
          _nativeStartedGeneration == generation ||
          _nativeStartedGeneration != null) {
        _record(
          step: 'native-start',
          code: 'native-start-deduplicated',
          accepted: false,
          sessionGeneration: _pendingConversationGeneration,
        );
        return;
      }
      _nativeStartedGeneration = generation;
      _record(
        step: 'native-start',
        code: 'native-start-dispatched',
        accepted: true,
        sessionGeneration: _pendingConversationGeneration,
      );
      final platformId = await _gateway.startListening(
        localeId: selected,
        listenFor: _limits.maximumSessionDuration,
        pauseFor: _limits.silenceDuration,
      );
      if (!_isCurrent(generation)) {
        await _gateway.cancelListening();
        _nativeStartedGeneration = null;
        return;
      }
      session = session!.copyWith(
        state: VoiceRecognitionSessionState.listening,
        platformSessionId: platformId,
      );
      _armTimers(generation);
      notifyListeners();
    } on TimeoutException {
      if (_isCurrent(generation)) {
        _fail(VoiceRecognitionFailureCode.initializationFailed);
      }
    } catch (_) {
      if (_isCurrent(generation)) {
        _fail(VoiceRecognitionFailureCode.platformFailure);
      }
    }
  }

  Future<void> stop() async {
    if (_disposed || !isListening) return;
    final active = session;
    _cancelTimers();
    session = active?.copyWith(state: VoiceRecognitionSessionState.stopping);
    notifyListeners();
    try {
      await _gateway.stopListening().timeout(_limits.stopTimeout);
    } catch (_) {
      await _gateway.cancelListening();
    }
    if (active != null && session?.voiceSessionId == active.voiceSessionId) {
      session = session!.copyWith(
        state: VoiceRecognitionSessionState.stopped,
        stoppedAt: _clock().toUtc(),
        finalTranscript: session!.finalTranscript ??
            (session!.partialTranscript.isEmpty
                ? null
                : session!.partialTranscript),
        isFinal: session!.isFinal || session!.partialTranscript.isNotEmpty,
      );
      notifyListeners();
    }
    _nativeStartedGeneration = null;
  }

  Future<void> cancel() async {
    if (_disposed) return;
    _generation++;
    _cancelTimers();
    await _gateway.cancelListening();
    _nativeStartedGeneration = null;
    soundLevel = 0;
    final active = session;
    if (active != null) {
      session = active.copyWith(
        state: VoiceRecognitionSessionState.cancelled,
        stoppedAt: _clock().toUtc(),
        partialTranscript: '',
        finalTranscript: '',
      );
    }
    notifyListeners();
  }

  Future<void> interrupt(VoiceInterruptionReason reason) async {
    if (_disposed || session == null || !isListening) return;
    _generation++;
    _cancelTimers();
    await _gateway.cancelListening();
    _nativeStartedGeneration = null;
    soundLevel = 0;
    session = session!.copyWith(
      state: VoiceRecognitionSessionState.interrupted,
      stoppedAt: _clock().toUtc(),
      interruptionReason: reason,
      errorCode: VoiceRecognitionFailureCode.interrupted,
    );
    failure = const VoiceRecognitionFailure(
      code: VoiceRecognitionFailureCode.interrupted,
      isRecoverable: true,
    );
    notifyListeners();
  }

  Future<void> onLifecycleChanged(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.inactive:
        await interrupt(VoiceInterruptionReason.applicationInactive);
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        await interrupt(VoiceInterruptionReason.applicationPaused);
      case AppLifecycleState.detached:
        await disposeAsync();
      case AppLifecycleState.resumed:
        permissions = await _gateway.readPermissions();
        availability = await _gateway.checkAvailability();
        if (!_disposed) notifyListeners();
    }
  }

  Future<void> invalidateForContextChange(
      VoiceInterruptionReason reason) async {
    if (isListening) {
      await interrupt(reason);
    } else {
      _generation++;
      session = null;
      failure = null;
      notifyListeners();
    }
  }

  String? takeFinalTranscript() {
    final transcript = session?.finalTranscript?.trim();
    if (transcript == null || transcript.isEmpty) return null;
    return transcript;
  }

  void _onPlatformEvent(
    int generation,
    SpeechRecognitionPlatformEvent event,
  ) {
    final accepted = _isCurrent(generation) && session != null;
    if (event.type != SpeechRecognitionPlatformEventType.soundLevel) {
      _record(
        step: 'platform-event',
        code: event.type.name,
        accepted: accepted,
        sessionGeneration: session?.conversationSessionGeneration,
      );
    }
    if (!accepted) return;
    switch (event.type) {
      case SpeechRecognitionPlatformEventType.partialResult:
        _acceptTranscript(event.transcript, false, generation);
      case SpeechRecognitionPlatformEventType.finalResult:
        _acceptTranscript(event.transcript, true, generation);
      case SpeechRecognitionPlatformEventType.failure:
        final code =
            event.failure?.code ?? VoiceRecognitionFailureCode.platformFailure;
        if (_canRecoverPartial(code)) {
          _recoverPartial(code);
        } else {
          _fail(
            code,
            recoverable: event.failure?.isRecoverable ?? true,
          );
        }
      case SpeechRecognitionPlatformEventType.interrupted:
        unawaited(interrupt(VoiceInterruptionReason.systemAudio));
      case SpeechRecognitionPlatformEventType.notListening:
        if (session!.partialTranscript.isEmpty &&
            (session!.finalTranscript?.isEmpty ?? true)) {
          _fail(VoiceRecognitionFailureCode.noSpeech);
        } else if (!session!.isFinal) {
          _recoverPartial(VoiceRecognitionFailureCode.lifecycleStopped);
        }
      case SpeechRecognitionPlatformEventType.listening:
        session = session!.copyWith(
          state: VoiceRecognitionSessionState.listening,
        );
        notifyListeners();
      case SpeechRecognitionPlatformEventType.soundLevel:
        final level = event.soundLevel;
        if (level != null && level.isFinite && soundLevel != level) {
          soundLevel = level;
          notifyListeners();
        }
    }
  }

  void _acceptTranscript(String? raw, bool isFinal, int generation) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty || !_isCurrent(generation) || session == null) return;
    final bounded = value.length <= _limits.maximumTranscriptLength
        ? value
        : value.substring(0, _limits.maximumTranscriptLength);
    final now = _clock().toUtc();
    if (isFinal) {
      final fragments = [...session!.finalFragments];
      if (!fragments.contains(bounded) &&
          fragments.length < _limits.maximumFinalFragments) {
        fragments.add(bounded);
      }
      final transcript = fragments.join(' ').trim();
      session = session!.copyWith(
        state: VoiceRecognitionSessionState.receivingFinalResult,
        lastResultAt: now,
        finalTranscript: transcript,
        partialTranscript: '',
        isFinal: true,
        finalFragments: fragments,
      );
      _cancelTimers();
      _generation++;
      _nativeStartedGeneration = null;
      unawaited(_gateway.stopListening());
    } else {
      session = session!.copyWith(
        state: VoiceRecognitionSessionState.receivingPartialResult,
        lastResultAt: now,
        partialTranscript: bounded,
        silenceDeadline: now.add(_limits.silenceDuration),
      );
      _armSilenceTimer(generation);
    }
    if (value.length > _limits.maximumTranscriptLength) {
      failure = const VoiceRecognitionFailure(
        code: VoiceRecognitionFailureCode.resultTooLong,
        isRecoverable: true,
      );
      unawaited(stop());
    }
    notifyListeners();
  }

  void _armTimers(int generation) {
    _maximumTimer?.cancel();
    _maximumTimer = Timer(_limits.maximumSessionDuration, () {
      if (_isCurrent(generation)) _timeOut();
    });
    _armSilenceTimer(generation);
  }

  void _armSilenceTimer(int generation) {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(_limits.silenceDuration, () {
      if (_isCurrent(generation)) _timeOut();
    });
  }

  void _timeOut() {
    if (session?.partialTranscript.trim().isNotEmpty ?? false) {
      _recoverPartial(VoiceRecognitionFailureCode.lifecycleStopped);
      return;
    }
    _generation++;
    _cancelTimers();
    unawaited(_gateway.cancelListening());
    _nativeStartedGeneration = null;
    soundLevel = 0;
    session = session?.copyWith(
      state: VoiceRecognitionSessionState.timedOut,
      stoppedAt: _clock().toUtc(),
      errorCode: session!.partialTranscript.isEmpty
          ? VoiceRecognitionFailureCode.noSpeech
          : VoiceRecognitionFailureCode.lifecycleStopped,
    );
    failure = VoiceRecognitionFailure(
      code: session?.partialTranscript.isEmpty ?? true
          ? VoiceRecognitionFailureCode.noSpeech
          : VoiceRecognitionFailureCode.lifecycleStopped,
      isRecoverable: true,
    );
    notifyListeners();
  }

  void _fail(
    VoiceRecognitionFailureCode code, {
    bool recoverable = true,
  }) {
    _generation++;
    _cancelTimers();
    unawaited(_gateway.cancelListening());
    _nativeStartedGeneration = null;
    failure = VoiceRecognitionFailure(code: code, isRecoverable: recoverable);
    availability = code == VoiceRecognitionFailureCode.recognizerUnavailable
        ? VoiceRecognitionAvailability.unavailable
        : availability;
    session = session?.copyWith(
      state: VoiceRecognitionSessionState.failed,
      stoppedAt: _clock().toUtc(),
      errorCode: code,
    );
    notifyListeners();
  }

  bool _canRecoverPartial(VoiceRecognitionFailureCode code) =>
      session?.partialTranscript.trim().isNotEmpty == true &&
      (code == VoiceRecognitionFailureCode.noSpeech ||
          code == VoiceRecognitionFailureCode.noMatch ||
          code == VoiceRecognitionFailureCode.lifecycleStopped);

  void _recoverPartial(VoiceRecognitionFailureCode reason) {
    final active = session;
    final transcript = active?.partialTranscript.trim() ?? '';
    if (active == null || transcript.isEmpty) {
      _fail(reason);
      return;
    }
    _generation++;
    _cancelTimers();
    _nativeStartedGeneration = null;
    unawaited(_gateway.cancelListening());
    failure = null;
    session = active.copyWith(
      state: VoiceRecognitionSessionState.stoppedWithTranscript,
      stoppedAt: _clock().toUtc(),
      partialTranscript: '',
      finalTranscript: transcript,
      isFinal: false,
    );
    _record(
      step: 'partial-recovery',
      code: reason.name,
      accepted: true,
      sessionGeneration: active.conversationSessionGeneration,
    );
    notifyListeners();
  }

  bool get _blocksNewStart =>
      _nativeStartedGeneration != null ||
      {
        VoiceRecognitionSessionState.starting,
        VoiceRecognitionSessionState.listening,
        VoiceRecognitionSessionState.receivingPartialResult,
        VoiceRecognitionSessionState.stopping,
      }.contains(session?.state);

  void _record({
    required String step,
    required String code,
    required bool accepted,
    int? sessionGeneration,
  }) {
    AppDiagnostics.record(
      component: 'voice-coordinator',
      step: step,
      code: AppErrorCode.unknown,
      severity: AppErrorSeverity.info,
      metadata: {
        'eventType': code,
        'accepted': accepted,
        'attemptCount': session?.attemptCount ?? 1,
        'sessionGeneration':
            sessionGeneration ?? session?.conversationSessionGeneration ?? 0,
        'state': session?.state.name ?? 'none',
      },
      correlationId: session?.voiceSessionId,
    );
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _cancelTimers() {
    _maximumTimer?.cancel();
    _silenceTimer?.cancel();
    _maximumTimer = null;
    _silenceTimer = null;
  }

  Future<void> disposeAsync() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _cancelTimers();
    await _gateway.dispose();
    _nativeStartedGeneration = null;
  }

  @override
  void dispose() {
    unawaited(disposeAsync());
    super.dispose();
  }

  static String _defaultId() =>
      'voice-${DateTime.now().microsecondsSinceEpoch}';
}
