import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/voice_recognition.dart';
import 'package:moms_ai/services/voice_recognition_coordinator.dart';
import 'package:moms_ai/services/voice_service.dart';
import 'package:moms_ai/widgets/voice_input_control.dart';

void main() {
  group('voice models', () {
    test('technical serialization is deterministic and excludes content/scope',
        () {
      final session = VoiceRecognitionSession(
        voiceSessionId: 'voice-1',
        conversationSessionGeneration: 2,
        accountScopeId: 'private-account',
        localeId: 'fr_FR',
        state: VoiceRecognitionSessionState.receivingFinalResult,
        startedAt: DateTime.utc(2026, 7, 24, 10),
        lastResultAt: DateTime.utc(2026, 7, 24, 10, 0, 1),
        partialTranscript: 'contenu partiel privé',
        finalTranscript: 'contenu final privé',
        isFinal: true,
        silenceDeadline: DateTime.utc(2026, 7, 24, 10, 0, 6),
        maximumDeadline: DateTime.utc(2026, 7, 24, 10, 1),
        finalFragments: const ['contenu final privé'],
      );

      final json = session.toTechnicalJson();
      expect(
          json['schemaVersion'], VoiceRecognitionSession.currentSchemaVersion);
      expect(json['fragmentCount'], 1);
      expect(json.toString(), isNot(contains('contenu')));
      expect(json.toString(), isNot(contains('private-account')));
      expect(json.keys, isNot(contains('accountScopeId')));
    });

    test('future versions and invalid deadlines are refused', () {
      expect(
        () => VoiceRecognitionSession(
          schemaVersion: 2,
          voiceSessionId: 'voice-1',
          conversationSessionGeneration: 0,
          localeId: 'fr_FR',
          state: VoiceRecognitionSessionState.idle,
          startedAt: DateTime.utc(2026),
          silenceDeadline: DateTime.utc(2026, 1, 1, 0, 0, 1),
          maximumDeadline: DateTime.utc(2026, 1, 1, 0, 1),
        ),
        throwsFormatException,
      );
    });

    test('failure messages never expose native details', () {
      const failure = VoiceRecognitionFailure(
        code: VoiceRecognitionFailureCode.platformFailure,
        isRecoverable: true,
      );
      expect(failure.userMessage, isNot(contains('Exception')));
    });

    test('state transitions are closed', () {
      expect(
        VoiceRecognitionStateMachine.canTransition(
          VoiceRecognitionSessionState.listening,
          VoiceRecognitionSessionState.receivingPartialResult,
        ),
        isTrue,
      );
      expect(
        () => VoiceRecognitionStateMachine.requireTransition(
          VoiceRecognitionSessionState.cancelled,
          VoiceRecognitionSessionState.receivingFinalResult,
        ),
        throwsStateError,
      );
    });
  });

  group('VoiceRecognitionCoordinator', () {
    test('reads permissions silently and requests only after explicit consent',
        () async {
      final gateway = _FakeGateway(authorized: false);
      final coordinator = _coordinator(gateway);

      await coordinator.begin(conversationSessionGeneration: 3);
      expect(gateway.permissionRequests, 0);
      expect(coordinator.permissionExplanationRequired, isTrue);
      expect(gateway.startCalls, 0);

      gateway.authorized = true;
      await coordinator.requestPermissionsAndBegin();
      expect(gateway.permissionRequests, 1);
      expect(gateway.startCalls, 1);
      expect(coordinator.isListening, isTrue);
    });

    test('partial results never become a committed final transcript', () async {
      final gateway = _FakeGateway();
      final coordinator = _coordinator(gateway);
      await coordinator.begin(conversationSessionGeneration: 1);

      gateway.emit(
        const SpeechRecognitionPlatformEvent(
          type: SpeechRecognitionPlatformEventType.partialResult,
          transcript: 'un texte partiel',
        ),
      );

      expect(coordinator.visibleTranscript, 'un texte partiel');
      expect(coordinator.takeFinalTranscript(), isNull);
      expect(coordinator.session?.state,
          VoiceRecognitionSessionState.receivingPartialResult);
    });

    test('real platform sound levels update only the current session',
        () async {
      final gateway = _FakeGateway();
      final coordinator = _coordinator(gateway);
      await coordinator.begin(conversationSessionGeneration: 1);
      final oldListener = gateway.listener!;

      gateway.emit(
        const SpeechRecognitionPlatformEvent(
          type: SpeechRecognitionPlatformEventType.soundLevel,
          soundLevel: -24.5,
        ),
      );
      expect(coordinator.soundLevel, -24.5);

      await coordinator.cancel();
      oldListener(
        const SpeechRecognitionPlatformEvent(
          type: SpeechRecognitionPlatformEventType.soundLevel,
          soundLevel: -2,
        ),
      );
      expect(coordinator.soundLevel, 0);
    });

    test('final result remains editable and is never dispatched', () async {
      final gateway = _FakeGateway();
      final coordinator = _coordinator(gateway);
      await coordinator.begin(conversationSessionGeneration: 1);

      gateway.emit(
        const SpeechRecognitionPlatformEvent(
          type: SpeechRecognitionPlatformEventType.finalResult,
          transcript: 'message dicté',
        ),
      );

      expect(coordinator.takeFinalTranscript(), 'message dicté');
      expect(coordinator.isListening, isFalse);
    });

    test('late callbacks from an interrupted session are ignored', () async {
      final gateway = _FakeGateway();
      final coordinator = _coordinator(gateway);
      await coordinator.begin(conversationSessionGeneration: 1);
      final oldListener = gateway.listener!;

      await coordinator.interrupt(VoiceInterruptionReason.applicationPaused);
      oldListener(
        const SpeechRecognitionPlatformEvent(
          type: SpeechRecognitionPlatformEventType.finalResult,
          transcript: 'résultat tardif',
        ),
      );

      expect(coordinator.takeFinalTranscript(), isNull);
      expect(
          coordinator.session?.state, VoiceRecognitionSessionState.interrupted);
    });

    test('background stops listening and resume never restarts it', () async {
      final gateway = _FakeGateway();
      final coordinator = _coordinator(gateway);
      await coordinator.begin(conversationSessionGeneration: 1);

      await coordinator.onLifecycleChanged(AppLifecycleState.paused);
      expect(gateway.cancelCalls, 1);
      await coordinator.onLifecycleChanged(AppLifecycleState.resumed);
      expect(gateway.startCalls, 1);
      expect(coordinator.isListening, isFalse);
    });

    test('double start is refused and context changes isolate sessions',
        () async {
      final gateway = _FakeGateway();
      final coordinator = _coordinator(gateway);
      await coordinator.begin(conversationSessionGeneration: 1);
      await coordinator.begin(conversationSessionGeneration: 1);
      expect(gateway.startCalls, 1);

      await coordinator.invalidateForContextChange(
        VoiceInterruptionReason.accountChanged,
      );
      expect(coordinator.isListening, isFalse);
    });

    test('concurrent starts before permission resolution dispatch once',
        () async {
      final gateway = _FakeGateway()..delayPermissionRead = true;
      final coordinator = _coordinator(gateway);

      final first = coordinator.begin(conversationSessionGeneration: 1);
      await Future<void>.delayed(Duration.zero);
      final second = coordinator.begin(conversationSessionGeneration: 1);
      gateway.completePermissionRead();
      await Future.wait([first, second]);

      expect(gateway.permissionReads, 1);
      expect(gateway.startCalls, 1);
    });

    test('silence times out without synthesizing a message', () async {
      final gateway = _FakeGateway();
      final coordinator = VoiceRecognitionCoordinator(
        gateway: gateway,
        limits: const VoiceRecognitionLimits(
          silenceDuration: Duration(milliseconds: 5),
          maximumSessionDuration: Duration(seconds: 1),
        ),
        idGenerator: () => 'voice-timeout',
      );
      await coordinator.begin(conversationSessionGeneration: 1);
      await Future<void>.delayed(const Duration(milliseconds: 15));

      expect(coordinator.session?.state, VoiceRecognitionSessionState.timedOut);
      expect(coordinator.takeFinalTranscript(), isNull);
      expect(coordinator.failure?.code, VoiceRecognitionFailureCode.noSpeech);
    });

    test('noMatch is mapped to a closed safe failure', () async {
      final gateway = _FakeGateway();
      final coordinator = _coordinator(gateway);
      await coordinator.begin(conversationSessionGeneration: 1);
      gateway.emit(
        const SpeechRecognitionPlatformEvent(
          type: SpeechRecognitionPlatformEventType.failure,
          failure: VoiceRecognitionFailure(
            code: VoiceRecognitionFailureCode.noMatch,
            isRecoverable: true,
          ),
        ),
      );

      expect(coordinator.failure?.code, VoiceRecognitionFailureCode.noMatch);
      expect(coordinator.takeFinalTranscript(), isNull);
    });

    for (final code in [
      VoiceRecognitionFailureCode.noSpeech,
      VoiceRecognitionFailureCode.noMatch,
    ]) {
      test('partial transcript is recovered after ${code.name}', () async {
        final gateway = _FakeGateway();
        final coordinator = _coordinator(gateway);
        await coordinator.begin(conversationSessionGeneration: 1);
        gateway.emit(
          const SpeechRecognitionPlatformEvent(
            type: SpeechRecognitionPlatformEventType.partialResult,
            transcript: 'dernier partiel utile',
          ),
        );

        gateway.emit(
          SpeechRecognitionPlatformEvent(
            type: SpeechRecognitionPlatformEventType.failure,
            failure: VoiceRecognitionFailure(
              code: code,
              isRecoverable: true,
            ),
          ),
        );

        expect(
          coordinator.session?.state,
          VoiceRecognitionSessionState.stoppedWithTranscript,
        );
        expect(coordinator.takeFinalTranscript(), 'dernier partiel utile');
        expect(coordinator.failure, isNull);
        expect(gateway.startCalls, 1);
      });
    }

    test('partial transcript is recovered after silence timeout', () async {
      final gateway = _FakeGateway();
      final coordinator = VoiceRecognitionCoordinator(
        gateway: gateway,
        limits: const VoiceRecognitionLimits(
          silenceDuration: Duration(milliseconds: 5),
          maximumSessionDuration: Duration(seconds: 1),
        ),
        idGenerator: () => 'voice-timeout-partial',
      );
      await coordinator.begin(conversationSessionGeneration: 1);
      gateway.emit(
        const SpeechRecognitionPlatformEvent(
          type: SpeechRecognitionPlatformEventType.partialResult,
          transcript: 'partiel borné',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 15));

      expect(
        coordinator.session?.state,
        VoiceRecognitionSessionState.stoppedWithTranscript,
      );
      expect(coordinator.takeFinalTranscript(), 'partiel borné');
      expect(coordinator.failure, isNull);
    });

    test('empty noSpeech remains a failure without usable transcript',
        () async {
      final gateway = _FakeGateway();
      final coordinator = _coordinator(gateway);
      await coordinator.begin(conversationSessionGeneration: 1);

      gateway.emit(
        const SpeechRecognitionPlatformEvent(
          type: SpeechRecognitionPlatformEventType.failure,
          failure: VoiceRecognitionFailure(
            code: VoiceRecognitionFailureCode.noSpeech,
            isRecoverable: true,
          ),
        ),
      );

      expect(coordinator.failure?.code, VoiceRecognitionFailureCode.noSpeech);
      expect(coordinator.takeFinalTranscript(), isNull);
    });

    test('restart after recovery creates one isolated native session',
        () async {
      final gateway = _FakeGateway();
      var sequence = 0;
      final coordinator = VoiceRecognitionCoordinator(
        gateway: gateway,
        idGenerator: () => 'voice-${++sequence}',
      );
      await coordinator.begin(conversationSessionGeneration: 1);
      final oldListener = gateway.listener!;
      gateway.emit(
        const SpeechRecognitionPlatformEvent(
          type: SpeechRecognitionPlatformEventType.partialResult,
          transcript: 'ancienne session',
        ),
      );
      gateway.emit(
        const SpeechRecognitionPlatformEvent(
          type: SpeechRecognitionPlatformEventType.failure,
          failure: VoiceRecognitionFailure(
            code: VoiceRecognitionFailureCode.noMatch,
            isRecoverable: true,
          ),
        ),
      );

      await coordinator.begin(conversationSessionGeneration: 1);
      expect(gateway.startCalls, 2);
      expect(coordinator.session?.voiceSessionId, 'voice-2');
      oldListener(
        const SpeechRecognitionPlatformEvent(
          type: SpeechRecognitionPlatformEventType.finalResult,
          transcript: 'ancien résultat tardif',
        ),
      );
      expect(coordinator.takeFinalTranscript(), isNull);
    });

    test('cancel removes a recovered transcript without dispatch', () async {
      final gateway = _FakeGateway();
      final coordinator = _coordinator(gateway);
      await coordinator.begin(conversationSessionGeneration: 1);
      gateway.emit(
        const SpeechRecognitionPlatformEvent(
          type: SpeechRecognitionPlatformEventType.partialResult,
          transcript: 'texte récupéré',
        ),
      );
      gateway.emit(
        const SpeechRecognitionPlatformEvent(
          type: SpeechRecognitionPlatformEventType.failure,
          failure: VoiceRecognitionFailure(
            code: VoiceRecognitionFailureCode.noSpeech,
            isRecoverable: true,
          ),
        ),
      );

      await coordinator.cancel();
      expect(coordinator.takeFinalTranscript(), isNull);
      expect(
        coordinator.session?.state,
        VoiceRecognitionSessionState.cancelled,
      );
    });
  });

  test('architecture keeps plugin and permissions out of ChatScreen', () {
    final source = File('lib/screens/chat_screen.dart').readAsStringSync();
    expect(source, isNot(contains('speech_to_text')));
    expect(source, isNot(contains('SpeechToText')));
    expect(source, isNot(contains('Permission.')));
    expect(source, isNot(contains('.listen(')));
    expect(source, isNot(contains('onResult:')));
  });

  test('speech plugin listen is isolated to the canonical gateway', () {
    final production = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();
    final directListeners = production
        .where((file) => file.readAsStringSync().contains('_speech.listen('))
        .map((file) => file.path)
        .toList();
    expect(directListeners, ['lib/services/voice_service.dart']);
  });

  for (final size in const [Size(390, 844), Size(1024, 1366)]) {
    testWidgets('voice control is accessible at $size with text scale 1.6',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final coordinator = _coordinator(_FakeGateway());

      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: const TextScaler.linear(1.6),
          ),
          child: MaterialApp(
            home: Scaffold(
              body: VoiceInputControl(
                coordinator: coordinator,
                conversationSessionGeneration: 1,
                onTranscriptReady: (_) {},
                idleBuilder: _idleVoiceButton,
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('voice-primary')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('permission explanation precedes the native request',
      (tester) async {
    final gateway = _FakeGateway(authorized: false);
    final coordinator = _coordinator(gateway);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VoiceInputControl(
            coordinator: coordinator,
            conversationSessionGeneration: 1,
            onTranscriptReady: (_) {},
            idleBuilder: _idleVoiceButton,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('voice-primary')));
    await tester.pumpAndSettle();
    expect(find.text('Autoriser la dictée'), findsOneWidget);
    expect(gateway.permissionRequests, 0);

    gateway.authorized = true;
    await tester.tap(find.text('Autoriser le microphone'));
    await tester.pumpAndSettle();
    expect(gateway.permissionRequests, 1);
    await coordinator.cancel();
  });

  testWidgets('widget rebuild never starts another native session',
      (tester) async {
    final gateway = _FakeGateway();
    final coordinator = _coordinator(gateway);
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: Column(
              children: [
                VoiceInputControl(
                  coordinator: coordinator,
                  conversationSessionGeneration: 1,
                  onTranscriptReady: (_) {},
                  idleBuilder: _idleVoiceButton,
                ),
                TextButton(
                  onPressed: () => setState(() {}),
                  child: const Text('Rebuild'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('voice-primary')));
    await tester.pump();
    await tester.tap(find.text('Rebuild'));
    await tester.pump();

    expect(gateway.startCalls, 1);
    await coordinator.cancel();
  });

  testWidgets('recording visualizer reacts to real sound-level callbacks',
      (tester) async {
    final gateway = _FakeGateway();
    final coordinator = _coordinator(gateway);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VoiceInputControl(
            coordinator: coordinator,
            conversationSessionGeneration: 1,
            onTranscriptReady: (_) {},
            idleBuilder: _idleVoiceButton,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('voice-primary')));
    await tester.pump();
    gateway.emit(
      const SpeechRecognitionPlatformEvent(
        type: SpeechRecognitionPlatformEventType.soundLevel,
        soundLevel: -50,
      ),
    );
    await tester.pump();
    final quietValue =
        tester.getSemantics(find.byKey(const Key('voice-sound-level'))).value;
    gateway.emit(
      const SpeechRecognitionPlatformEvent(
        type: SpeechRecognitionPlatformEventType.soundLevel,
        soundLevel: -10,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final loudValue =
        tester.getSemantics(find.byKey(const Key('voice-sound-level'))).value;

    expect(quietValue, isNot(loudValue));
    expect(
      int.parse(loudValue.replaceAll(RegExp(r'\D'), '')),
      greaterThan(int.parse(quietValue.replaceAll(RegExp(r'\D'), ''))),
    );
    await coordinator.cancel();
  });
}

VoiceRecognitionCoordinator _coordinator(_FakeGateway gateway) =>
    VoiceRecognitionCoordinator(
      gateway: gateway,
      idGenerator: () => 'voice-session',
    );

Widget _idleVoiceButton(BuildContext context, VoidCallback? onPressed) =>
    IconButton(
      key: const Key('voice-primary'),
      onPressed: onPressed,
      icon: const Icon(Icons.mic),
    );

final class _FakeGateway implements SpeechRecognitionPlatformGateway {
  _FakeGateway({this.authorized = true});

  bool authorized;
  int permissionRequests = 0;
  int permissionReads = 0;
  int startCalls = 0;
  int cancelCalls = 0;
  bool delayPermissionRead = false;
  Completer<void>? _permissionReadGate;
  void Function(SpeechRecognitionPlatformEvent event)? listener;

  void emit(SpeechRecognitionPlatformEvent event) => listener?.call(event);

  VoicePermissionState get permissionState => VoicePermissionState(
        microphone: authorized
            ? VoicePermissionStatus.authorized
            : VoicePermissionStatus.notDetermined,
        speechRecognition: authorized
            ? VoicePermissionStatus.authorized
            : VoicePermissionStatus.notDetermined,
        checkedAt: DateTime.utc(2026),
        canRequest: !authorized,
        canOpenSettings: false,
      );

  @override
  Future<VoiceRecognitionAvailability> checkAvailability() async =>
      VoiceRecognitionAvailability.available;

  @override
  Future<String?> currentLocale() async => 'fr_FR';

  @override
  Future<void> dispose() async {}

  @override
  Future<bool> initialize(
    void Function(SpeechRecognitionPlatformEvent event) onEvent,
  ) async {
    listener = onEvent;
    return true;
  }

  @override
  Future<bool> openSettings() async => true;

  @override
  Future<VoicePermissionState> readPermissions() async {
    permissionReads++;
    if (delayPermissionRead) {
      _permissionReadGate ??= Completer<void>();
      await _permissionReadGate!.future;
    }
    return permissionState;
  }

  void completePermissionRead() {
    _permissionReadGate?.complete();
  }

  @override
  Future<VoicePermissionState> requestPermissions() async {
    permissionRequests++;
    return permissionState;
  }

  @override
  Future<String> startListening({
    required String localeId,
    required Duration listenFor,
    required Duration pauseFor,
  }) async {
    startCalls++;
    return 'platform-$startCalls';
  }

  @override
  Future<void> stopListening() async {}

  @override
  Future<void> cancelListening() async {
    cancelCalls++;
  }

  @override
  Future<List<String>> supportedLocales() async => const ['fr_FR'];
}
