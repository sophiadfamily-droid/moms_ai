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
      'dictation stays editable and only the send button reaches Conversation',
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
    gateway.emit(
      const SpeechRecognitionPlatformEvent(
        type: SpeechRecognitionPlatformEventType.partialResult,
        transcript: 'texte provisoire',
      ),
    );
    await tester.pump();
    expect(backend.requests, isEmpty);
    expect(find.text('texte provisoire'), findsOneWidget);

    gateway.emit(
      const SpeechRecognitionPlatformEvent(
        type: SpeechRecognitionPlatformEventType.finalResult,
        transcript: 'texte final',
      ),
    );
    await tester.pump();
    expect(backend.requests, isEmpty);
    await tester.tap(find.byKey(const Key('voice-use-text')));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'texte final',
    );
    expect(backend.requests, isEmpty);

    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(backend.requests, hasLength(1));
    expect(backend.requests.single.message, 'texte final');
  });

  testWidgets(
      'recovered Android partial only fills the composer after explicit use',
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
    expect(find.byKey(const Key('voice-use-text')), findsOneWidget);
    expect(find.byKey(const Key('voice-cancel')), findsOneWidget);

    await tester.tap(find.byKey(const Key('voice-use-text')));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'partiel récupéré',
    );
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
  }) async =>
      'platform-widget';

  @override
  Future<void> stopListening() async {}

  @override
  Future<void> cancelListening() async {}

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
