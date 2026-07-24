import 'dart:collection';

enum VoiceRecognitionAvailability {
  unknown,
  checking,
  available,
  unavailable,
  serviceMissing,
  temporarilyUnavailable,
  unsupportedPlatform,
  error,
}

enum VoicePermissionStatus {
  unknown,
  notDetermined,
  authorized,
  denied,
  permanentlyDenied,
  restricted,
  unavailable,
  error,
}

enum VoiceRecognitionSessionState {
  idle,
  checkingPermission,
  initializing,
  ready,
  starting,
  listening,
  receivingPartialResult,
  receivingFinalResult,
  stopping,
  stopped,
  stoppedWithTranscript,
  cancelled,
  interrupted,
  timedOut,
  unavailable,
  failed,
  disposed,
}

final class VoiceRecognitionStateMachine {
  static const Map<VoiceRecognitionSessionState,
      Set<VoiceRecognitionSessionState>> _allowed = {
    VoiceRecognitionSessionState.idle: {
      VoiceRecognitionSessionState.checkingPermission,
      VoiceRecognitionSessionState.disposed,
    },
    VoiceRecognitionSessionState.checkingPermission: {
      VoiceRecognitionSessionState.initializing,
      VoiceRecognitionSessionState.unavailable,
      VoiceRecognitionSessionState.failed,
      VoiceRecognitionSessionState.cancelled,
    },
    VoiceRecognitionSessionState.initializing: {
      VoiceRecognitionSessionState.ready,
      VoiceRecognitionSessionState.unavailable,
      VoiceRecognitionSessionState.failed,
      VoiceRecognitionSessionState.cancelled,
    },
    VoiceRecognitionSessionState.ready: {
      VoiceRecognitionSessionState.starting,
      VoiceRecognitionSessionState.cancelled,
      VoiceRecognitionSessionState.disposed,
    },
    VoiceRecognitionSessionState.starting: {
      VoiceRecognitionSessionState.listening,
      VoiceRecognitionSessionState.failed,
      VoiceRecognitionSessionState.interrupted,
      VoiceRecognitionSessionState.cancelled,
    },
    VoiceRecognitionSessionState.listening: {
      VoiceRecognitionSessionState.receivingPartialResult,
      VoiceRecognitionSessionState.receivingFinalResult,
      VoiceRecognitionSessionState.stopping,
      VoiceRecognitionSessionState.interrupted,
      VoiceRecognitionSessionState.timedOut,
      VoiceRecognitionSessionState.failed,
      VoiceRecognitionSessionState.cancelled,
    },
    VoiceRecognitionSessionState.receivingPartialResult: {
      VoiceRecognitionSessionState.receivingPartialResult,
      VoiceRecognitionSessionState.receivingFinalResult,
      VoiceRecognitionSessionState.stopping,
      VoiceRecognitionSessionState.stoppedWithTranscript,
      VoiceRecognitionSessionState.interrupted,
      VoiceRecognitionSessionState.timedOut,
      VoiceRecognitionSessionState.failed,
      VoiceRecognitionSessionState.cancelled,
    },
    VoiceRecognitionSessionState.receivingFinalResult: {
      VoiceRecognitionSessionState.stopping,
      VoiceRecognitionSessionState.stopped,
      VoiceRecognitionSessionState.failed,
      VoiceRecognitionSessionState.cancelled,
    },
    VoiceRecognitionSessionState.stopping: {
      VoiceRecognitionSessionState.stopped,
      VoiceRecognitionSessionState.failed,
      VoiceRecognitionSessionState.cancelled,
    },
    VoiceRecognitionSessionState.stopped: {
      VoiceRecognitionSessionState.disposed,
    },
    VoiceRecognitionSessionState.stoppedWithTranscript: {
      VoiceRecognitionSessionState.disposed,
    },
    VoiceRecognitionSessionState.cancelled: {
      VoiceRecognitionSessionState.disposed,
    },
    VoiceRecognitionSessionState.interrupted: {
      VoiceRecognitionSessionState.disposed,
    },
    VoiceRecognitionSessionState.timedOut: {
      VoiceRecognitionSessionState.disposed,
    },
    VoiceRecognitionSessionState.unavailable: {
      VoiceRecognitionSessionState.disposed,
    },
    VoiceRecognitionSessionState.failed: {
      VoiceRecognitionSessionState.disposed,
    },
    VoiceRecognitionSessionState.disposed: {},
  };

  static bool canTransition(
    VoiceRecognitionSessionState from,
    VoiceRecognitionSessionState to,
  ) =>
      _allowed[from]?.contains(to) ?? false;

  static void requireTransition(
    VoiceRecognitionSessionState from,
    VoiceRecognitionSessionState to,
  ) {
    if (!canTransition(from, to)) {
      throw StateError('invalid_voice_state_transition');
    }
  }
}

enum VoiceRecognitionFailureCode {
  permissionDenied,
  permissionPermanentlyDenied,
  recognizerUnavailable,
  recognizerBusy,
  noSpeech,
  noMatch,
  networkUnavailable,
  networkTimeout,
  audioUnavailable,
  interrupted,
  lifecycleStopped,
  localeUnsupported,
  initializationFailed,
  platformFailure,
  resultTooLong,
  cancelled,
  unknownFailure,
}

enum VoiceInterruptionReason {
  applicationInactive,
  applicationPaused,
  applicationDetached,
  accountChanged,
  conversationChanged,
  systemAudio,
  audioRouteChanged,
  recognizerLost,
}

final class VoiceRecognitionLimits {
  const VoiceRecognitionLimits({
    this.maximumSessionDuration = const Duration(minutes: 1),
    this.silenceDuration = const Duration(seconds: 6),
    this.maximumTranscriptLength = 4000,
    this.maximumFinalFragments = 20,
    this.maximumAttempts = 3,
    this.maximumConsecutiveErrors = 3,
    this.initializationTimeout = const Duration(seconds: 8),
    this.stopTimeout = const Duration(seconds: 3),
    this.minimumUiUpdateInterval = const Duration(milliseconds: 80),
  });

  final Duration maximumSessionDuration;
  final Duration silenceDuration;
  final int maximumTranscriptLength;
  final int maximumFinalFragments;
  final int maximumAttempts;
  final int maximumConsecutiveErrors;
  final Duration initializationTimeout;
  final Duration stopTimeout;
  final Duration minimumUiUpdateInterval;
}

final class VoicePermissionState {
  const VoicePermissionState({
    required this.microphone,
    required this.speechRecognition,
    required this.checkedAt,
    required this.canRequest,
    required this.canOpenSettings,
  });

  final VoicePermissionStatus microphone;
  final VoicePermissionStatus speechRecognition;
  final DateTime checkedAt;
  final bool canRequest;
  final bool canOpenSettings;

  bool get isAuthorized =>
      microphone == VoicePermissionStatus.authorized &&
      speechRecognition == VoicePermissionStatus.authorized;
}

final class VoiceRecognitionFailure {
  const VoiceRecognitionFailure({
    required this.code,
    required this.isRecoverable,
  });

  final VoiceRecognitionFailureCode code;
  final bool isRecoverable;

  String get userMessage => switch (code) {
        VoiceRecognitionFailureCode.permissionDenied =>
          'Le microphone et la reconnaissance vocale ne sont pas autorisés.',
        VoiceRecognitionFailureCode.permissionPermanentlyDenied =>
          'Tu peux autoriser la dictée dans les réglages du téléphone.',
        VoiceRecognitionFailureCode.noSpeech ||
        VoiceRecognitionFailureCode.noMatch =>
          "Je n'ai rien entendu. Tu peux recommencer.",
        VoiceRecognitionFailureCode.networkUnavailable ||
        VoiceRecognitionFailureCode.networkTimeout =>
          'La reconnaissance vocale est temporairement indisponible.',
        VoiceRecognitionFailureCode.localeUnsupported =>
          "La reconnaissance en français n'est pas disponible sur cet appareil.",
        VoiceRecognitionFailureCode.interrupted ||
        VoiceRecognitionFailureCode.lifecycleStopped =>
          'La dictée a été interrompue. Aucun message n’a été envoyé.',
        VoiceRecognitionFailureCode.resultTooLong =>
          'La dictée est trop longue. Le texte conservé reste modifiable.',
        VoiceRecognitionFailureCode.recognizerBusy =>
          'Le service vocal est déjà occupé. Réessaie dans un instant.',
        _ => 'La dictée est indisponible pour le moment.',
      };
}

final class VoiceRecognitionResult {
  VoiceRecognitionResult({
    required this.voiceSessionId,
    required String transcript,
    required this.isFinal,
    required this.receivedAt,
    this.fragmentIndex = 0,
  }) : transcript = transcript.trim() {
    if (voiceSessionId.trim().isEmpty ||
        this.transcript.isEmpty ||
        fragmentIndex < 0) {
      throw const FormatException('invalid_voice_result');
    }
  }

  final String voiceSessionId;
  final String transcript;
  final bool isFinal;
  final DateTime receivedAt;
  final int fragmentIndex;
}

final class VoiceRecognitionSession {
  static const int currentSchemaVersion = 1;

  VoiceRecognitionSession({
    this.schemaVersion = currentSchemaVersion,
    required this.voiceSessionId,
    required this.conversationSessionGeneration,
    required this.localeId,
    required this.state,
    required this.startedAt,
    required this.silenceDeadline,
    required this.maximumDeadline,
    this.accountScopeId,
    this.lastResultAt,
    this.stoppedAt,
    this.partialTranscript = '',
    this.finalTranscript,
    this.isFinal = false,
    this.interruptionReason,
    this.errorCode,
    this.attemptCount = 1,
    this.platformSessionId,
    List<String> finalFragments = const [],
  }) : finalFragments = UnmodifiableListView(finalFragments) {
    if (schemaVersion != currentSchemaVersion ||
        voiceSessionId.trim().isEmpty ||
        conversationSessionGeneration < 0 ||
        localeId.trim().isEmpty ||
        !maximumDeadline.isAfter(startedAt) ||
        !silenceDeadline.isAfter(startedAt) ||
        attemptCount < 1 ||
        accountScopeId != null && accountScopeId!.trim().isEmpty ||
        platformSessionId != null && platformSessionId!.trim().isEmpty) {
      throw const FormatException('invalid_voice_session');
    }
  }

  final int schemaVersion;
  final String voiceSessionId;
  final int conversationSessionGeneration;
  final String? accountScopeId;
  final String localeId;
  final VoiceRecognitionSessionState state;
  final DateTime startedAt;
  final DateTime? lastResultAt;
  final DateTime? stoppedAt;
  final String partialTranscript;
  final String? finalTranscript;
  final bool isFinal;
  final DateTime silenceDeadline;
  final DateTime maximumDeadline;
  final VoiceInterruptionReason? interruptionReason;
  final VoiceRecognitionFailureCode? errorCode;
  final int attemptCount;
  final String? platformSessionId;
  final List<String> finalFragments;

  Map<String, Object?> toTechnicalJson() => {
        'schemaVersion': schemaVersion,
        'voiceSessionId': voiceSessionId,
        'conversationSessionGeneration': conversationSessionGeneration,
        'localeId': localeId,
        'state': state.name,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'lastResultAt': lastResultAt?.toUtc().toIso8601String(),
        'stoppedAt': stoppedAt?.toUtc().toIso8601String(),
        'isFinal': isFinal,
        'silenceDeadline': silenceDeadline.toUtc().toIso8601String(),
        'maximumDeadline': maximumDeadline.toUtc().toIso8601String(),
        'interruptionReason': interruptionReason?.name,
        'errorCode': errorCode?.name,
        'attemptCount': attemptCount,
        'fragmentCount': finalFragments.length,
      };

  VoiceRecognitionSession copyWith({
    VoiceRecognitionSessionState? state,
    DateTime? lastResultAt,
    DateTime? stoppedAt,
    String? partialTranscript,
    String? finalTranscript,
    bool? isFinal,
    DateTime? silenceDeadline,
    VoiceInterruptionReason? interruptionReason,
    VoiceRecognitionFailureCode? errorCode,
    String? platformSessionId,
    List<String>? finalFragments,
  }) =>
      VoiceRecognitionSession(
        voiceSessionId: voiceSessionId,
        conversationSessionGeneration: conversationSessionGeneration,
        accountScopeId: accountScopeId,
        localeId: localeId,
        state: state ?? this.state,
        startedAt: startedAt,
        lastResultAt: lastResultAt ?? this.lastResultAt,
        stoppedAt: stoppedAt ?? this.stoppedAt,
        partialTranscript: partialTranscript ?? this.partialTranscript,
        finalTranscript: finalTranscript ?? this.finalTranscript,
        isFinal: isFinal ?? this.isFinal,
        silenceDeadline: silenceDeadline ?? this.silenceDeadline,
        maximumDeadline: maximumDeadline,
        interruptionReason: interruptionReason ?? this.interruptionReason,
        errorCode: errorCode ?? this.errorCode,
        attemptCount: attemptCount,
        platformSessionId: platformSessionId ?? this.platformSessionId,
        finalFragments: finalFragments ?? this.finalFragments,
      );
}
