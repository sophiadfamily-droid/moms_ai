import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/chat_backend_request.dart';
import 'package:moms_ai/models/chat_backend_response.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/models/voice_recognition.dart';
import 'package:moms_ai/screens/chat_screen.dart';
import 'package:moms_ai/services/chat_backend_client.dart';
import 'package:moms_ai/services/conversation_context_service.dart';
import 'package:moms_ai/services/voice_recognition_coordinator.dart';
import 'package:moms_ai/services/voice_service.dart';

void main() {
  testWidgets('ChatScreen keeps the visible user and assistant message order',
      (tester) async {
    final backend = _WidgetBackend();
    final context = _WidgetContextProvider();

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          profile: _profile(),
          backendClient: backend,
          conversationContextProvider: context,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Bonjour Zélia');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(find.text('Bonjour Zélia'), findsOneWidget);
    expect(find.text('Bonjour 💕'), findsOneWidget);
    expect(backend.requests, hasLength(1));
    final payload = backend.requests.single.toJson();
    expect(payload['schemaVersion'], 2);
    expect(payload['message'], 'Bonjour Zélia');
    expect(
      (payload['conversationContext'] as Map)['state'],
      'unavailable',
    );
    expect(payload['profile'], isEmpty);
    expect(payload['memoryReasoning'], isEmpty);
  });

  testWidgets('ChatScreen never exposes a raw backend failure', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          profile: _profile(),
          backendClient: _FailingWidgetBackend(),
          conversationContextProvider: _WidgetContextProvider(),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Message privé');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(find.textContaining('private provider detail'), findsNothing);
    expect(
      find.text(
        'Zélia rencontre un problème temporaire. Tes données ne sont pas perdues.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'recording capsule validates editable text and only Send reaches Conversation',
      (tester) async {
    final backend = _WidgetBackend();
    final gateway = _WidgetVoiceGateway();
    final voice = VoiceRecognitionCoordinator(
      gateway: gateway,
      idGenerator: () => 'voice-widget',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          profile: _profile(),
          backendClient: backend,
          conversationContextProvider: _WidgetContextProvider(),
          voiceCoordinator: voice,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('voice-primary')));
    await tester.pump();
    expect(find.byKey(const Key('voice-recording-capsule')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(const Key('voice-use-text')), findsNothing);
    expect(gateway.startCalls, 1);
    await tester.tap(find.byKey(const Key('voice-recording-capsule')));
    await tester.pump();
    expect(gateway.startCalls, 1);

    gateway.emit(
      const SpeechRecognitionPlatformEvent(
        type: SpeechRecognitionPlatformEventType.partialResult,
        transcript: 'texte provisoire',
      ),
    );
    await tester.pump();
    expect(backend.requests, isEmpty);
    expect(find.text('texte provisoire'), findsNothing);
    expect(find.byType(TextField), findsNothing);

    gateway.emit(
      const SpeechRecognitionPlatformEvent(
        type: SpeechRecognitionPlatformEventType.finalResult,
        transcript: 'texte final',
      ),
    );
    await tester.pump();
    expect(backend.requests, isEmpty);
    await tester.tap(find.byKey(const Key('voice-validate')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'texte final',
    );
    expect(backend.requests, isEmpty);
    expect(find.byKey(const Key('voice-use-text')), findsNothing);

    await tester.enterText(find.byType(TextField), 'texte final corrigé');
    await tester.pump();

    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(backend.requests, hasLength(1));
    expect(backend.requests.single.message, 'texte final corrigé');
  });

  testWidgets(
      'recovered Android partial only fills the composer after validation',
      (tester) async {
    final backend = _WidgetBackend();
    final gateway = _WidgetVoiceGateway();
    final voice = VoiceRecognitionCoordinator(
      gateway: gateway,
      idGenerator: () => 'voice-recovered',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          profile: _profile(),
          backendClient: backend,
          conversationContextProvider: _WidgetContextProvider(),
          voiceCoordinator: voice,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('voice-primary')));
    await tester.pump();
    gateway.emit(
      const SpeechRecognitionPlatformEvent(
        type: SpeechRecognitionPlatformEventType.partialResult,
        transcript: 'partiel récupéré',
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
    await tester.pump();

    expect(backend.requests, isEmpty);
    expect(
        find.text("Je n'ai rien entendu. Tu peux recommencer."), findsNothing);
    expect(find.byKey(const Key('voice-validate')), findsOneWidget);
    expect(find.byKey(const Key('voice-cancel')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.byKey(const Key('voice-validate')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'partiel récupéré',
    );
    expect(backend.requests, isEmpty);
  });

  testWidgets('cancel preserves an existing draft and sends nothing',
      (tester) async {
    final backend = _WidgetBackend();
    final gateway = _WidgetVoiceGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          profile: _profile(),
          backendClient: backend,
          conversationContextProvider: _WidgetContextProvider(),
          voiceCoordinator: VoiceRecognitionCoordinator(gateway: gateway),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Mon brouillon');
    await tester.tap(find.byKey(const Key('voice-primary')));
    await tester.pump();
    gateway.emit(
      const SpeechRecognitionPlatformEvent(
        type: SpeechRecognitionPlatformEventType.partialResult,
        transcript: 'à supprimer',
      ),
    );
    await tester.tap(find.byKey(const Key('voice-cancel')));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, 'Mon brouillon');
    expect(backend.requests, isEmpty);
  });

  testWidgets('validation inserts at the cursor and never overwrites the draft',
      (tester) async {
    final backend = _WidgetBackend();
    final gateway = _WidgetVoiceGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          profile: _profile(),
          backendClient: backend,
          conversationContextProvider: _WidgetContextProvider(),
          voiceCoordinator: VoiceRecognitionCoordinator(gateway: gateway),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Bonjour demain');
    final controller =
        tester.widget<TextField>(find.byType(TextField)).controller!;
    controller.selection = const TextSelection.collapsed(offset: 7);
    await tester.tap(find.byKey(const Key('voice-primary')));
    await tester.pump();
    gateway.emit(
      const SpeechRecognitionPlatformEvent(
        type: SpeechRecognitionPlatformEventType.finalResult,
        transcript: 'Zélia',
      ),
    );
    await tester.tap(find.byKey(const Key('voice-validate')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.text, 'Bonjour Zélia demain');
    expect(controller.selection, const TextSelection.collapsed(offset: 13));
    expect(backend.requests, isEmpty);
  });

  testWidgets('empty validation inserts and sends nothing and shows feedback',
      (tester) async {
    final backend = _WidgetBackend();
    final gateway = _WidgetVoiceGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          profile: _profile(),
          backendClient: backend,
          conversationContextProvider: _WidgetContextProvider(),
          voiceCoordinator: VoiceRecognitionCoordinator(gateway: gateway),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('voice-primary')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('voice-validate')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      isEmpty,
    );
    expect(find.text('Je n’ai pas bien entendu. Réessaie.'), findsOneWidget);
    expect(backend.requests, isEmpty);
  });

  testWidgets('double validation never duplicates the transcript',
      (tester) async {
    final gateway = _WidgetVoiceGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          profile: _profile(),
          backendClient: _WidgetBackend(),
          conversationContextProvider: _WidgetContextProvider(),
          voiceCoordinator: VoiceRecognitionCoordinator(gateway: gateway),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('voice-primary')));
    await tester.pump();
    gateway.emit(
      const SpeechRecognitionPlatformEvent(
        type: SpeechRecognitionPlatformEventType.partialResult,
        transcript: 'une seule fois',
      ),
    );
    final validate = find.byKey(const Key('voice-validate'));
    await tester.tap(validate);
    await tester.tap(validate);
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'une seule fois',
    );
  });

  testWidgets('background stops recording without inserting or sending',
      (tester) async {
    final backend = _WidgetBackend();
    final gateway = _WidgetVoiceGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          profile: _profile(),
          backendClient: backend,
          conversationContextProvider: _WidgetContextProvider(),
          voiceCoordinator: VoiceRecognitionCoordinator(gateway: gateway),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('voice-primary')));
    await tester.pump();
    gateway.emit(
      const SpeechRecognitionPlatformEvent(
        type: SpeechRecognitionPlatformEventType.partialResult,
        transcript: 'ne pas insérer',
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      isEmpty,
    );
    expect(gateway.cancelCalls, 1);
    expect(backend.requests, isEmpty);
  });
}

class _WidgetBackend implements ChatBackendClient {
  final List<ChatBackendRequest> requests = [];

  @override
  Future<ChatBackendResponse> send(ChatBackendRequest request) async {
    requests.add(request);
    return const ChatBackendResponse(
      reply: 'Bonjour 💕',
      actions: [],
      memories: [],
    );
  }
}

class _FailingWidgetBackend implements ChatBackendClient {
  @override
  Future<ChatBackendResponse> send(ChatBackendRequest request) async {
    throw Exception('private provider detail');
  }
}

class _WidgetContextProvider implements ConversationContextProvider {
  @override
  Future<ChatBackendRequest> buildRequest({
    required String message,
    required UserProfile profile,
  }) async {
    return ChatBackendRequest.withUnavailableContext(
      message: message,
    );
  }

  @override
  Future<void> saveResponseMemory(dynamic memory) async {}
}

final class _WidgetVoiceGateway implements SpeechRecognitionPlatformGateway {
  void Function(SpeechRecognitionPlatformEvent event)? _listener;
  int startCalls = 0;
  int cancelCalls = 0;

  void emit(SpeechRecognitionPlatformEvent event) => _listener?.call(event);

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
    _listener = onEvent;
    return true;
  }

  @override
  Future<bool> openSettings() async => true;

  @override
  Future<VoicePermissionState> readPermissions() async =>
      _authorizedPermission();

  @override
  Future<VoicePermissionState> requestPermissions() async =>
      _authorizedPermission();

  @override
  Future<String> startListening({
    required String localeId,
    required Duration listenFor,
    required Duration pauseFor,
  }) async {
    startCalls++;
    return 'platform-widget';
  }

  @override
  Future<void> stopListening() async {}

  @override
  Future<void> cancelListening() async {
    cancelCalls++;
  }

  @override
  Future<List<String>> supportedLocales() async => const ['fr_FR'];

  VoicePermissionState _authorizedPermission() => VoicePermissionState(
        microphone: VoicePermissionStatus.authorized,
        speechRecognition: VoicePermissionStatus.authorized,
        checkedAt: DateTime.utc(2026),
        canRequest: false,
        canOpenSettings: false,
      );
}

UserProfile _profile() {
  return UserProfile(
    firstName: 'Sophia',
    familyStatus: '',
    workStatus: '',
    partnerName: '',
    wantsNotifications: true,
    children: const [],
  );
}
