import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/chat_backend_request.dart';
import 'package:moms_ai/models/chat_backend_response.dart';
import 'package:moms_ai/models/conversation_models.dart';
import 'package:moms_ai/models/conversation_session_models.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/services/chat_backend_client.dart';
import 'package:moms_ai/services/conversation_context_service.dart';
import 'package:moms_ai/services/conversation_coordinator.dart';
import 'package:moms_ai/services/conversation_session_controller.dart';

void main() {
  group('canonical conversation session orchestration', () {
    test('starts immutable, versioned and without public account data', () {
      final harness = _Harness();
      final state = harness.controller.state;
      expect(state.schemaVersion, 1);
      expect(state.phase, ConversationSessionPhase.ready);
      expect(state.messages, isEmpty);
      expect(() => state.messages.add(_message()), throwsUnsupportedError);
      expect(state.sessionId, isNot(contains('uid')));
      harness.dispose();
    });

    test('submits once and preserves visible message order', () async {
      final harness = _Harness();
      await harness.controller.dispatch(SubmitConversationText('Bonjour'));

      expect(harness.context.calls, 1);
      expect(harness.backend.calls, 1);
      expect(
        harness.controller.state.messages.map((message) => message.role),
        [
          ConversationMessageRole.user,
          ConversationMessageRole.assistant,
        ],
      );
      expect(
        harness.controller.state.messages.map((message) => message.text),
        ['Bonjour', 'Réponse'],
      );
      expect(harness.store.values, hasLength(2));
      expect(harness.controller.state.phase, ConversationSessionPhase.ready);
      harness.dispose();
    });

    test('double submit while active is ignored', () async {
      final completer = Completer<ChatBackendResponse>();
      final harness = _Harness(pending: completer.future);
      final first = harness.controller.submitText('Bonjour');
      await Future<void>.delayed(Duration.zero);
      await harness.controller.submitText('Deuxième');

      expect(harness.context.calls, 1);
      expect(harness.controller.state.messages, hasLength(1));
      completer.complete(_response());
      await first;
      expect(harness.controller.state.messages, hasLength(2));
      harness.dispose();
    });

    test('logical cancellation ignores a late response', () async {
      final completer = Completer<ChatBackendResponse>();
      final harness = _Harness(pending: completer.future);
      final request = harness.controller.submitText('Bonjour');
      await Future<void>.delayed(Duration.zero);
      await harness.controller.cancelCurrentRequest();
      completer.complete(_response());
      await request;

      expect(harness.controller.state.messages, hasLength(1));
      expect(harness.controller.state.phase, ConversationSessionPhase.ready);
      harness.dispose();
    });

    test('retry is bounded and does not duplicate the user message', () async {
      final harness = _Harness(error: ChatBackendTimeoutException());
      await harness.controller.submitText('Bonjour');
      expect(harness.controller.state.retryAvailable, isTrue);
      await harness.controller.retryLastRequest();
      await harness.controller.retryLastRequest();

      expect(
        harness.controller.state.messages
            .where((message) => message.role == ConversationMessageRole.user),
        hasLength(1),
      );
      expect(harness.backend.calls, 2);
      expect(harness.controller.state.retryAvailable, isFalse);
      harness.dispose();
    });

    test('account change isolates messages and invalidates old response',
        () async {
      final completer = Completer<ChatBackendResponse>();
      final harness = _Harness(pending: completer.future);
      final request = harness.controller.submitText('Bonjour');
      await Future<void>.delayed(Duration.zero);
      final oldSession = harness.controller.state.sessionId;
      harness.controller.changeAccount(_profile(firstName: 'Autre'));
      completer.complete(_response());
      await request;

      expect(harness.controller.state.sessionId, isNot(oldSession));
      expect(harness.controller.state.messages, isEmpty);
      harness.dispose();
    });

    test('effects are consumed once', () async {
      final harness = _Harness();
      await harness.controller.submitText('Bonjour');
      final effect = harness.controller.state.effects.first;
      await harness.controller.dispatch(ConsumeConversationEffect(effect.id));
      expect(
        harness.controller.state.effects.any((item) => item.id == effect.id),
        isFalse,
      );
      harness.dispose();
    });

    test('dispose prevents late state application', () async {
      final completer = Completer<ChatBackendResponse>();
      final harness = _Harness(pending: completer.future);
      final request = harness.controller.submitText('Bonjour');
      await Future<void>.delayed(Duration.zero);
      harness.controller.dispose();
      completer.complete(_response());
      await request;
      expect(harness.backend.calls, 1);
    });
  });
}

final class _Harness {
  _Harness({
    Future<ChatBackendResponse>? pending,
    Object? error,
  })  : backend = _Backend(pending: pending, error: error),
        context = _Context(),
        store = _Store() {
    coordinator = ConversationCoordinator(
      backend: backend,
      contextProvider: context,
    );
    var id = 0;
    controller = ConversationSessionController(
      profile: _profile(),
      coordinator: coordinator,
      executeAction: (_, __) async => const ConversationActionOutcome(),
      messageStore: store,
      idGenerator: () => 'technical-${++id}',
      clock: () => DateTime.utc(2026, 7, 23),
    );
  }

  final _Backend backend;
  final _Context context;
  final _Store store;
  late final ConversationCoordinator coordinator;
  late final ConversationSessionController controller;

  void dispose() => controller.dispose();
}

final class _Backend implements ChatBackendClient {
  _Backend({this.pending, this.error});

  final Future<ChatBackendResponse>? pending;
  final Object? error;
  int calls = 0;

  @override
  Future<ChatBackendResponse> send(ChatBackendRequest request) async {
    calls++;
    if (error != null) throw error!;
    return pending ?? Future.value(_response());
  }
}

final class _Context implements ConversationContextProvider {
  int calls = 0;

  @override
  Future<ChatBackendRequest> buildRequest({
    required String message,
    required UserProfile profile,
  }) async {
    calls++;
    return ChatBackendRequest(
      message: message,
      profile: const {},
      profileContext: const {},
      memories: const [],
      memoryReasoning: const [],
      events: const [],
    );
  }

  @override
  Future<void> saveResponseMemory(dynamic memory) async {}
}

final class _Store implements ConversationMessageStore {
  final List<String> values = [];

  @override
  Future<void> save({
    required String sessionId,
    required ConversationMessageRole role,
    required String text,
  }) async {
    values.add('${role.name}:$text');
  }
}

ChatBackendResponse _response() =>
    const ChatBackendResponse(reply: 'Réponse', actions: [], memories: []);

ConversationVisibleMessage _message() => ConversationVisibleMessage(
      id: 'message',
      role: ConversationMessageRole.user,
      text: 'texte',
      createdAt: DateTime.utc(2026, 7, 23),
    );

UserProfile _profile({String firstName = 'Sophia'}) => UserProfile(
      firstName: firstName,
      familyStatus: '',
      workStatus: '',
      partnerName: '',
      wantsNotifications: true,
      children: const [],
    );
