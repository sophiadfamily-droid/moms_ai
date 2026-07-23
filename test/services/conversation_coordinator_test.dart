import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/chat_backend_request.dart';
import 'package:moms_ai/models/chat_backend_response.dart';
import 'package:moms_ai/models/conversation_models.dart';
import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/services/chat_backend_client.dart';
import 'package:moms_ai/services/conversation_context_service.dart';
import 'package:moms_ai/services/conversation_coordinator.dart';

void main() {
  group('ConversationCoordinator', () {
    test('sends a normal message with the unchanged backend request', () async {
      final request = _request(message: 'Bonjour');
      final backend = _FakeBackend(
        response: const ChatBackendResponse(
          reply: 'Bonjour 💕',
          actions: [],
          memories: [],
        ),
      );
      final context = _FakeContextProvider(request);
      final coordinator = ConversationCoordinator(
        backend: backend,
        contextProvider: context,
      );

      final outcome = await coordinator.send(
        input: ConversationInput(message: 'Bonjour', profile: _profile()),
        executeAction: (_) async => const ConversationActionOutcome(),
      );

      expect(outcome?.reply, 'Bonjour 💕');
      expect(identical(outcome?.request, request), isTrue);
      expect(identical(backend.requests.single, request), isTrue);
      expect(request.toJson().keys, {
        'schemaVersion',
        'message',
        'conversationContext',
        'conversationHistory',
        'profile',
        'profileContext',
        'memories',
        'memoryReasoning',
        'events',
      });
      expect(coordinator.state.phase, ConversationPhase.idle);
    });

    test('delegates an accepted action and preserves its confirmation reply',
        () async {
      final backend = _FakeBackend(
        response: const ChatBackendResponse(
          reply: 'Réponse initiale',
          actions: [
            {
              'type': 'event',
              'title': 'Médecin',
              'date': '2026-07-21',
              'time': '10:00',
              'durationMinutes': 30,
            },
          ],
          memories: [],
        ),
      );
      final coordinator = ConversationCoordinator(
        backend: backend,
        contextProvider: _FakeContextProvider(_request()),
      );
      var executions = 0;

      final outcome = await coordinator.send(
        input: ConversationInput(
            message: 'Ajoute le rendez-vous', profile: _profile()),
        executeAction: (action) async {
          executions++;
          expect(action['title'], 'Médecin');
          return const ConversationActionOutcome(
            message: 'Confirmer le rendez-vous ?',
          );
        },
      );

      expect(executions, 1);
      expect(outcome?.reply, 'Confirmer le rendez-vous ?');
    });

    test('keeps a pending event after an unrecognized answer', () async {
      final coordinator = _coordinator();
      final event = _event();
      coordinator.setPendingEventConfirmation(event);

      final resolution = await coordinator.resolvePendingEventConfirmation(
        answer: 'peut-être',
        isPositiveAnswer: (value) => value == 'oui',
        isNegativeAnswer: (value) => value == 'non',
        cancellationMessage: (_) => 'Annulé',
        expectedAnswerMessage: () => 'Réponds oui ou non',
        execute: (_) async => 'Créé',
      );

      expect(resolution?.message, 'Réponds oui ou non');
      expect(coordinator.state.pendingAction?.event, same(event));
      expect(
        coordinator.state.phase,
        ConversationPhase.awaitingActionConfirmation,
      );
    });

    test('cancels and clears a pending event', () async {
      final coordinator = _coordinator();
      coordinator.setPendingEventConfirmation(_event());

      final resolution = await coordinator.resolvePendingEventConfirmation(
        answer: 'non',
        isPositiveAnswer: (value) => value == 'oui',
        isNegativeAnswer: (value) => value == 'non',
        cancellationMessage: (_) => 'Annulé',
        expectedAnswerMessage: () => 'Réponds oui ou non',
        execute: (_) async => 'Créé',
      );

      expect(resolution?.message, 'Annulé');
      expect(coordinator.state.pendingAction, isNull);
      expect(coordinator.state.phase, ConversationPhase.idle);
    });

    test('confirms once and clears a pending event after execution', () async {
      final coordinator = _coordinator();
      coordinator.setPendingEventConfirmation(_event());
      var executions = 0;

      final resolution = await coordinator.resolvePendingEventConfirmation(
        answer: 'oui',
        isPositiveAnswer: (value) => value == 'oui',
        isNegativeAnswer: (value) => value == 'non',
        cancellationMessage: (_) => 'Annulé',
        expectedAnswerMessage: () => 'Réponds oui ou non',
        execute: (_) async {
          executions++;
          return 'Créé';
        },
      );
      final repeated = await coordinator.resolvePendingEventConfirmation(
        answer: 'oui',
        isPositiveAnswer: (_) => true,
        isNegativeAnswer: (_) => false,
        cancellationMessage: (_) => 'Annulé',
        expectedAnswerMessage: () => 'Réponds oui ou non',
        execute: (_) async {
          executions++;
          return 'Créé';
        },
      );

      expect(resolution?.message, 'Créé');
      expect(repeated, isNull);
      expect(executions, 1);
      expect(coordinator.state.pendingAction, isNull);
    });

    test('keeps a pending event when confirmation execution fails', () async {
      final coordinator = _coordinator();
      final event = _event();
      final error = StateError('persistence failed');
      coordinator.setPendingEventConfirmation(event);

      await expectLater(
        coordinator.resolvePendingEventConfirmation(
          answer: 'oui',
          isPositiveAnswer: (value) => value == 'oui',
          isNegativeAnswer: (value) => value == 'non',
          cancellationMessage: (_) => 'Annulé',
          expectedAnswerMessage: () => 'Réponds oui ou non',
          execute: (_) async => throw error,
        ),
        throwsA(same(error)),
      );

      expect(coordinator.state.pendingAction?.event, same(event));
      expect(
        coordinator.state.phase,
        ConversationPhase.awaitingActionConfirmation,
      );
    });

    test('does not start a second backend execution while sending', () async {
      final completer = Completer<ChatBackendResponse>();
      final backend = _FakeBackend(pendingResponse: completer.future);
      final coordinator = ConversationCoordinator(
        backend: backend,
        contextProvider: _FakeContextProvider(_request()),
      );
      final input = ConversationInput(message: 'Bonjour', profile: _profile());

      final first = coordinator.send(
        input: input,
        executeAction: (_) async => const ConversationActionOutcome(),
      );
      await Future<void>.delayed(Duration.zero);
      final second = await coordinator.send(
        input: input,
        executeAction: (_) async => const ConversationActionOutcome(),
      );

      expect(second, isNull);
      expect(backend.requests, hasLength(1));
      completer.complete(
        const ChatBackendResponse(reply: 'OK', actions: [], memories: []),
      );
      expect((await first)?.reply, 'OK');
    });

    test('propagates backend errors and restores idle state', () async {
      final error = StateError('backend failed');
      final coordinator = ConversationCoordinator(
        backend: _FakeBackend(error: error),
        contextProvider: _FakeContextProvider(_request()),
      );

      await expectLater(
        coordinator.send(
          input: ConversationInput(message: 'Bonjour', profile: _profile()),
          executeAction: (_) async => const ConversationActionOutcome(),
        ),
        throwsA(same(error)),
      );
      expect(coordinator.state.phase, ConversationPhase.idle);
    });

    test('delegates returned memories to the context provider', () async {
      final context = _FakeContextProvider(_request());
      final coordinator = ConversationCoordinator(
        backend: _FakeBackend(
          response: const ChatBackendResponse(
            reply: 'Noté',
            actions: [],
            memories: [
              {'text': 'Préférence stable'},
            ],
          ),
        ),
        contextProvider: context,
      );

      await coordinator.send(
        input: ConversationInput(message: 'Retiens ceci', profile: _profile()),
        executeAction: (_) async => const ConversationActionOutcome(),
      );

      expect(context.savedMemories, [
        {'text': 'Préférence stable'},
      ]);
    });
  });
}

class _FakeBackend implements ChatBackendClient {
  final ChatBackendResponse? response;
  final Future<ChatBackendResponse>? pendingResponse;
  final Object? error;
  final List<ChatBackendRequest> requests = [];

  _FakeBackend({this.response, this.pendingResponse, this.error});

  @override
  Future<ChatBackendResponse> send(ChatBackendRequest request) async {
    requests.add(request);
    if (error != null) throw error!;
    if (pendingResponse != null) return pendingResponse!;
    return response ??
        const ChatBackendResponse(reply: 'OK', actions: [], memories: []);
  }
}

class _FakeContextProvider implements ConversationContextProvider {
  final ChatBackendRequest request;
  final List<dynamic> savedMemories = [];

  _FakeContextProvider(this.request);

  @override
  Future<ChatBackendRequest> buildRequest({
    required String message,
    required UserProfile profile,
  }) async {
    return request;
  }

  @override
  Future<void> saveResponseMemory(dynamic memory) async {
    savedMemories.add(memory);
  }
}

ConversationCoordinator _coordinator() {
  return ConversationCoordinator(
    backend: _FakeBackend(),
    contextProvider: _FakeContextProvider(_request()),
  );
}

ChatBackendRequest _request({String message = 'message'}) {
  return ChatBackendRequest.withUnavailableContext(
    message: message,
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

EventModel _event() {
  return EventModel(
    title: 'Médecin',
    date: '2026-07-21',
    time: '10:00',
    notes: '',
    category: 'Personnel',
    createdAt: DateTime(2026, 7, 20),
    startDateTimeIso: '2026-07-21T10:00:00',
    durationMinutes: 30,
  );
}
