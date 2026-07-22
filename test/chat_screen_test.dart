import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/chat_backend_request.dart';
import 'package:moms_ai/models/chat_backend_response.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/screens/chat_screen.dart';
import 'package:moms_ai/services/chat_backend_client.dart';
import 'package:moms_ai/services/conversation_context_service.dart';

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
    expect(backend.requests.single.toJson(), {
      'message': 'Bonjour Zélia',
      'profile': _profile().toJson(),
      'profileContext': const <String, dynamic>{},
      'memories': const <Map<String, dynamic>>[],
      'memoryReasoning': const <Map<String, dynamic>>[],
      'events': const <Map<String, dynamic>>[],
    });
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
    return ChatBackendRequest(
      message: message,
      profile: profile.toJson(),
      profileContext: const {},
      memories: const [],
      memoryReasoning: const [],
      events: const [],
    );
  }

  @override
  Future<void> saveResponseMemory(dynamic memory) async {}
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
