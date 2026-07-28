import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/chat_backend_request.dart';
import 'package:moms_ai/models/chat_backend_response.dart';
import 'package:moms_ai/models/conversation_models.dart';
import 'package:moms_ai/models/conversation_epistemic_models.dart';
import 'package:moms_ai/models/conversation_session_models.dart';
import 'package:moms_ai/models/priority/proactive_priority_models.dart';
import 'package:moms_ai/models/smart_planning_continuation.dart';
import 'package:moms_ai/models/task_model.dart';
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
      expect(harness.backend.correlationIds, hasLength(2));
      expect(harness.backend.correlationIds.toSet(), hasLength(1));
      expect(
        harness.backend.correlationIds.first,
        matches(RegExp(r'^[0-9a-f]{32}$')),
      );
      expect(harness.controller.state.retryAvailable, isFalse);
      harness.dispose();
    });

    test('maps a retained Task persistence failure to a controlled error',
        () async {
      final harness = _Harness(
        resolvePending: (_, __) async {
          throw const ConversationTaskPersistenceException();
        },
      );

      await harness.controller.submitText('oui');

      expect(
        harness.controller.state.messages.last.text,
        'La sauvegarde locale a échoué. Réessaie avant de quitter.',
      );
      expect(harness.controller.state.retryAvailable, isTrue);
      expect(harness.backend.calls, 0);
      harness.dispose();
    });

    test('maps a retained Shopping persistence failure to storage failure',
        () async {
      final harness = _Harness(
        resolvePending: (_, __) async {
          throw const ConversationShoppingPersistenceException(
            'shopping_local_persist_failed',
          );
        },
      );

      await harness.controller.submitText('oui');

      expect(
        harness.controller.state.messages.last.text,
        'La sauvegarde locale a échoué. Réessaie avant de quitter.',
      );
      expect(harness.controller.state.retryAvailable, isTrue);
      expect(harness.backend.calls, 0);
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

    test('does not repeat the same epistemic clarification indefinitely',
        () async {
      final clarification = ConversationClarification(
        clarificationId: 'clarification-1',
        reasonCode: 'event_date_required',
        questionText: 'Pour quel jour ?',
        expectedAnswerType: ConversationClarificationAnswerType.date,
        allowedChoices: const [],
        missingFieldCodes: const [
          ConversationMissingInformationCode.missingDate,
        ],
        createdAt: DateTime.utc(2026, 7, 23),
        attemptNumber: 1,
        sessionGeneration: 0,
      );
      final harness = _Harness(
        resolvePending: (_, __) async => ConversationOutcome(
          reply: 'Pour quel jour ?',
          responseKind: ConversationResponseKind.clarificationRequired,
          epistemicClarification: clarification,
        ),
      );

      await harness.controller.submitText('Planifie un rendez-vous');
      expect(
        harness.controller.state.phase,
        ConversationSessionPhase.awaitingClarification,
      );
      await harness.controller.submitText('Je ne sais pas');

      expect(harness.controller.state.phase, ConversationSessionPhase.ready);
      expect(
        harness.controller.state.messages.last.text,
        contains('informations restent insuffisantes'),
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

    test('proactive duration handoff arms pending before showing its question',
        () async {
      TaskModel? targetedTask;
      final task = TaskModel(
        id: 'task-stable',
        title: 'Préparer le dossier',
        category: 'To-do',
        isDone: false,
        createdAt: DateTime.utc(2026, 7, 23),
      );
      final harness = _Harness(
        startTaskDuration: ({
          required task,
          required question,
          required sessionGeneration,
          required logicalRequestId,
          required sourceSuggestionId,
        }) {
          targetedTask = task;
          expect(logicalRequestId, 'logical-duration');
          expect(sourceSuggestionId, 'suggestion-1');
          return SmartPlanningContinuationResult(
            status: SmartPlanningContinuationResultStatus
                .clarificationStillRequired,
            message: question,
            handled: true,
          );
        },
        applicationPendingPhase: () =>
            ConversationSessionPhase.awaitingClarification,
        resolvePending: (answer, generation) async {
          expect(answer, 'une heure');
          expect(targetedTask?.id, 'task-stable');
          return const ConversationOutcome(
            reply: 'Durée comprise : 60 minutes.',
          );
        },
      );
      final handoff = ProactiveTaskDurationHandoff(
        taskId: 'task-stable',
        logicalRequestId: 'logical-duration',
        sourceSuggestionId: 'suggestion-1',
        sourceEntityReference: 'priority:task:task-stable',
        taskTitle: task.title,
        question:
            'Combien de temps veux-tu prévoir pour “Préparer le dossier” ?',
        createdAt: DateTime.utc(2026, 7, 23),
        task: task,
      );

      harness.controller.beginProactiveTaskDuration(handoff: handoff);

      expect(targetedTask, same(task));
      expect(
        harness.controller.state.phase,
        ConversationSessionPhase.awaitingClarification,
      );
      expect(harness.controller.state.hasPendingAction, isTrue);
      expect(harness.controller.state.messages.last.text, handoff.question);
      expect(harness.controller.activeLogicalRequestId, 'logical-duration');

      await harness.controller.submitText('une heure');

      expect(harness.backend.calls, 0);
      expect(harness.controller.activeLogicalRequestId, 'logical-duration');
      expect(
        harness.controller.state.messages.last.text,
        'Durée comprise : 60 minutes.',
      );
      harness.dispose();
    });

    test('production composition shares the typed Smart Planning pending', () {
      final task = TaskModel(
        id: 'production-task',
        title: 'Préparer le dossier',
        category: 'To-do',
        isDone: false,
        createdAt: DateTime.utc(2026, 7, 23),
      );
      final controller = ConversationSessionController.production(
        profile: _profile(),
        backendClient: _Backend(),
        contextProvider: _Context(),
        messageStore: _Store(),
        accountScopeId: 'account',
        clock: () => DateTime.utc(2026, 7, 23),
        idGenerator: () => 'production-id',
      );
      final handoff = ProactiveTaskDurationHandoff(
        taskId: task.id!,
        logicalRequestId: 'production-logical',
        sourceSuggestionId: 'production-suggestion',
        sourceEntityReference: 'priority:task:production-task',
        taskTitle: task.title,
        question:
            'Combien de temps veux-tu prévoir pour “Préparer le dossier” ?',
        createdAt: DateTime.utc(2026, 7, 23),
        task: task,
      );

      controller.beginProactiveTaskDuration(handoff: handoff);

      final pending = controller.activeSmartPlanningContinuation;
      expect(pending, isNotNull);
      expect(pending!.task.id, 'production-task');
      expect(pending.step, SmartPlanningContinuationStep.duration);
      expect(pending.logicalRequestId, 'production-logical');
      expect(pending.sourceSuggestionId, 'production-suggestion');
      expect(controller.state.phase,
          ConversationSessionPhase.awaitingClarification);
      controller.dispose();
    });
  });
}

final class _Harness {
  _Harness({
    Future<ChatBackendResponse>? pending,
    Object? error,
    ConversationPendingResolver? resolvePending,
    ConversationTaskDurationStarter? startTaskDuration,
    ConversationApplicationPendingPhase? applicationPendingPhase,
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
      executeAction: (_, __, ___) async => const ConversationActionOutcome(),
      resolvePending: resolvePending,
      startTaskDuration: startTaskDuration,
      applicationPendingPhase: applicationPendingPhase,
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
  final List<String?> correlationIds = [];

  @override
  Future<ChatBackendResponse> send(ChatBackendRequest request) async {
    calls++;
    correlationIds.add(request.correlationId);
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
