import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/chat_backend_request.dart';
import 'package:moms_ai/models/action_autonomy_policy.dart';
import 'package:moms_ai/models/chat_backend_response.dart';
import 'package:moms_ai/models/conversation_context_envelope.dart';
import 'package:moms_ai/models/conversation_epistemic_models.dart';
import 'package:moms_ai/models/conversation_models.dart';
import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/models/shopping_item_model.dart';
import 'package:moms_ai/models/smart_planning_continuation.dart';
import 'package:moms_ai/models/task_model.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/services/action_handler_service.dart';
import 'package:moms_ai/services/callable_chat_backend_client.dart';
import 'package:moms_ai/services/chat_backend_client.dart';
import 'package:moms_ai/services/conversation_context_service.dart';
import 'package:moms_ai/services/conversation_coordinator.dart';
import 'package:moms_ai/services/conversation_legacy_action_executor.dart';
import 'package:moms_ai/services/event_service.dart';
import 'package:moms_ai/services/shopping_service.dart';
import 'package:moms_ai/services/planner_engine_service.dart';
import 'package:moms_ai/services/planning_proposal_engine.dart';
import 'package:moms_ai/services/selected_slot_revalidation_service.dart';
import 'package:moms_ai/services/smart_planning_continuation_coordinator.dart';
import 'package:moms_ai/services/smart_planning_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('ConversationCoordinator', () {
    test(
        'decodes the deterministic Task callable JSON and creates clarification',
        () async {
      final backend = CallableChatBackendClient.withInvoker(
        (_) async => _deterministicTaskClarificationJson(),
      );
      final coordinator = ConversationCoordinator(
        backend: backend,
        contextProvider: _FakeContextProvider(_completeTaskRequest()),
        clock: () => DateTime.utc(2026, 7, 27, 10),
      );
      var executions = 0;

      final outcome = await coordinator.send(
        input: ConversationInput(
          message: 'Crée une tâche prioritaire pour demain.',
          profile: _profile(),
          logicalRequestId: 'logical-task-request-1',
        ),
        executeAction: (_) async {
          executions++;
          return const ConversationActionOutcome();
        },
      );

      expect(outcome?.reply, 'Quelle tâche veux-tu créer ?');
      expect(executions, 0);
      final pending = coordinator.state.pendingAction?.taskClarification;
      expect(pending, isNotNull);
      expect(pending?.dueDate, '2026-07-28');
      expect(pending?.priority, 'Haute');
      expect(pending?.isImportant, isTrue);
      expect(pending?.logicalRequestId, 'logical-task-request-1');
      expect(pending?.originalInstruction,
          'Crée une tâche prioritaire pour demain.');
    });

    test('keeps rejecting a Task clarification with an invalid contract',
        () async {
      final invalid = _deterministicTaskClarificationJson();
      final clarification = (invalid['epistemic']
          as Map<String, dynamic>)['clarification'] as Map<String, dynamic>;
      clarification.remove('maximumAttempts');
      final coordinator = ConversationCoordinator(
        backend: CallableChatBackendClient.withInvoker((_) async => invalid),
        contextProvider: _FakeContextProvider(_completeTaskRequest()),
        clock: () => DateTime.utc(2026, 7, 27, 10),
      );

      await expectLater(
        coordinator.send(
          input: ConversationInput(
            message: 'Crée une tâche prioritaire pour demain.',
            profile: _profile(),
          ),
          executeAction: (_) async => const ConversationActionOutcome(),
        ),
        throwsA(isA<ChatBackendMalformedResponseException>()),
      );
      expect(coordinator.state.pendingAction, isNull);
    });

    test('sends a normal message with the session-scoped backend request',
        () async {
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
      expect(outcome?.request?.message, request.message);
      expect(outcome?.request?.sessionGeneration, 0);
      expect(backend.requests.single, same(outcome?.request));
      expect(outcome?.request?.toJson().keys, {
        'schemaVersion',
        'message',
        'sessionGeneration',
        'conversationContext',
        'conversationHistory',
        'profile',
        'profileContext',
        'memories',
        'memoryReasoning',
        'events',
        'autonomyPolicyVersion',
        'autonomyMode',
        'allowedStructuredResponseKinds',
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

    test('suggestions blocks immediate mutation and paused blocks proposals',
        () async {
      var mode = ActionAutonomyMode.suggestions;
      var loads = 0;
      final coordinator = ConversationCoordinator(
        backend: _FakeBackend(
          response: const ChatBackendResponse(
            reply: 'Réponse initiale',
            actions: [
              {'type': 'task', 'title': 'Préparer le dossier'},
            ],
            memories: [],
          ),
        ),
        contextProvider: _FakeContextProvider(_request()),
        loadAutonomyPolicy: () async {
          loads++;
          return ActionAutonomyPolicy(
            mode: mode,
            changedAt: DateTime.utc(2026, 7, 23),
            changeSource: ActionAutonomyChangeSource.explicitUserSetting,
            accountScopeId: 'scope-a',
          );
        },
      );
      var executions = 0;
      final suggestions = await coordinator.send(
        input: ConversationInput(message: 'Ajoute', profile: _profile()),
        executeAction: (_) async {
          executions++;
          return const ConversationActionOutcome();
        },
      );
      expect(executions, 0);
      expect(suggestions?.reply, contains('confirmer'));
      expect(loads, greaterThanOrEqualTo(2));

      mode = ActionAutonomyMode.paused;
      final paused = await coordinator.send(
        input: ConversationInput(message: 'Ajoute', profile: _profile()),
        executeAction: (_) async {
          executions++;
          return const ConversationActionOutcome();
        },
      );
      expect(executions, 0);
      expect(paused?.reply, contains('pause'));
    });

    test('current mode is reloaded before dispatching a late response',
        () async {
      var mode = ActionAutonomyMode.normal;
      var loads = 0;
      final coordinator = ConversationCoordinator(
        backend: _FakeBackend(
          response: const ChatBackendResponse(
            reply: 'Réponse initiale',
            actions: [
              {'type': 'shopping', 'title': 'Lait'},
            ],
            memories: [],
          ),
        ),
        contextProvider: _FakeContextProvider(_request()),
        loadAutonomyPolicy: () async {
          loads++;
          if (loads > 1) mode = ActionAutonomyMode.paused;
          return ActionAutonomyPolicy(
            mode: mode,
            changedAt: DateTime.utc(2026, 7, 23),
            changeSource: ActionAutonomyChangeSource.explicitUserSetting,
            accountScopeId: 'scope-a',
          );
        },
      );
      var executions = 0;
      await coordinator.send(
        input: ConversationInput(message: 'Ajoute', profile: _profile()),
        executeAction: (_) async {
          executions++;
          return const ConversationActionOutcome();
        },
      );
      expect(executions, 0);
      expect(mode, ActionAutonomyMode.paused);
    });

    test('suggestions keeps a typed Task pending and executes it once',
        () async {
      var mode = ActionAutonomyMode.suggestions;
      final coordinator = ConversationCoordinator(
        backend: _FakeBackend(
          response: ChatBackendResponse(
            reply: 'Je prépare la tâche.',
            actions: const [
              {'type': 'task', 'title': 'Préparer le dossier'},
            ],
            memories: const [],
            epistemic: _epistemic(
              kind: ConversationResponseKind.actionProposal,
            ),
          ),
        ),
        contextProvider: _FakeContextProvider(_request()),
        loadAutonomyPolicy: () async => ActionAutonomyPolicy(
          mode: mode,
          changedAt: DateTime.utc(2026, 7, 23),
          changeSource: ActionAutonomyChangeSource.explicitUserSetting,
          accountScopeId: 'scope-a',
        ),
      );
      var executions = 0;
      await coordinator.send(
        input: ConversationInput(
          message: 'Ajoute la tâche',
          profile: _profile(),
          sessionGeneration: 4,
        ),
        executeAction: (_) async {
          executions++;
          return const ConversationActionOutcome();
        },
      );
      final pending = coordinator.state.pendingAction?.autonomyPending;
      expect(pending?.payload, isA<PendingTaskPayload>());
      expect(pending?.policyModeAtCreation, ActionAutonomyMode.suggestions);
      expect(pending?.riskLevel, ActionRiskLevel.reversibleLowRisk);
      expect(pending?.sessionGeneration, 4);
      expect(executions, 0);

      final resolved = await coordinator.resolvePendingAutonomyConfirmation(
        answer: 'oui',
        sessionGeneration: 4,
        executeAction: (_) async {
          executions++;
          return const ConversationActionOutcome(message: 'Tâche créée.');
        },
      );
      expect(resolved?.message, 'Tâche créée.');
      expect(executions, 1);
      expect(coordinator.state.pendingAction, isNull);
      expect(
        await coordinator.resolvePendingAutonomyConfirmation(
          answer: 'oui',
          sessionGeneration: 4,
          executeAction: (_) async {
            executions++;
            return const ConversationActionOutcome();
          },
        ),
        isNull,
      );
      expect(executions, 1);
      mode = ActionAutonomyMode.paused;
    });

    test('clarifies an incomplete task and preserves known fields', () async {
      final policy = ActionAutonomyPolicy(
        mode: ActionAutonomyMode.suggestions,
        changedAt: DateTime.utc(2026, 7, 27),
        changeSource: ActionAutonomyChangeSource.explicitUserSetting,
        accountScopeId: 'scope-a',
      );
      final coordinator = ConversationCoordinator(
        backend: _FakeBackend(
          response: ChatBackendResponse(
            reply: 'Quelle tâche veux-tu créer ?',
            actions: const [],
            memories: const [],
            epistemic: _taskTitleClarification(sessionGeneration: 5),
          ),
        ),
        contextProvider: _FakeContextProvider(_request()),
        loadAutonomyPolicy: () async => policy,
        clock: () => DateTime.utc(2026, 7, 27, 10),
      );
      var executions = 0;
      final initial = await coordinator.send(
        input: ConversationInput(
          message: 'Crée une tâche prioritaire pour demain.',
          profile: _profile(),
          sessionGeneration: 5,
          logicalRequestId: 'logical-task-5',
        ),
        executeAction: (_) async {
          executions++;
          return const ConversationActionOutcome();
        },
      );

      expect(initial?.reply, 'Quelle tâche veux-tu créer ?');
      expect(executions, 0);
      expect(
        coordinator.state.pendingAction?.type,
        PendingConversationActionType.taskClarification,
      );

      final ambiguous = await coordinator.resolvePendingTaskClarification(
        answer: 'oui',
        sessionGeneration: 5,
      );
      expect(ambiguous?.message, 'Quelle tâche veux-tu créer ?');
      expect(executions, 0);

      final completed = await coordinator.resolvePendingTaskClarification(
        answer: 'Envoyer le dossier à la mutuelle.',
        sessionGeneration: 5,
      );
      expect(completed?.message, contains('Envoyer le dossier'));
      expect(completed?.message, contains('2026-07-28'));
      expect(completed?.message, contains('Haute'));
      final payload = coordinator.state.pendingAction?.autonomyPending?.payload
          as PendingTaskPayload;
      expect(payload.title, 'Envoyer le dossier à la mutuelle.');
      expect(payload.dueDate, '2026-07-28');
      expect(payload.priority, 'Haute');
      expect(payload.isImportant, isTrue);
      expect(executions, 0);

      final confirmed = await coordinator.resolvePendingAutonomyConfirmation(
        answer: 'oui',
        sessionGeneration: 5,
        executeAction: (action) async {
          executions++;
          expect(action['dueDate'], '2026-07-28');
          expect(action['priority'], 'Haute');
          expect(action['isImportant'], isTrue);
          expect(action['actionId'], isNotEmpty);
          expect(action['logicalRequestId'], 'logical-task-5');
          expect(action['mutationId'], 'logical-task-5');
          return const ConversationActionOutcome(message: 'Tâche créée.');
        },
      );
      expect(confirmed?.message, 'Tâche créée.');
      expect(executions, 1);
      expect(
        await coordinator.resolvePendingAutonomyConfirmation(
          answer: 'oui',
          sessionGeneration: 5,
          executeAction: (_) async {
            executions++;
            return const ConversationActionOutcome();
          },
        ),
        isNull,
      );
      expect(executions, 1);
    });

    test('keeps a failed Task confirmation retryable and idempotent', () async {
      final policy = ActionAutonomyPolicy(
        mode: ActionAutonomyMode.suggestions,
        changedAt: DateTime.utc(2026, 7, 27),
        changeSource: ActionAutonomyChangeSource.explicitUserSetting,
        accountScopeId: 'scope-a',
      );
      final coordinator = ConversationCoordinator(
        backend: _FakeBackend(
          response: ChatBackendResponse(
            reply: 'Quelle tâche veux-tu créer ?',
            actions: const [],
            memories: const [],
            epistemic: _taskTitleClarification(),
          ),
        ),
        contextProvider: _FakeContextProvider(_request()),
        loadAutonomyPolicy: () async => policy,
        clock: () => DateTime.utc(2026, 7, 27, 10),
      );
      await coordinator.send(
        input: ConversationInput(
          message: 'Crée une tâche prioritaire pour demain.',
          profile: _profile(),
          logicalRequestId: 'logical-retry',
        ),
        executeAction: (_) async => const ConversationActionOutcome(),
      );
      await coordinator.resolvePendingTaskClarification(
        answer: 'Envoyer le dossier à la mutuelle.',
        sessionGeneration: 0,
      );
      Map<String, dynamic>? firstAction;
      await expectLater(
        coordinator.resolvePendingAutonomyConfirmation(
          answer: 'oui',
          sessionGeneration: 0,
          executeAction: (action) async {
            firstAction = Map<String, dynamic>.from(action);
            throw const FormatException('synthetic_task_repository_failure');
          },
        ),
        throwsA(
          isA<ConversationTaskPersistenceException>(),
        ),
      );
      expect(
        coordinator.state.pendingAction?.autonomyPending?.state,
        ActionPendingState.pendingSync,
      );

      var writes = 0;
      final retried = await coordinator.resolvePendingAutonomyConfirmation(
        answer: 'OUI.',
        sessionGeneration: 0,
        executeAction: (action) async {
          writes++;
          expect(action, firstAction);
          return const ConversationActionOutcome(message: 'Tâche créée.');
        },
      );
      expect(retried?.message, 'Tâche créée.');
      expect(writes, 1);
      expect(coordinator.state.pendingAction, isNull);
      expect(
        await coordinator.resolvePendingAutonomyConfirmation(
          answer: 'oui',
          sessionGeneration: 0,
          executeAction: (_) async {
            writes++;
            return const ConversationActionOutcome();
          },
        ),
        isNull,
      );
      expect(writes, 1);
    });

    test('refusing task clarification creates nothing', () async {
      final coordinator = ConversationCoordinator(
        backend: _FakeBackend(
          response: ChatBackendResponse(
            reply: 'Quelle tâche veux-tu créer ?',
            actions: const [],
            memories: const [],
            epistemic: _taskTitleClarification(),
          ),
        ),
        contextProvider: _FakeContextProvider(_request()),
        clock: () => DateTime.utc(2026, 7, 27, 10),
      );
      await coordinator.send(
        input: ConversationInput(
          message: 'Crée une tâche prioritaire pour demain.',
          profile: _profile(),
        ),
        executeAction: (_) async => const ConversationActionOutcome(),
      );
      final result = await coordinator.resolvePendingTaskClarification(
        answer: 'non',
        sessionGeneration: 0,
      );
      expect(result?.message, contains('aucune tâche'));
      expect(coordinator.state.pendingAction, isNull);
    });

    test('Shopping pending is preserved and blocked when mode becomes paused',
        () async {
      var mode = ActionAutonomyMode.suggestions;
      final coordinator = ConversationCoordinator(
        backend: _FakeBackend(
          response: ChatBackendResponse(
            reply: 'Je prépare la liste.',
            actions: const [
              {'type': 'shopping', 'title': 'Lait'},
            ],
            memories: const [],
            epistemic: _epistemic(
              kind: ConversationResponseKind.actionProposal,
            ),
          ),
        ),
        contextProvider: _FakeContextProvider(_request()),
        loadAutonomyPolicy: () async => ActionAutonomyPolicy(
          mode: mode,
          changedAt: DateTime.utc(2026, 7, 23),
          changeSource: ActionAutonomyChangeSource.explicitUserSetting,
          accountScopeId: 'scope-a',
        ),
      );
      var executions = 0;
      await coordinator.send(
        input: ConversationInput(
          message: 'Ajoute du lait',
          profile: _profile(),
          sessionGeneration: 2,
        ),
        executeAction: (_) async {
          executions++;
          return const ConversationActionOutcome();
        },
      );
      expect(
        coordinator.state.pendingAction?.autonomyPending?.payload,
        isA<PendingShoppingPayload>(),
      );
      mode = ActionAutonomyMode.paused;
      final blocked = await coordinator.resolvePendingAutonomyConfirmation(
        answer: 'oui',
        sessionGeneration: 2,
        executeAction: (_) async {
          executions++;
          return const ConversationActionOutcome();
        },
      );
      expect(blocked?.message, contains('pause'));
      expect(executions, 0);
      expect(
        coordinator.state.pendingAction?.autonomyPending?.state,
        ActionPendingState.blockedByPolicy,
      );
      mode = ActionAutonomyMode.normal;
      expect(executions, 0);
      final completed = await coordinator.resolvePendingAutonomyConfirmation(
        answer: 'oui',
        sessionGeneration: 2,
        executeAction: (_) async {
          executions++;
          return const ConversationActionOutcome(message: 'Article ajouté.');
        },
      );
      expect(completed?.message, contains('Confirme à nouveau'));
      expect(executions, 0);
      final reconfirmed = await coordinator.resolvePendingAutonomyConfirmation(
        answer: 'oui',
        sessionGeneration: 2,
        executeAction: (_) async {
          executions++;
          return const ConversationActionOutcome(message: 'Article ajouté.');
        },
      );
      expect(reconfirmed?.message, 'Article ajouté.');
      expect(executions, 1);
    });

    test('rejects an incomplete grounded action before business execution',
        () async {
      final backend = _FakeBackend(
        response: ChatBackendResponse(
          reply: 'Je prépare le rendez-vous.',
          actions: const [
            {'type': 'event', 'title': 'Médecin'},
          ],
          memories: const [],
          epistemic: _epistemic(
            kind: ConversationResponseKind.actionProposal,
          ),
        ),
      );
      final coordinator = ConversationCoordinator(
        backend: backend,
        contextProvider: _FakeContextProvider(_request()),
      );
      var executions = 0;

      await expectLater(
        coordinator.send(
          input: ConversationInput(
            message: 'Ajoute le rendez-vous',
            profile: _profile(),
          ),
          executeAction: (_) async {
            executions++;
            return const ConversationActionOutcome();
          },
        ),
        throwsA(isA<ChatBackendMalformedResponseException>()),
      );
      expect(executions, 0);
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

    test('active Event duration consumes 1h before general routing', () async {
      final coordinator = _coordinator();
      final executor = ConversationLegacyActionExecutor(
        coordinator: coordinator,
        clock: () => DateTime.utc(2026, 7, 29, 10),
      );

      final initial = await executor.execute(
        const {
          'type': 'event',
          'title': 'Médecin',
          'date': '2026-07-30',
          'time': '15:00',
          'durationMinutes': 0,
        },
        'médecin demain 15h',
        0,
      );
      expect(initial.message, contains('Combien de temps'));
      expect(executor.hasPendingEventDraft, isTrue);

      final duration = await executor.resolvePending('1h', 0);

      expect(duration?.reply, contains('trajet aller'));
      expect(duration?.reply, isNot(contains('pour quel rendez-vous')));
      expect(executor.hasPendingEventDraft, isTrue);
    });

    test('slot search period is routed before classic Event creation',
        () async {
      final now = DateTime(2026, 8, 13, 14, 48);
      final smartPlanning = SmartPlanningContinuationCoordinator(
        gateway: _SlotSearchGateway(),
        clock: () => now,
        idGenerator: () => 'slot-search-period',
      );
      final executor = ConversationLegacyActionExecutor(
        coordinator: _coordinator(),
        smartPlanning: smartPlanning,
        clock: () => now,
      );

      final outcome = await executor.resolveLocalRequest(
        'Propose-moi un créneau pour le dentiste la semaine prochaine',
        0,
      );

      expect(outcome?.reply, contains('durée'));
      expect(outcome?.reply, isNot(contains('Quel jour')));
      expect(executor.hasPendingEventDraft, isFalse);
      expect(
        smartPlanning.active?.type,
        SmartPlanningContinuationType.explicitSlotRequest,
      );
      expect(smartPlanning.active?.task.title, 'Dentiste');
      expect(smartPlanning.active?.startDate, DateTime(2026, 8, 17));
    });

    test('generic Event title is completed on the same local draft', () async {
      final coordinator = _coordinator();
      final executor = ConversationLegacyActionExecutor(
        coordinator: coordinator,
        clock: () => DateTime.utc(2026, 7, 29, 10),
      );
      final draft = ConversationClarificationDraft(
        schemaVersion: 1,
        draftType: ConversationClarificationDraftType.eventCreation,
        logicalRequestId: 'logical-generic-event',
        draftId: 'generic-event-draft',
        title: 'Rendez-vous',
        date: '2026-07-30',
        startTime: '15:00',
        durationMinutes: null,
        travelGoMinutes: null,
        travelBackMinutes: null,
        marginMinutes: null,
        expectedField: ConversationEventDraftExpectedField.duration,
        createdAt: DateTime.utc(2026, 7, 29, 10),
        expiresAt: DateTime.utc(2026, 7, 29, 10, 15),
        sessionGeneration: 0,
      );
      expect(executor.registerClarificationDraft(draft, 0), isTrue);
      expect(executor.pendingEventExpectedFieldCode, 'eventTitle');

      final independent =
          await executor.resolvePending('ajoute du lait aux courses', 0);
      expect(independent, isNull);
      expect(executor.pendingEventDraftId, 'generic-event-draft');

      final ambiguous = await executor.resolvePending('un truc', 0);
      expect(ambiguous?.reply, contains('préciser le motif'));
      expect(executor.pendingEventDraftId, 'generic-event-draft');

      final motif = await executor.resolvePending('dentiste', 0);
      expect(motif?.reply, contains('Combien de temps'));
      expect(executor.pendingEventDraftId, 'generic-event-draft');
      expect(executor.pendingEventLogicalRequestId, 'logical-generic-event');
      expect(executor.pendingEventExpectedFieldCode, 'duration');
    });

    test('explicit memory request closes a pending generic Event draft',
        () async {
      final coordinator = _coordinator();
      final executor = ConversationLegacyActionExecutor(
        coordinator: coordinator,
        clock: () => DateTime.utc(2026, 7, 29, 10),
      );
      final draft = ConversationClarificationDraft(
        schemaVersion: 1,
        draftType: ConversationClarificationDraftType.eventCreation,
        logicalRequestId: 'logical-generic-event-memory-switch',
        draftId: 'generic-event-memory-switch',
        title: 'Rendez-vous',
        date: '2026-07-30',
        startTime: '15:00',
        durationMinutes: null,
        travelGoMinutes: null,
        travelBackMinutes: null,
        marginMinutes: null,
        expectedField: ConversationEventDraftExpectedField.duration,
        createdAt: DateTime.utc(2026, 7, 29, 10),
        expiresAt: DateTime.utc(2026, 7, 29, 10, 15),
        sessionGeneration: 0,
      );
      expect(executor.registerClarificationDraft(draft, 0), isTrue);

      final result = await executor.resolvePending(
        'Souviens toi que je préfère les rendez-vous le matin',
        0,
      );

      expect(result, isNull);
      expect(executor.hasPendingEventDraft, isFalse);
    });

    test('Event conflict keeps draft identity and consumes a replacement time',
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
      final coordinator = _coordinator();
      final executor = ConversationLegacyActionExecutor(
        coordinator: coordinator,
        clock: () => DateTime.utc(2026, 7, 29, 10),
      );
      final draft = ConversationClarificationDraft(
        schemaVersion: 1,
        draftType: ConversationClarificationDraftType.eventCreation,
        logicalRequestId: 'logical-event-draft',
        draftId: 'event-draft',
        title: 'Consultation médecin',
        date: '2026-07-30',
        startTime: '15:00',
        durationMinutes: null,
        travelGoMinutes: null,
        travelBackMinutes: null,
        marginMinutes: null,
        expectedField: ConversationEventDraftExpectedField.duration,
        createdAt: DateTime.utc(2026, 7, 29, 10),
        expiresAt: DateTime.utc(2026, 7, 29, 10, 15),
        sessionGeneration: 0,
      );
      expect(executor.registerClarificationDraft(draft, 0), isTrue);

      final conflict = await executor.resolvePending('1h', 0);

      expect(conflict?.reply, contains('autre horaire'));
      expect(executor.pendingEventDraftId, 'event-draft');
      expect(executor.pendingEventLogicalRequestId, 'logical-event-draft');
      expect(executor.pendingEventExpectedFieldCode, 'conflictAlternativeTime');

      final ambiguous = await executor.resolvePending('plus tard', 0);
      expect(ambiguous?.reply, contains('heure précise'));
      expect(executor.pendingEventDraftId, 'event-draft');

      final repeatedConflict = await executor.resolvePending('15h', 0);
      expect(repeatedConflict?.reply, contains('autre horaire'));
      expect(executor.pendingEventDraftId, 'event-draft');

      final replacementDate =
          await executor.resolvePending('plutôt vendredi', 0);
      expect(replacementDate?.reply, contains('heure précise'));
      expect(executor.pendingEventDraftId, 'event-draft');

      final replacement = await executor.resolvePending('19heur', 0);
      expect(replacement?.reply, contains('trajet aller'));
      expect(executor.pendingEventDraftId, 'event-draft');
      expect(executor.pendingEventLogicalRequestId, 'logical-event-draft');
      expect(executor.pendingEventExpectedFieldCode, 'travelGo');

      await executor.resolvePending('20 minutes', 0);
      await executor.resolvePending('aucun trajet', 0);
      await executor.resolvePending('aucune', 0);
      expect(coordinator.state.pendingAction?.event.date, '2026-07-31');
      expect(coordinator.state.pendingAction?.event.durationMinutes, 60);
    });

    test('Event conflict proposes a free start and yes keeps the same draft',
        () async {
      final coordinator = _coordinator();
      final conflict = EventModel(
        id: 'pilates',
        title: 'Pilates',
        date: '2026-08-12',
        time: '09:00',
        notes: '',
        createdAt: DateTime(2026, 8, 1),
        startDateTimeIso: '2026-08-12T09:00:00',
        endTime: '10:00',
        endDateTimeIso: '2026-08-12T10:00:00',
        durationMinutes: 60,
      );
      final executor = ConversationLegacyActionExecutor(
        coordinator: coordinator,
        clock: () => DateTime(2026, 8, 11, 17),
        eventStartConflictChecker: ({required startDateTimeIso}) async =>
            startDateTimeIso.contains('09:30') ? conflict : null,
        eventConflictChecker: ({required candidate}) async => null,
        eventStartAlternativeSuggester: ({
          required startDateTimeIso,
          required conflict,
        }) async =>
            DateTime(2026, 8, 12, 10),
      );
      final draft = ConversationClarificationDraft(
        schemaVersion: 1,
        draftType: ConversationClarificationDraftType.eventCreation,
        logicalRequestId: 'logical-dentist',
        draftId: 'draft-dentist',
        title: 'Dentiste',
        date: '2026-08-12',
        startTime: '09:30',
        durationMinutes: null,
        travelGoMinutes: null,
        travelBackMinutes: null,
        marginMinutes: null,
        expectedField: ConversationEventDraftExpectedField.duration,
        createdAt: DateTime(2026, 8, 11, 17),
        expiresAt: DateTime(2026, 8, 11, 17, 15),
        sessionGeneration: 0,
      );

      final reply = await executor.prepareClarificationDraftFromMessage(
        draft,
        0,
        'Dentiste demain à 9h30',
      );

      expect(reply, contains('Pilates'));
      expect(reply, contains('10 h'));
      expect(reply, contains('Est-ce que ça te va'));
      expect(executor.pendingEventDraftId, 'draft-dentist');
      final accepted = await executor.resolvePending('oui', 0);
      expect(accepted?.reply, contains('Combien de temps'));
      expect(executor.pendingEventDraftId, 'draft-dentist');
      expect(executor.pendingEventExpectedFieldCode, 'duration');
    });

    test('refusing a suggested time keeps the Event draft open', () async {
      final coordinator = _coordinator();
      final conflict = EventModel(
        id: 'work',
        title: 'Tes horaires de travail',
        date: '2026-08-17',
        time: '09:00',
        notes: '',
        createdAt: DateTime(2026, 8, 1),
        startDateTimeIso: '2026-08-17T09:00:00',
        endTime: '10:00',
        endDateTimeIso: '2026-08-17T10:00:00',
        durationMinutes: 60,
      );
      final executor = ConversationLegacyActionExecutor(
        coordinator: coordinator,
        clock: () => DateTime(2026, 8, 16, 10),
        eventStartConflictChecker: ({required startDateTimeIso}) async =>
            conflict,
        eventConflictChecker: ({required candidate}) async => null,
        eventStartAlternativeSuggester: ({
          required startDateTimeIso,
          required conflict,
        }) async =>
            DateTime(2026, 8, 17, 10),
      );
      final draft = ConversationClarificationDraft(
        schemaVersion: 1,
        draftType: ConversationClarificationDraftType.eventCreation,
        logicalRequestId: 'logical-refusal',
        draftId: 'draft-refusal',
        title: 'Dentiste',
        date: '2026-08-17',
        startTime: '09:30',
        durationMinutes: null,
        travelGoMinutes: null,
        travelBackMinutes: null,
        marginMinutes: null,
        expectedField: ConversationEventDraftExpectedField.duration,
        createdAt: DateTime(2026, 8, 16, 10),
        expiresAt: DateTime(2026, 8, 16, 10, 15),
        sessionGeneration: 0,
      );
      await executor.prepareClarificationDraftFromMessage(
        draft,
        0,
        'Dentiste demain à 9h30',
      );

      final refused = await executor.resolvePending('non', 0);

      expect(refused?.reply, contains('Quel autre horaire'));
      expect(executor.pendingEventDraftId, 'draft-refusal');
      expect(executor.pendingEventExpectedFieldCode, 'conflictAlternativeTime');
    });

    test('Event continuation keeps travel return and margin structured',
        () async {
      final coordinator = _coordinator();
      final executor = ConversationLegacyActionExecutor(
        coordinator: coordinator,
        clock: () => DateTime.utc(2026, 7, 29, 10),
      );
      await executor.execute(
        const {
          'type': 'event',
          'title': 'Médecin',
          'date': '2026-07-30',
          'time': '15:00',
          'durationMinutes': 0,
        },
        'médecin demain 15h',
        0,
      );

      expect((await executor.resolvePending('une heure', 0))?.reply,
          contains('trajet aller'));
      expect((await executor.resolvePending('15 min', 0))?.reply,
          contains('trajet retour'));
      expect((await executor.resolvePending('vingt minutes', 0))?.reply,
          contains('marge'));
      final confirmation = await executor.resolvePending('aucune', 0);

      expect(confirmation?.reply, contains('Veux-tu que je l’ajoute'));
      expect(coordinator.state.pendingAction?.event.durationMinutes, 60);
      expect(coordinator.state.pendingAction?.event.travelGoMinutes, 15);
      expect(coordinator.state.pendingAction?.event.travelBackMinutes, 20);
      expect(coordinator.state.pendingAction?.event.marginMinutes, 0);
    });

    test('Event contextual bare numbers stay minutes for travel and margin',
        () async {
      final coordinator = _coordinator();
      final executor = ConversationLegacyActionExecutor(
        coordinator: coordinator,
        clock: () => DateTime.utc(2026, 7, 29, 10),
      );
      await executor.execute(
        const {
          'type': 'event',
          'title': 'Médecin',
          'date': '2026-07-30',
          'time': '15:00',
          'durationMinutes': 0,
        },
        'médecin demain 15h',
        0,
      );

      await executor.resolvePending('1h', 0);
      await executor.resolvePending('10', 0);
      await executor.resolvePending('5', 0);
      final confirmation = await executor.resolvePending('5', 0);

      expect(confirmation?.reply, contains('Veux-tu que je l’ajoute'));
      expect(coordinator.state.pendingAction?.event.durationMinutes, 60);
      expect(coordinator.state.pendingAction?.event.travelGoMinutes, 10);
      expect(coordinator.state.pendingAction?.event.travelBackMinutes, 5);
      expect(coordinator.state.pendingAction?.event.marginMinutes, 5);
    });

    test('Event accepts numeric zero for travel and margin', () async {
      final coordinator = _coordinator();
      final executor = ConversationLegacyActionExecutor(
        coordinator: coordinator,
        clock: () => DateTime.utc(2026, 7, 29, 10),
      );
      await executor.execute(
        const {
          'type': 'event',
          'title': 'Médecin',
          'date': '2026-07-30',
          'time': '15:00',
          'durationMinutes': 0,
        },
        'médecin demain 15h',
        0,
      );

      await executor.resolvePending('1h', 0);
      await executor.resolvePending('0', 0);
      await executor.resolvePending('0 minute', 0);
      final confirmation = await executor.resolvePending('zéro', 0);

      expect(confirmation?.reply, contains('Veux-tu que je l’ajoute'));
      expect(coordinator.state.pendingAction?.event.durationMinutes, 60);
      expect(coordinator.state.pendingAction?.event.travelGoMinutes, 0);
      expect(coordinator.state.pendingAction?.event.travelBackMinutes, 0);
      expect(coordinator.state.pendingAction?.event.marginMinutes, 0);
    });

    test('conflict replacement time cannot fill a missing duration', () async {
      final coordinator = _coordinator();
      final executor = ConversationLegacyActionExecutor(
        coordinator: coordinator,
        clock: () => DateTime.utc(2026, 7, 29, 10),
      );
      final draft = ConversationClarificationDraft(
        schemaVersion: 1,
        draftType: ConversationClarificationDraftType.eventCreation,
        logicalRequestId: 'logical-missing-duration',
        draftId: 'event-missing-duration',
        title: 'Consultation médecin',
        date: '2026-07-30',
        startTime: null,
        durationMinutes: null,
        travelGoMinutes: null,
        travelBackMinutes: null,
        marginMinutes: null,
        expectedField:
            ConversationEventDraftExpectedField.conflictAlternativeTime,
        createdAt: DateTime.utc(2026, 7, 29, 10),
        expiresAt: DateTime.utc(2026, 7, 29, 10, 15),
        sessionGeneration: 0,
      );
      expect(executor.registerClarificationDraft(draft, 0), isTrue);

      final replacement = await executor.resolvePending('23h', 0);

      expect(replacement?.reply, contains('Combien de temps'));
      expect(executor.pendingEventExpectedFieldCode, 'duration');
      expect(coordinator.state.pendingAction?.event, isNull);
    });

    test('simple non cancels active Event continuation locally', () async {
      final coordinator = _coordinator();
      final executor = ConversationLegacyActionExecutor(
        coordinator: coordinator,
        clock: () => DateTime.utc(2026, 7, 29, 10),
      );
      await executor.execute(
        const {
          'type': 'event',
          'title': 'Médecin',
          'date': '2026-07-30',
          'time': '15:00',
          'durationMinutes': 0,
        },
        'médecin demain 15h',
        0,
      );

      final cancelled = await executor.resolvePending('non', 0);

      expect(cancelled?.reply, contains('ferme cette préparation'));
      expect(cancelled?.reply, isNot(contains('respecter la négation')));
      expect(executor.hasPendingEventDraft, isFalse);
    });

    test('oral Event confirmation executes once and negative refuses locally',
        () async {
      final coordinator = _coordinator();
      coordinator.setPendingEventConfirmation(_event());
      var executions = 0;

      final accepted = await coordinator.resolvePendingEventConfirmation(
        answer: 'ouais vas-y',
        isPositiveAnswer: PlannerEngineService.isPositiveAnswer,
        isNegativeAnswer: PlannerEngineService.isNegativeAnswer,
        cancellationMessage: (_) => 'Annulé',
        expectedAnswerMessage: () => 'Réponds oui ou non',
        execute: (_) async {
          executions++;
          return 'Créé';
        },
      );
      final repeated = await coordinator.resolvePendingEventConfirmation(
        answer: 'ouais vas-y',
        isPositiveAnswer: PlannerEngineService.isPositiveAnswer,
        isNegativeAnswer: PlannerEngineService.isNegativeAnswer,
        cancellationMessage: (_) => 'Annulé',
        expectedAnswerMessage: () => 'Réponds oui ou non',
        execute: (_) async {
          executions++;
          return 'Créé';
        },
      );

      expect(accepted?.message, 'Créé');
      expect(repeated, isNull);
      expect(executions, 1);

      coordinator.setPendingEventConfirmation(_event());
      final refused = await coordinator.resolvePendingEventConfirmation(
        answer: 'nan',
        isPositiveAnswer: PlannerEngineService.isPositiveAnswer,
        isNegativeAnswer: PlannerEngineService.isNegativeAnswer,
        cancellationMessage: (_) => 'Annulé',
        expectedAnswerMessage: () => 'Réponds oui ou non',
        execute: (_) async => 'Créé',
      );
      expect(refused?.message, 'Annulé');
      expect(coordinator.state.pendingAction, isNull);
    });

    test('composed confirmation answers are never reduced to booleans', () {
      for (final answer in const [
        'ouais mais demain',
        'oui plutôt mardi',
        'vas-y à 16h',
        'd’accord sauf pour le trajet',
        'oui mais sans marge',
      ]) {
        expect(
          PlannerEngineService.isPositiveAnswer(answer),
          isFalse,
          reason: answer,
        );
        expect(
          PlannerEngineService.isNegativeAnswer(answer),
          isFalse,
          reason: answer,
        );
      }
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

    test('routes a stock-out locally to one typed Shopping confirmation',
        () async {
      final backend = _FakeBackend(
        response: const ChatBackendResponse(
          reply: 'Cette réponse ne doit pas être utilisée.',
          actions: [],
          memories: [],
        ),
      );
      final coordinator = ConversationCoordinator(
        backend: backend,
        contextProvider: _FakeContextProvider(_request()),
      );
      var executions = 0;

      final proposal = await coordinator.send(
        input: ConversationInput(
          message: 'J’ai plus de bananes',
          profile: _profile(),
          logicalRequestId: 'shopping-request-1',
        ),
        executeAction: (_) async {
          executions++;
          return const ConversationActionOutcome();
        },
      );

      expect(proposal?.reply, contains('plus de bananes'));
      expect(proposal?.reply, contains('liste de courses'));
      expect(backend.requests, isEmpty);
      expect(executions, 0);
      final pending = coordinator.state.pendingAction?.autonomyPending;
      expect(pending?.actionType, ActionType.addShoppingItem);
      expect(pending?.mutationId, 'shopping-request-1');
      expect(
        (pending?.payload as PendingShoppingPayload).title,
        'bananes',
      );

      Map<String, dynamic>? executed;
      final confirmation = await coordinator.resolvePendingAutonomyConfirmation(
        answer: 'oui',
        sessionGeneration: 0,
        executeAction: (action) async {
          executions++;
          executed = action;
          return const ConversationActionOutcome();
        },
      );
      expect(confirmation?.message, 'C’est ajouté à ta liste de courses.');
      expect(executions, 1);
      expect(executed?['type'], 'shopping');
      expect(executed?['items'], ['bananes']);
      expect(executed?['mutationId'], 'shopping-request-1');
      expect(coordinator.state.pendingAction, isNull);
    });

    test('groups several Shopping items and rejection creates nothing',
        () async {
      final coordinator = ConversationCoordinator(
        backend: _FakeBackend(),
        contextProvider: _FakeContextProvider(_request()),
      );
      final proposal = await coordinator.send(
        input: ConversationInput(
          message: 'Il manque du lait et des œufs',
          profile: _profile(),
        ),
        executeAction: (_) async => const ConversationActionOutcome(),
      );
      expect(proposal?.reply, contains('lait et œufs'));
      final payload = coordinator.state.pendingAction?.autonomyPending?.payload
          as PendingShoppingPayload;
      expect(payload.title, 'lait');
      expect(payload.additionalTitles, ['œufs']);

      var executions = 0;
      final rejection = await coordinator.resolvePendingAutonomyConfirmation(
        answer: 'non',
        sessionGeneration: 0,
        executeAction: (_) async {
          executions++;
          return const ConversationActionOutcome();
        },
      );
      expect(rejection?.message, contains('n’ajoute rien'));
      expect(executions, 0);
      expect(coordinator.state.pendingAction, isNull);
    });

    test('keeps Shopping pending after a storage failure', () async {
      final coordinator = ConversationCoordinator(
        backend: _FakeBackend(),
        contextProvider: _FakeContextProvider(_request()),
      );
      await coordinator.send(
        input: ConversationInput(
          message: 'Ajoute du lait aux courses',
          profile: _profile(),
        ),
        executeAction: (_) async => const ConversationActionOutcome(),
      );

      await expectLater(
        coordinator.resolvePendingAutonomyConfirmation(
          answer: 'oui',
          sessionGeneration: 0,
          executeAction: (_) => throw StateError('synthetic storage failure'),
        ),
        throwsA(
          isA<ConversationShoppingPersistenceException>().having(
            (error) => error.code,
            'code',
            'shopping_local_persist_failed',
          ),
        ),
      );
      expect(
        coordinator.state.pendingAction?.autonomyPending?.state,
        ActionPendingState.pendingSync,
      );
    });

    test('simple stock-out confirmation persists one Shopping item', () async {
      final stored = <ShoppingItemModel>[];
      final mutationIds = <String>[];
      final coordinator = ConversationCoordinator(
        backend: _FakeBackend(),
        contextProvider: _FakeContextProvider(_request()),
      );
      await coordinator.send(
        input: ConversationInput(
          message: 'J’ai plus de banane',
          profile: _profile(),
          logicalRequestId: 'logical-shopping-simple',
        ),
        executeAction: (_) async => const ConversationActionOutcome(),
      );

      final result = await coordinator.resolvePendingAutonomyConfirmation(
        answer: 'oui',
        sessionGeneration: 0,
        executeAction: _shoppingExecutor(
          stored: stored,
          mutationIds: mutationIds,
        ),
      );

      expect(result?.message, 'C’est ajouté à ta liste de courses.');
      expect(stored.map((item) => item.title), ['banane']);
      expect(stored.single.id, isNotEmpty);
      expect(mutationIds, ['logical-shopping-simple']);
    });

    test('grouped confirmation persists two distinct Shopping items once',
        () async {
      final stored = <ShoppingItemModel>[];
      final mutationIds = <String>[];
      final coordinator = ConversationCoordinator(
        backend: _FakeBackend(),
        contextProvider: _FakeContextProvider(_request()),
      );
      await coordinator.send(
        input: ConversationInput(
          message: 'Il manque du lait et des œufs',
          profile: _profile(),
          logicalRequestId: 'logical-shopping-group',
        ),
        executeAction: (_) async => const ConversationActionOutcome(),
      );

      final result = await coordinator.resolvePendingAutonomyConfirmation(
        answer: 'oui',
        sessionGeneration: 0,
        executeAction: _shoppingExecutor(
          stored: stored,
          mutationIds: mutationIds,
        ),
      );

      expect(result?.message, 'C’est ajouté à ta liste de courses.');
      expect(stored.map((item) => item.title), ['lait', 'œufs']);
      expect(stored.map((item) => item.id).toSet(), hasLength(2));
      expect(mutationIds, [
        'logical-shopping-group:0',
        'logical-shopping-group:1',
      ]);
    });

    test('durable local Shopping with unavailable cloud reports pending sync',
        () async {
      final coordinator = ConversationCoordinator(
        backend: _FakeBackend(),
        contextProvider: _FakeContextProvider(_request()),
      );
      await coordinator.send(
        input: ConversationInput(
          message: 'Ajoute du lait aux courses',
          profile: _profile(),
        ),
        executeAction: (_) async => const ConversationActionOutcome(),
      );
      final result = await coordinator.resolvePendingAutonomyConfirmation(
        answer: 'oui',
        sessionGeneration: 0,
        executeAction: _shoppingExecutor(
          stored: [],
          mutationIds: [],
          persistenceStatus: ShoppingPersistenceStatus.synchronizationPending,
        ),
      );
      expect(result?.message, contains('sur cet appareil'));
      expect(result?.message, contains('synchronisation'));
      expect(coordinator.state.pendingAction, isNull);
    });

    test('ambiguous Shopping stays local and a simple yes clarifies again',
        () async {
      final backend = _FakeBackend();
      final coordinator = ConversationCoordinator(
        backend: backend,
        contextProvider: _FakeContextProvider(_request()),
      );

      final first = await coordinator.send(
        input: ConversationInput(
          message: 'Je veux plus de bananes',
          profile: _profile(),
          logicalRequestId: 'ambiguous-shopping-1',
        ),
        executeAction: (_) async => const ConversationActionOutcome(),
      );

      expect(backend.requests, isEmpty);
      expect(first?.reply, contains('acheter davantage de bananes'));
      expect(first?.reply, contains('n’en veux plus'));
      expect(
        coordinator.state.pendingAction?.type,
        PendingConversationActionType.shoppingClarification,
      );
      expect(
        coordinator.state.pendingAction?.shoppingClarification?.article,
        'bananes',
      );

      final stillAmbiguous =
          await coordinator.resolvePendingShoppingClarification(
        answer: 'oui',
        sessionGeneration: 0,
      );
      expect(stillAmbiguous?.message, first?.reply);
      expect(backend.requests, isEmpty);
      expect(
        coordinator.state.pendingAction?.type,
        PendingConversationActionType.shoppingClarification,
      );
    });

    test('Shopping ambiguity resolves to a specific proposal then one add',
        () async {
      final stored = <ShoppingItemModel>[];
      final mutationIds = <String>[];
      final backend = _FakeBackend();
      final coordinator = ConversationCoordinator(
        backend: backend,
        contextProvider: _FakeContextProvider(_request()),
      );
      await coordinator.send(
        input: ConversationInput(
          message: 'Je veux plus de bananes',
          profile: _profile(),
          logicalRequestId: 'ambiguous-shopping-buy',
        ),
        executeAction: (_) async => const ConversationActionOutcome(),
      );

      final proposal = await coordinator.resolvePendingShoppingClarification(
        answer: 'je veux en acheter davantage',
        sessionGeneration: 0,
      );
      expect(
        proposal?.message,
        'Veux-tu que j’ajoute “bananes” à ta liste de courses ?',
      );
      expect(backend.requests, isEmpty);
      expect(
        coordinator.state.pendingAction?.type,
        PendingConversationActionType.autonomyConfirmation,
      );
      expect(stored, isEmpty);

      final completed = await coordinator.resolvePendingAutonomyConfirmation(
        answer: 'oui',
        sessionGeneration: 0,
        executeAction: _shoppingExecutor(
          stored: stored,
          mutationIds: mutationIds,
        ),
      );
      expect(completed?.message, 'C’est ajouté à ta liste de courses.');
      expect(stored.map((item) => item.title), ['bananes']);
      expect(mutationIds, ['ambiguous-shopping-buy']);
    });

    test('Shopping ambiguity refusal closes without creating an action',
        () async {
      final backend = _FakeBackend();
      final coordinator = ConversationCoordinator(
        backend: backend,
        contextProvider: _FakeContextProvider(_request()),
      );
      await coordinator.send(
        input: ConversationInput(
          message: 'Je veux plus de lait',
          profile: _profile(),
        ),
        executeAction: (_) async => const ConversationActionOutcome(),
      );

      final refusal = await coordinator.resolvePendingShoppingClarification(
        answer: 'je n’en veux plus',
        sessionGeneration: 0,
      );
      expect(refusal?.message, contains('je n’ajoute rien'));
      expect(coordinator.state.pendingAction, isNull);
      expect(backend.requests, isEmpty);
    });

    test('Shopping ambiguity recognizes bounded purchase and refusal answers',
        () async {
      for (final answer in const [
        'davantage',
        'en acheter plus',
        'ajoute-les aux courses',
        'oui, j’en veux plus',
        'je veux en racheter',
      ]) {
        final coordinator = ConversationCoordinator(
          backend: _FakeBackend(),
          contextProvider: _FakeContextProvider(_request()),
        );
        await coordinator.send(
          input: ConversationInput(
            message: 'Je veux plus de bananes',
            profile: _profile(),
          ),
          executeAction: (_) async => const ConversationActionOutcome(),
        );
        await coordinator.resolvePendingShoppingClarification(
          answer: answer,
          sessionGeneration: 0,
        );
        expect(
          coordinator.state.pendingAction?.type,
          PendingConversationActionType.autonomyConfirmation,
          reason: answer,
        );
      }

      for (final answer in const [
        'je n’en veux plus',
        'je ne veux plus de bananes',
        'non, je n’en veux plus',
        'retire cette idée',
      ]) {
        final coordinator = ConversationCoordinator(
          backend: _FakeBackend(),
          contextProvider: _FakeContextProvider(_request()),
        );
        await coordinator.send(
          input: ConversationInput(
            message: 'Je veux plus de bananes',
            profile: _profile(),
          ),
          executeAction: (_) async => const ConversationActionOutcome(),
        );
        await coordinator.resolvePendingShoppingClarification(
          answer: answer,
          sessionGeneration: 0,
        );
        expect(coordinator.state.pendingAction, isNull, reason: answer);
      }
    });
  });
}

ConversationActionExecutor _shoppingExecutor({
  required List<ShoppingItemModel> stored,
  required List<String> mutationIds,
  ShoppingPersistenceStatus persistenceStatus =
      ShoppingPersistenceStatus.durable,
}) =>
    (action) async {
      final result = await ActionHandlerService.handleAction(
        action: action,
        currentUserMessage: 'confirmation Shopping synthétique',
        normalizeTime: (value) => value,
        parseDurationMinutes: (_) => 0,
        weekdayFromText: () => 0,
        messageLooksRecurringWeekly: () => false,
        nextDateForWeekday: (_) => '',
        eventNeedsTravel: (_) => false,
        buildStartDateTimeIso: ({required date, required time}) => '',
        buildEndDateTimeIso: ({
          required date,
          required time,
          required durationMinutes,
        }) =>
            '',
        endTimeFromDuration: ({
          required date,
          required time,
          required durationMinutes,
        }) =>
            '',
        shoppingItemWriter: (item, {mutationId}) async {
          stored.add(item);
          mutationIds.add(mutationId ?? '');
          return ShoppingPersistenceResult(
            status: persistenceStatus,
            entityId: item.id!,
          );
        },
      );
      return ConversationActionOutcome(message: result.message);
    };

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

final class _SlotSearchGateway implements SmartPlanningContinuationGateway {
  @override
  Future<void> addEvent(EventModel event, {String? mutationId}) async {}

  @override
  Future<SmartPlanningProposal> buildProposal({
    required TaskModel task,
    required String originalMessage,
    required int actionMinutes,
    required int travelGoMinutes,
    required int travelBackMinutes,
    required List<TaskModel> groupedTasks,
  }) =>
      throw UnimplementedError();

  @override
  Future<EventModel?> conflict(EventModel event) async => null;

  @override
  Future<PlanningProposalEngineResult> findOptions({
    required DateTime startDate,
    required int totalMinutes,
    required int searchDays,
  }) async =>
      const PlanningProposalEngineResult(
        hasOptions: false,
        options: [],
        explanation: '',
      );

  @override
  Future<List<TaskModel>> relatedTasks(
    TaskModel task,
    String originalMessage,
  ) async =>
      [task];

  @override
  Future<SelectedSlotRevalidationResult> revalidate({
    required EventModel event,
    required DateTime protectedStart,
    required int totalMinutes,
  }) async =>
      const SelectedSlotRevalidationResult(
        isAvailable: true,
        conflictEvent: null,
        alternatives: PlanningProposalEngineResult(
          hasOptions: false,
          options: [],
          explanation: '',
        ),
      );
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

ChatBackendRequest _completeTaskRequest() => ChatBackendRequest(
      message: 'Crée une tâche prioritaire pour demain.',
      context: ConversationContextEnvelope(
        projectionVersion: 1,
        purpose: ConversationTransportContract.purposeId,
        generatedAt: DateTime.utc(2026, 7, 27, 10),
        state: ConversationContextState.complete,
        sections: const [],
        budgetRequested: 245,
        budgetUsed: 0,
        omittedCount: 0,
        truncatedSections: const [],
        warningCodes: const [],
      ),
    );

Map<String, dynamic> _deterministicTaskClarificationJson() => {
      'reply': 'Quelle tâche veux-tu créer ?',
      'actions': <dynamic>[],
      'memories': <dynamic>[],
      'epistemic': {
        'schemaVersion': 1,
        'responseKind': 'clarificationRequired',
        'epistemicState': 'insufficientInformation',
        'confidenceLevel': 'low',
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
          },
        ],
        'personalClaims': <dynamic>[],
        'missingInformation': [
          {
            'schemaVersion': 1,
            'code': 'missingTaskTarget',
            'domain': 'task',
            'field': 'target',
            'isRequired': true,
            'canClarify': true,
          },
        ],
        'contradictions': <dynamic>[],
        'clarification': {
          'schemaVersion': 1,
          'clarificationId': 'task-title-0',
          'reasonCode': 'task_title_required',
          'questionText': 'Quelle tâche veux-tu créer ?',
          'expectedAnswerType': 'freeTextBounded',
          'allowedChoices': <dynamic>[],
          'missingFieldCodes': ['missingTaskTarget'],
          'createdAt': '2026-07-27T10:00:00.000Z',
          'expiresAt': null,
          'attemptNumber': 1,
          'maximumAttempts': 3,
          'sessionGeneration': 0,
          'draft': null,
        },
        'uncertaintyCodes': ['missingRequiredInformation'],
        'contextStateObserved': 'complete',
        'warningCodes': <dynamic>[],
        'responseId': 'task-clarification-0',
      },
    };

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

ConversationEpistemicContract _epistemic({
  required ConversationResponseKind kind,
}) =>
    ConversationEpistemicContract(
      responseKind: kind,
      epistemicState: ConversationEpistemicState.grounded,
      confidenceLevel: ConversationConfidenceLevel.high,
      usedSourceTypes: const [
        ConversationGroundingSourceType.currentUserMessage,
      ],
      groundingReferences: const [
        ConversationGroundingReference(
          sourceType: ConversationGroundingSourceType.currentUserMessage,
          freshness: 'current',
          confirmation: 'confirmed',
          projectionVersion: 0,
        ),
      ],
      personalClaims: const [],
      missingInformation: const [],
      contradictions: const [],
      uncertaintyCodes: const [],
      contextStateObserved: ConversationContextState.unavailable,
      warningCodes: const [],
      responseId: 'response-test',
    );

ConversationEpistemicContract _taskTitleClarification({
  int sessionGeneration = 0,
}) =>
    ConversationEpistemicContract(
      responseKind: ConversationResponseKind.clarificationRequired,
      epistemicState: ConversationEpistemicState.insufficientInformation,
      confidenceLevel: ConversationConfidenceLevel.low,
      usedSourceTypes: const [
        ConversationGroundingSourceType.currentUserMessage,
      ],
      groundingReferences: const [
        ConversationGroundingReference(
          sourceType: ConversationGroundingSourceType.currentUserMessage,
          freshness: 'current',
          confirmation: 'confirmed',
          projectionVersion: 0,
        ),
      ],
      personalClaims: const [],
      missingInformation: const [
        ConversationMissingInformation(
          code: ConversationMissingInformationCode.missingTaskTarget,
          domain: 'task',
          field: 'target',
          isRequired: true,
          canClarify: true,
        ),
      ],
      contradictions: const [],
      clarification: ConversationClarification(
        clarificationId: 'task-title-0',
        reasonCode: 'task_title_required',
        questionText: 'Quelle tâche veux-tu créer ?',
        expectedAnswerType: ConversationClarificationAnswerType.freeTextBounded,
        allowedChoices: const [],
        missingFieldCodes: const [
          ConversationMissingInformationCode.missingTaskTarget,
        ],
        createdAt: DateTime.utc(2026, 7, 27),
        attemptNumber: 1,
        sessionGeneration: sessionGeneration,
      ),
      uncertaintyCodes: const [
        ConversationUncertaintyCode.missingRequiredInformation,
      ],
      contextStateObserved: ConversationContextState.unavailable,
      warningCodes: const [],
      responseId: 'task-clarification-0',
    );
