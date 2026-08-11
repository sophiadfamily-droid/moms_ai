import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/chat_backend_request.dart';
import 'package:moms_ai/models/chat_backend_response.dart';
import 'package:moms_ai/models/conversation_models.dart';
import 'package:moms_ai/models/conversation_context_envelope.dart';
import 'package:moms_ai/models/conversation_epistemic_models.dart';
import 'package:moms_ai/models/conversation_session_models.dart';
import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/models/priority/proactive_priority_models.dart';
import 'package:moms_ai/models/smart_planning_continuation.dart';
import 'package:moms_ai/models/task_model.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/services/chat_backend_client.dart';
import 'package:moms_ai/services/conversation_context_service.dart';
import 'package:moms_ai/services/conversation_coordinator.dart';
import 'package:moms_ai/services/conversation_session_controller.dart';
import 'package:moms_ai/services/event_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

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
        'Je n’ai pas réussi à enregistrer ça. Réessaie avant de quitter.',
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
        'Je n’ai pas réussi à enregistrer ça. Réessaie avant de quitter.',
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

    test('production composition consumes callable Event draft before backend',
        () async {
      expect(
        ChatBackendResponse.fromJson(_eventDraftCallableJson())
            .epistemic
            ?.clarification
            ?.draft,
        isNotNull,
      );
      final backend = _JsonCallableBackend(_eventDraftCallableJson());
      final controller = ConversationSessionController.production(
        profile: _profile(),
        backendClient: backend,
        contextProvider: _Context(),
        messageStore: _Store(),
        accountScopeId: 'account',
        eventConflictChecker: EventService.getOverlapConflict,
        clock: () => DateTime.utc(2026, 7, 29, 12),
        idGenerator: () => 'production-event-diagnosis',
      );

      await controller.submitText('medecin demain 15h');

      expect(controller.state.hasPendingAction, isTrue);
      expect(
        controller.state.phase,
        ConversationSessionPhase.awaitingClarification,
      );

      await controller.submitText('1h');

      expect(backend.invocations, 1);
      expect(
        controller.state.messages.last.text,
        contains('trajet aller'),
      );
      controller.dispose();
    });

    test('an occupied start replaces the backend duration question', () async {
      final backend = _JsonCallableBackend(_eventDraftCallableJson());
      final checkedStarts = <String>[];
      final controller = ConversationSessionController.production(
        profile: _profile(),
        backendClient: backend,
        contextProvider: _Context(),
        messageStore: _Store(),
        accountScopeId: 'account',
        eventStartConflictChecker: ({required startDateTimeIso}) async {
          checkedStarts.add(startDateTimeIso);
          if (startDateTimeIso.contains('T15:00')) {
            return EventModel(
              title: 'ton Pilates',
              date: '2026-07-30',
              time: '14:00',
              notes: '',
              createdAt: DateTime.utc(2026, 7, 29),
              startDateTimeIso: '2026-07-30T14:00:00.000Z',
              endDateTimeIso: '2026-07-30T16:00:00.000Z',
              durationMinutes: 120,
            );
          }
          return null;
        },
        eventConflictChecker: ({required candidate}) async => null,
        eventStartAlternativeSuggester: ({
          required startDateTimeIso,
          required conflict,
        }) async =>
            DateTime.utc(2026, 7, 30, 16),
        clock: () => DateTime.utc(2026, 7, 29, 12),
        idGenerator: () => 'production-event-occupied-start',
      );

      await controller.submitText('medecin demain 15h');

      expect(controller.state.messages.last.text, contains('ton Pilates'));
      expect(controller.state.messages.last.text, contains('16 h'));
      expect(controller.state.messages.last.text, contains('ça te va'));
      expect(controller.state.messages.last.text, isNot(contains('durée')));
      expect(controller.state.phase,
          ConversationSessionPhase.awaitingClarification);

      await controller.submitText('oui');

      expect(controller.state.messages.last.text, contains('Combien de temps'));
      expect(checkedStarts, hasLength(2));
      expect(backend.invocations, 1);
      controller.dispose();
    });

    test('callable Event draft follows every local field to confirmation',
        () async {
      SharedPreferences.setMockInitialValues({});
      final backend = _JsonCallableBackend(_eventDraftCallableJson());
      final controller = ConversationSessionController.production(
        profile: _profile(),
        backendClient: backend,
        contextProvider: _Context(),
        messageStore: _Store(),
        accountScopeId: 'account',
        eventConflictChecker: EventService.getOverlapConflict,
        clock: () => DateTime.utc(2026, 7, 29, 12),
        idGenerator: () => 'production-event-full-path',
      );

      await controller.submitText('medecin demain 15h');
      await controller.submitText('1h');
      expect(controller.state.messages.last.text, contains('trajet aller'));
      await controller.submitText('vingt minutes');
      expect(controller.state.messages.last.text, contains('trajet retour'));
      await controller.submitText('aucun trajet');
      expect(controller.state.messages.last.text, contains('marge'));
      await controller.submitText('aucune');

      expect(backend.invocations, 1);
      expect(controller.state.phase,
          ConversationSessionPhase.awaitingConfirmation);
      expect(
        controller.state.messages.last.text,
        contains('Veux-tu que je l’ajoute'),
      );
      await controller.submitText('ouais vas-y');

      final preferences = await SharedPreferences.getInstance();
      final eventKey = EventService.localEventsKeyForAccountScope(null);
      expect(preferences.getStringList(eventKey), hasLength(1));

      await controller.submitText('ouais vas-y');
      expect(preferences.getStringList(eventKey), hasLength(1));
      controller.dispose();
    });

    test(
        'production composition clarifies a generic Event title and creates once',
        () async {
      SharedPreferences.setMockInitialValues({});
      final json = jsonDecode(jsonEncode(_eventDraftCallableJson()))
          as Map<String, dynamic>;
      final epistemic = json['epistemic'] as Map<String, dynamic>;
      final clarification = epistemic['clarification'] as Map<String, dynamic>;
      final draft = clarification['draft'] as Map<String, dynamic>;
      draft['title'] = 'Rendez-vous';
      draft['startTime'] = null;
      final backend = _JsonCallableBackend(json);
      final controller = ConversationSessionController.production(
        profile: _profile(),
        backendClient: backend,
        contextProvider: _Context(),
        messageStore: _Store(),
        accountScopeId: 'account',
        eventConflictChecker: EventService.getOverlapConflict,
        clock: () => DateTime.utc(2026, 7, 29, 12),
        idGenerator: () => 'production-generic-event',
      );

      await controller.submitText('rdv demain 14heur');
      expect(controller.state.messages.last.text, contains('motif'));
      await controller.submitText('dentiste');
      expect(controller.state.messages.last.text, contains('Combien de temps'));
      expect(backend.invocations, 1);
      await controller.submitText('1h');
      await controller.submitText('10');
      await controller.submitText('5');
      await controller.submitText('5');

      expect(controller.state.phase,
          ConversationSessionPhase.awaitingConfirmation);
      expect(controller.state.messages.last.text,
          contains('Rendez-vous dentiste'));
      await controller.submitText('ouais vas-y');
      await controller.submitText('ouais vas-y');

      final preferences = await SharedPreferences.getInstance();
      final stored = preferences
          .getStringList(EventService.localEventsKeyForAccountScope(null))!
          .map((value) => EventModel.fromJson(jsonDecode(value)))
          .toList(growable: false);
      expect(stored, hasLength(1));
      expect(stored.single.title, 'Rendez-vous dentiste');
      expect(stored.single.time, '14:00');
      expect(stored.single.durationMinutes, 60);
      expect(stored.single.travelGoMinutes, 10);
      expect(stored.single.travelBackMinutes, 5);
      expect(stored.single.marginMinutes, 5);
      controller.dispose();
    });

    test('production composition keeps callable Event draft through a conflict',
        () async {
      addTearDown(() => SharedPreferences.setMockInitialValues({}));
      final existing = EventModel(
        id: 'existing-event',
        title: 'Rendez-vous existant',
        date: '2026-07-30',
        time: '15:00',
        notes: '',
        createdAt: DateTime.utc(2026, 7, 28),
        startDateTimeIso: '2026-07-30T15:00:00.000',
        endTime: '16:00',
        endDateTimeIso: '2026-07-30T16:00:00.000',
        durationMinutes: 60,
      );
      SharedPreferences.setMockInitialValues({
        EventService.localEventsKeyForAccountScope(null): [
          jsonEncode(existing.toJson()),
        ],
      });
      final backend = _JsonCallableBackend(_eventDraftCallableJson());
      final controller = ConversationSessionController.production(
        profile: _profile(),
        backendClient: backend,
        contextProvider: _Context(),
        messageStore: _Store(),
        accountScopeId: 'account',
        eventConflictChecker: EventService.getOverlapConflict,
        clock: () => DateTime.utc(2026, 7, 29, 12),
        idGenerator: () => 'production-event-conflict',
      );

      await controller.submitText('medecin demain 15h');

      expect(controller.state.messages.last.text, contains('16 h'));
      expect(controller.state.messages.last.text, contains('ça te va'));
      expect(controller.state.messages.last.text, isNot(contains('durée')));
      expect(controller.state.hasPendingAction, isTrue);
      expect(controller.state.phase,
          ConversationSessionPhase.awaitingClarification);

      await controller.submitText('oui');

      expect(controller.state.messages.last.text, contains('Combien de temps'));

      await controller.submitText('1h');

      expect(backend.invocations, 1);
      expect(controller.state.messages.last.text, contains('trajet aller'));
      expect(controller.state.hasPendingAction, isTrue);
      await controller.submitText('vingt minutes');
      await controller.submitText('aucun trajet');
      await controller.submitText('aucune');
      expect(controller.state.messages.last.text, contains('16 h 20'));
      expect(controller.state.messages.last.text, contains('ça te va'));
      expect(controller.state.phase,
          ConversationSessionPhase.awaitingClarification);

      await controller.submitText('oui');
      expect(controller.state.phase,
          ConversationSessionPhase.awaitingConfirmation);

      await controller.submitText('ouais vas-y');

      final preferences = await SharedPreferences.getInstance();
      final stored = preferences
          .getStringList(EventService.localEventsKeyForAccountScope(null))!
          .map((value) => EventModel.fromJson(jsonDecode(value)))
          .toList(growable: false);
      expect(stored, hasLength(2));
      final created =
          stored.singleWhere((event) => event.id != 'existing-event');
      expect(created.time, '16:20');
      expect(created.durationMinutes, 60);
      expect(created.travelGoMinutes, 20);
      expect(created.travelBackMinutes, 0);
      expect(created.marginMinutes, 0);
      expect(backend.invocations, 1);
      controller.dispose();
    });

    test('production conflict time leaves an unknown duration missing',
        () async {
      final json = jsonDecode(jsonEncode(_eventDraftCallableJson()))
          as Map<String, dynamic>;
      final epistemic = json['epistemic'] as Map<String, dynamic>;
      final clarification = epistemic['clarification'] as Map<String, dynamic>;
      final draft = clarification['draft'] as Map<String, dynamic>;
      clarification['expectedAnswerType'] = 'time';
      draft['startTime'] = null;
      draft['expectedField'] = 'conflictAlternativeTime';
      final backend = _JsonCallableBackend(json);
      final controller = ConversationSessionController.production(
        profile: _profile(),
        backendClient: backend,
        contextProvider: _Context(),
        messageStore: _Store(),
        accountScopeId: 'account',
        eventStartConflictChecker: ({required startDateTimeIso}) async => null,
        clock: () => DateTime.utc(2026, 7, 29, 12),
        idGenerator: () => 'production-conflict-missing-duration',
      );

      await controller.submitText('medecin demain 15h');
      await controller.submitText('23h');

      expect(backend.invocations, 1);
      expect(controller.state.messages.last.text, contains('Combien de temps'));
      expect(controller.state.phase,
          ConversationSessionPhase.awaitingClarification);
      controller.dispose();
    });

    test('callable Event draft expires and is invalidated on account change',
        () async {
      var now = DateTime.utc(2026, 7, 29, 12);
      final expiringBackend = _JsonCallableBackend(_eventDraftCallableJson());
      final expiring = ConversationSessionController.production(
        profile: _profile(),
        backendClient: expiringBackend,
        contextProvider: _Context(),
        messageStore: _Store(),
        accountScopeId: 'account-a',
        eventStartConflictChecker: ({required startDateTimeIso}) async => null,
        clock: () => now,
        idGenerator: () => 'production-event-expiry',
      );
      await expiring.submitText('medecin demain 15h');
      now = DateTime.utc(2026, 7, 29, 12, 16);
      await expiring.submitText('1h');
      expect(expiring.state.messages.last.text, contains('expiré'));
      expect(expiringBackend.invocations, 1);
      expiring.dispose();

      final accountBackend = _JsonCallableBackend(_eventDraftCallableJson());
      final account = ConversationSessionController.production(
        profile: _profile(),
        backendClient: accountBackend,
        contextProvider: _Context(),
        messageStore: _Store(),
        accountScopeId: 'account-a',
        eventStartConflictChecker: ({required startDateTimeIso}) async => null,
        clock: () => DateTime.utc(2026, 7, 29, 12),
        idGenerator: () => 'production-event-account',
      );
      await account.submitText('medecin demain 15h');
      account.changeAccount(_profile(firstName: 'Compte B'));
      await account.submitText('1h');

      expect(accountBackend.invocations, 2);
      expect(account.state.hasPendingAction, isFalse);
      account.dispose();
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

final class _JsonCallableBackend implements ChatBackendClient {
  _JsonCallableBackend(this.json);

  final Map<String, dynamic> json;
  int invocations = 0;

  @override
  Future<ChatBackendResponse> send(ChatBackendRequest request) async {
    invocations++;
    return ChatBackendResponse.fromJson(json);
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
      context: ConversationContextEnvelope(
        projectionVersion: 0,
        purpose: ConversationTransportContract.purposeId,
        generatedAt: DateTime.utc(2026, 7, 29, 12),
        state: ConversationContextState.complete,
        sections: const [],
        budgetRequested: 245,
        budgetUsed: 0,
        omittedCount: 0,
        truncatedSections: const [],
        warningCodes: const [],
      ),
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

Map<String, dynamic> _eventDraftCallableJson() => {
      'reply': 'Je prépare ce rendez-vous. Il me manque juste la durée.',
      'actions': <dynamic>[],
      'memories': <dynamic>[],
      'epistemic': {
        'schemaVersion': 1,
        'responseKind': 'clarificationRequired',
        'epistemicState': 'insufficientInformation',
        'confidenceLevel': 'high',
        'usedSourceTypes': ['currentUserMessage'],
        'groundingReferences': [
          {
            'schemaVersion': 1,
            'sourceType': 'currentUserMessage',
            'section': null,
            'factKey': null,
            'freshness': 'current',
            'confirmation': 'confirmed',
            'projectionVersion': 0,
          }
        ],
        'personalClaims': <dynamic>[],
        'missingInformation': [
          {
            'schemaVersion': 1,
            'code': 'missingDuration',
            'domain': 'event',
            'field': 'duration',
            'isRequired': true,
            'canClarify': true,
          }
        ],
        'contradictions': <dynamic>[],
        'clarification': {
          'schemaVersion': 1,
          'clarificationId': 'event-clarification',
          'reasonCode': 'event_duration_required',
          'questionText':
              'Je prépare ce rendez-vous. Il me manque juste la durée.',
          'expectedAnswerType': 'duration',
          'allowedChoices': <dynamic>[],
          'missingFieldCodes': ['missingDuration'],
          'createdAt': '2026-07-29T12:00:00.000Z',
          'expiresAt': '2026-07-29T12:15:00.000Z',
          'attemptNumber': 1,
          'maximumAttempts': 3,
          'sessionGeneration': 0,
          'draft': {
            'schemaVersion': 1,
            'draftType': 'eventCreation',
            'logicalRequestId': 'logical-event-draft',
            'draftId': 'event-draft',
            'title': 'Consultation médecin',
            'date': '2026-07-30',
            'startTime': '15:00',
            'durationMinutes': null,
            'travelGoMinutes': null,
            'travelBackMinutes': null,
            'marginMinutes': null,
            'expectedField': 'duration',
            'createdAt': '2026-07-29T12:00:00.000Z',
            'expiresAt': '2026-07-29T12:15:00.000Z',
            'sessionGeneration': 0,
          },
        },
        'uncertaintyCodes': ['missingRequiredInformation'],
        'contextStateObserved': 'complete',
        'warningCodes': <dynamic>[],
        'responseId': 'event-clarification-response',
      },
    };

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
