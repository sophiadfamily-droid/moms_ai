import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/action_autonomy_policy.dart';
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

    test('quick reply is submitted once and choices disappear', () async {
      final harness = _Harness();
      harness.controller.addInitialAssistantMessageWithQuickReplies(
        'Tu préfères qu’on s’en occupe maintenant ou plus tard ?',
        [
          ConversationQuickReply(
            id: 'now',
            label: 'Maintenant',
            submission: 'Occupons-nous-en maintenant.',
          ),
          ConversationQuickReply(
            id: 'later',
            label: 'Plus tard',
            submission: 'Garde la préparation du voyage pour plus tard.',
          ),
        ],
      );

      final promptId = harness.controller.state.messages.single.id;
      expect(harness.controller.state.quickReplyMessageId, promptId);
      expect(harness.controller.state.quickReplies, hasLength(2));

      await harness.controller.dispatch(SelectConversationQuickReply('later'));

      expect(harness.controller.state.quickReplies, isEmpty);
      expect(harness.controller.state.quickReplyMessageId, isNull);
      expect(
        harness.controller.state.messages
            .where((message) => message.role == ConversationMessageRole.user)
            .map((message) => message.text),
        ['Plus tard'],
      );
      expect(harness.backend.calls, 1);
      expect(harness.context.messages,
          ['Garde la préparation du voyage pour plus tard.']);
      harness.dispose();
    });

    test('discussion quick reply bypasses local mutations', () async {
      var localResolverCalls = 0;
      final harness = _Harness(
        resolveLocalRequest: (_, __) async {
          localResolverCalls++;
          return const ConversationOutcome(reply: 'Modification locale');
        },
      );
      harness.controller.addInitialAssistantMessageWithQuickReplies(
        'Une anticipation précise',
        [
          ConversationQuickReply(
            id: 'now',
            label: 'Maintenant',
            submission: 'Une anticipation précise. Aide-moi à y réfléchir.',
            discussionOnly: true,
          ),
        ],
      );

      await harness.controller.dispatch(SelectConversationQuickReply('now'));

      expect(localResolverCalls, 0);
      expect(harness.backend.calls, 1);
      expect(harness.backend.requests.single.autonomyMode,
          ActionAutonomyMode.paused);
      expect(harness.backend.requests.single.conversationMode,
          ChatConversationMode.guidedDiscussion);
      expect(
        harness.controller.state.messages
            .where((message) => message.role == ConversationMessageRole.user)
            .single
            .text,
        'Maintenant',
      );

      await harness.controller.submitText('resto');

      expect(localResolverCalls, 0);
      expect(harness.backend.calls, 2);
      expect(harness.backend.requests.last.autonomyMode,
          ActionAutonomyMode.paused);
      expect(harness.backend.requests.last.conversationMode,
          ChatConversationMode.guidedDiscussion);
      expect(harness.backend.requests.last.message,
          contains('Une anticipation précise'));
      expect(harness.backend.requests.last.message, contains('resto'));
      expect(harness.backend.requests.last.message, contains('Réponse'));

      await harness.controller.submitText('aide à trouver');

      expect(localResolverCalls, 0);
      expect(harness.backend.calls, 3);
      expect(harness.backend.requests.last.autonomyMode,
          ActionAutonomyMode.paused);
      expect(harness.backend.requests.last.conversationMode,
          ChatConversationMode.guidedDiscussion);
      expect(harness.backend.requests.last.message, contains('resto'));
      expect(harness.backend.requests.last.message, contains('aide à trouver'));
      harness.dispose();
    });

    test('an explicit action leaves the bounded dashboard discussion',
        () async {
      var localResolverCalls = 0;
      final harness = _Harness(
        resolveLocalRequest: (_, __) async {
          localResolverCalls++;
          return const ConversationOutcome(reply: 'Modification locale');
        },
      );
      harness.controller.addInitialAssistantMessageWithQuickReplies(
        'Préparons l’anniversaire de Willy.',
        [
          ConversationQuickReply(
            id: 'now',
            label: 'Maintenant',
            submission: 'Aide-moi à préparer l’anniversaire de Willy.',
            discussionOnly: true,
          ),
        ],
      );

      await harness.controller.dispatch(SelectConversationQuickReply('now'));
      await harness.controller.submitText('Ajoute appeler le restaurant');

      expect(localResolverCalls, 1);
      expect(harness.backend.calls, 1);
      expect(
          harness.controller.state.messages.last.text, 'Modification locale');
      harness.dispose();
    });

    test('a free response removes quick replies from the previous subject',
        () async {
      final harness = _Harness();
      harness.controller.addInitialAssistantMessageWithQuickReplies(
        'Une suggestion',
        [
          ConversationQuickReply(
            id: 'later',
            label: 'Plus tard',
            submission: 'Plus tard.',
          ),
        ],
      );

      await harness.controller.submitText('Je veux parler d’autre chose.');

      expect(harness.controller.state.quickReplies, isEmpty);
      expect(harness.controller.state.quickReplyMessageId, isNull);
      harness.dispose();
    });

    test('a short answer to the latest question keeps bounded context',
        () async {
      final harness = _Harness();
      harness.controller.addInitialAssistantMessage(
        'Quel type de sortie aimerais-tu pour Willy ?',
      );

      await harness.controller.submitText('resto');

      final request = harness.backend.requests.single;
      expect(
        request.conversationMode,
        ChatConversationMode.contextualFollowUp,
      );
      expect(request.autonomyMode, isNot(ActionAutonomyMode.paused));
      expect(request.history, hasLength(1));
      expect(request.history.single.role, 'assistant');
      expect(
        request.history.single.text,
        'Quel type de sortie aimerais-tu pour Willy ?',
      );
      expect(request.message, 'resto');
      harness.dispose();
    });

    test('bounded context remains serializable with long emoji messages',
        () async {
      final harness = _Harness();
      for (var index = 0; index < 8; index++) {
        harness.controller.addInitialAssistantMessage(
          'Contexte $index ${'💕' * 1000}${index == 7 ? '?' : '.'}',
        );
      }

      await harness.controller.submitText('resto');

      final request = harness.backend.requests.single;
      expect(request.history, isNotEmpty);
      expect(request.history.length, lessThanOrEqualTo(8));
      expect(
        utf8
            .encode(
              jsonEncode(
                request.history.map((item) => item.toJson()).toList(),
              ),
            )
            .length,
        lessThanOrEqualTo(
          ConversationTransportContract.maximumHistoryUtf8Bytes,
        ),
      );
      expect(() => request.toJson(), returnsNormally);
      harness.dispose();
    });

    test('an explicit new action after a question keeps normal routing',
        () async {
      var localResolverCalls = 0;
      final harness = _Harness(
        resolveLocalRequest: (_, __) async {
          localResolverCalls++;
          return const ConversationOutcome(reply: 'Action locale');
        },
      );
      harness.controller.addInitialAssistantMessage(
        'Que veux-tu préparer ?',
      );

      await harness.controller.submitText('Ajoute du lait aux courses');

      expect(localResolverCalls, 1);
      expect(harness.backend.calls, 0);
      expect(harness.controller.state.messages.last.text, 'Action locale');
      harness.dispose();
    });

    test('a standalone question after another question stays standard',
        () async {
      final harness = _Harness();
      harness.controller.addInitialAssistantMessage(
        'Que veux-tu préparer ?',
      );

      await harness.controller.submitText('Quelle est ma date de mariage ?');

      expect(
        harness.backend.requests.single.conversationMode,
        ChatConversationMode.standard,
      );
      expect(harness.backend.requests.single.history, hasLength(1));
      harness.dispose();
    });

    test('runs two independent requests in order from one visible message',
        () async {
      final handled = <String>[];
      final harness = _Harness(
        resolveLocalRequest: (message, _) async {
          handled.add(message);
          return ConversationOutcome(reply: 'Traité : $message');
        },
      );

      await harness.controller.submitText(
        'Dentiste demain à 14h puis ajoute du lait aux courses',
      );

      expect(
        handled,
        ['Dentiste demain à 14h', 'ajoute du lait aux courses'],
      );
      expect(harness.backend.calls, 0);
      expect(
        harness.controller.state.messages
            .where((message) => message.role == ConversationMessageRole.user)
            .map((message) => message.text),
        ['Dentiste demain à 14h puis ajoute du lait aux courses'],
      );
      expect(
        harness.controller.state.messages
            .where(
              (message) => message.role == ConversationMessageRole.assistant,
            )
            .map((message) => message.text),
        [
          'Traité : Dentiste demain à 14h',
          'Traité : ajoute du lait aux courses',
        ],
      );
      expect(harness.controller.state.phase, ConversationSessionPhase.ready);
      harness.dispose();
    });

    test('continues after an explicitly saved memory without another yes',
        () async {
      final handled = <String>[];
      final harness = _Harness(
        resolveLocalRequest: (message, _) async {
          handled.add(message);
          if (message.startsWith('Souviens-toi')) {
            return const ConversationOutcome(
              reply: 'C’est noté, cette information est mémorisée.',
            );
          }
          return const ConversationOutcome(
            reply: 'Fraises ajoutées aux courses.',
          );
        },
      );

      await harness.controller.submitText(
        'Souviens-toi que j’aime préparer mes affaires la veille et ajoute '
        'des fraises aux courses',
      );

      expect(handled, [
        'Souviens-toi que j’aime préparer mes affaires la veille',
        'ajoute des fraises aux courses',
      ]);
      expect(
        harness.controller.state.messages
            .where((message) => message.role == ConversationMessageRole.user)
            .map((message) => message.text),
        [
          'Souviens-toi que j’aime préparer mes affaires la veille et ajoute '
              'des fraises aux courses',
        ],
      );
      expect(
        harness.controller.state.messages
            .where(
              (message) => message.role == ConversationMessageRole.assistant,
            )
            .map((message) => message.text),
        [
          'C’est noté, cette information est mémorisée.',
          'Fraises ajoutées aux courses.',
        ],
      );
      expect(harness.controller.state.phase, ConversationSessionPhase.ready);
      harness.dispose();
    });

    test('waits for the first confirmation before running the next request',
        () async {
      var awaitingConfirmation = false;
      final locallyHandled = <String>[];
      final pendingAnswers = <String>[];
      final harness = _Harness(
        applicationPendingPhase: () => awaitingConfirmation
            ? ConversationSessionPhase.awaitingConfirmation
            : null,
        resolvePending: (answer, _) async {
          if (!awaitingConfirmation) return null;
          pendingAnswers.add(answer);
          awaitingConfirmation = false;
          return const ConversationOutcome(reply: 'Rendez-vous confirmé.');
        },
        resolveLocalRequest: (message, _) async {
          locallyHandled.add(message);
          if (message.startsWith('Dentiste')) {
            awaitingConfirmation = true;
            return const ConversationOutcome(
              reply: 'Veux-tu ajouter ce rendez-vous ?',
              responseKind: ConversationResponseKind.confirmationRequired,
            );
          }
          return const ConversationOutcome(reply: 'Lait ajouté aux courses.');
        },
      );

      await harness.controller.submitText(
        'Dentiste demain à 14h puis ajoute du lait aux courses',
      );

      expect(locallyHandled, ['Dentiste demain à 14h']);
      expect(harness.controller.state.phase,
          ConversationSessionPhase.awaitingConfirmation);

      await harness.controller.submitText('oui');

      expect(pendingAnswers, ['oui']);
      expect(
        locallyHandled,
        ['Dentiste demain à 14h', 'ajoute du lait aux courses'],
      );
      expect(harness.backend.calls, 0);
      expect(harness.controller.state.phase, ConversationSessionPhase.ready);
      harness.dispose();
    });

    test('keeps a contextual clarification answer separate from a new request',
        () async {
      var awaitingMotif = true;
      final pendingAnswers = <String>[];
      final locallyHandled = <String>[];
      final harness = _Harness(
        applicationPendingPhase: () => awaitingMotif
            ? ConversationSessionPhase.awaitingClarification
            : null,
        resolvePending: (answer, _) async {
          if (!awaitingMotif) return null;
          pendingAnswers.add(answer);
          awaitingMotif = false;
          return const ConversationOutcome(reply: 'Motif ajouté : dentiste.');
        },
        resolveLocalRequest: (message, _) async {
          locallyHandled.add(message);
          return const ConversationOutcome(reply: 'Lait ajouté aux courses.');
        },
      );

      await harness.controller.submitText(
        'dentiste et ajoute du lait aux courses',
      );

      expect(pendingAnswers, ['dentiste']);
      expect(locallyHandled, ['ajoute du lait aux courses']);
      expect(harness.backend.calls, 0);
      expect(
        harness.controller.state.messages
            .where((message) => message.role == ConversationMessageRole.user)
            .map((message) => message.text),
        ['dentiste et ajoute du lait aux courses'],
      );
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

    test('a completed request resets clarification limits for the next one',
        () async {
      final clarification = ConversationClarification(
        clarificationId: 'clarification-reset',
        reasonCode: 'event_duration_required',
        questionText: 'Combien de temps dure le rendez-vous ?',
        expectedAnswerType: ConversationClarificationAnswerType.duration,
        allowedChoices: const [],
        missingFieldCodes: const [
          ConversationMissingInformationCode.missingDuration,
        ],
        createdAt: DateTime.utc(2026, 7, 23),
        attemptNumber: 1,
        sessionGeneration: 0,
      );
      var calls = 0;
      final harness = _Harness(
        resolvePending: (_, __) async {
          calls++;
          if (calls == 2) {
            return const ConversationOutcome(reply: 'C’est noté.');
          }
          return ConversationOutcome(
            reply: clarification.questionText,
            responseKind: ConversationResponseKind.clarificationRequired,
            epistemicClarification: clarification,
          );
        },
      );

      await harness.controller.submitText('Dentiste demain à 9h30');
      await harness.controller.submitText('1h');
      expect(harness.controller.state.phase, ConversationSessionPhase.ready);

      await harness.controller.submitText('Médecin demain à 14h');

      expect(
        harness.controller.state.messages.last.text,
        'Combien de temps dure le rendez-vous ?',
      );
      expect(
        harness.controller.state.messages.last.text,
        isNot(contains('informations restent insuffisantes')),
      );
      expect(
        harness.controller.state.phase,
        ConversationSessionPhase.awaitingClarification,
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

    test('an explicit Event is prepared locally when the backend is offline',
        () async {
      final backend = _Backend(error: ChatBackendTimeoutException());
      final controller = ConversationSessionController.production(
        profile: _profile(),
        backendClient: backend,
        contextProvider: _Context(),
        messageStore: _Store(),
        accountScopeId: 'account',
        eventStartConflictChecker: ({required startDateTimeIso}) async {
          expect(startDateTimeIso, contains('2026-07-30T09:30'));
          return EventModel(
            title: 'ton Pilates',
            date: '2026-07-30',
            time: '09:00',
            notes: '',
            createdAt: DateTime.utc(2026, 7, 29),
            startDateTimeIso: '2026-07-30T09:00:00.000',
            endDateTimeIso: '2026-07-30T10:00:00.000',
            durationMinutes: 60,
          );
        },
        eventConflictChecker: ({required candidate}) async => null,
        eventStartAlternativeSuggester: ({
          required startDateTimeIso,
          required conflict,
        }) async =>
            DateTime(2026, 7, 30, 10, 15),
        clock: () => DateTime(2026, 7, 29, 12),
        idGenerator: () => 'production-local-event-offline',
      );

      await controller.submitText('Coiffeur demain à 9h30');

      expect(backend.calls, 0);
      expect(controller.state.messages.last.text, contains('ton Pilates'));
      expect(controller.state.messages.last.text, contains('10 h 15'));
      expect(controller.state.messages.last.text, contains('ça te va'));
      expect(controller.state.phase,
          ConversationSessionPhase.awaitingClarification);
      controller.dispose();
    });

    test('a generic explicit Event asks its motif without the backend',
        () async {
      final backend = _Backend(error: ChatBackendTimeoutException());
      final controller = ConversationSessionController.production(
        profile: _profile(),
        backendClient: backend,
        contextProvider: _Context(),
        messageStore: _Store(),
        accountScopeId: 'account',
        eventStartConflictChecker: ({required startDateTimeIso}) async => null,
        eventConflictChecker: ({required candidate}) async => null,
        clock: () => DateTime(2026, 7, 29, 12),
        idGenerator: () => 'production-local-generic-event',
      );

      await controller.submitText('rdv demain 14 heures');

      expect(backend.calls, 0);
      expect(controller.state.messages.last.text, contains('motif'));
      expect(controller.state.phase,
          ConversationSessionPhase.awaitingClarification);
      controller.dispose();
    });

    test('a local Event reaches confirmation and is saved without the backend',
        () async {
      SharedPreferences.setMockInitialValues({});
      final backend = _Backend(error: ChatBackendTimeoutException());
      final controller = ConversationSessionController.production(
        profile: _profile(),
        backendClient: backend,
        contextProvider: _Context(),
        messageStore: _Store(),
        accountScopeId: 'account',
        eventStartConflictChecker: ({required startDateTimeIso}) async => null,
        eventConflictChecker: ({required candidate}) async => null,
        clock: () => DateTime(2026, 7, 29, 12),
        idGenerator: () => 'production-local-event-full-path',
      );

      await controller.submitText('Coiffeur demain à 9h30');
      await controller.submitText('1h');
      await controller.submitText('10');
      await controller.submitText('10');
      await controller.submitText('0');

      expect(backend.calls, 0);
      expect(controller.state.phase,
          ConversationSessionPhase.awaitingConfirmation);
      await controller.submitText('oui');
      expect(controller.state.messages.last.text, contains('agenda'));

      final preferences = await SharedPreferences.getInstance();
      final storedValues = preferences
          .getKeys()
          .where((key) => key.startsWith('${EventService.eventsKey}:'))
          .expand((key) => preferences.getStringList(key) ?? const <String>[])
          .toList(growable: false);
      expect(storedValues, hasLength(1));
      final stored = EventModel.fromJson(jsonDecode(storedValues.single));
      expect(stored.title, 'Rendez-vous Coiffeur');
      expect(stored.time, '09:30');
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

      await controller.submitText('Prépare mon rendez-vous');

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

    test('an occupied local Event replaces the duration question', () async {
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
      expect(backend.invocations, 0);
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

      await controller.submitText('Prépare mon rendez-vous');
      await controller.submitText('1h');
      expect(controller.state.messages.last.text, contains('trajet aller'));
      await controller.submitText('vingt minutes');
      expect(controller.state.messages.last.text, contains('trajet retour'));
      await controller.submitText('aucun trajet');
      expect(controller.state.messages.last.text, contains('marge'));
      await controller.submitText('0');

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
        'production composition clarifies a backend generic Event title and creates once',
        () async {
      SharedPreferences.setMockInitialValues({});
      final json = jsonDecode(jsonEncode(_eventDraftCallableJson()))
          as Map<String, dynamic>;
      final epistemic = json['epistemic'] as Map<String, dynamic>;
      final clarification = epistemic['clarification'] as Map<String, dynamic>;
      final draft = clarification['draft'] as Map<String, dynamic>;
      draft['title'] = 'Rendez-vous';
      draft['startTime'] = '14:00';
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

      await controller.submitText('Prépare mon rendez-vous');
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

      await controller.submitText('Prépare mon rendez-vous');

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

      await controller.submitText('Prépare mon rendez-vous');
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
      await expiring.submitText('Prépare mon rendez-vous');
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
      await account.submitText('Prépare mon rendez-vous');
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
    ConversationLocalRequestResolver? resolveLocalRequest,
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
      resolveLocalRequest: resolveLocalRequest,
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
  final List<ChatBackendRequest> requests = [];

  @override
  Future<ChatBackendResponse> send(ChatBackendRequest request) async {
    calls++;
    requests.add(request);
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
  final List<String> messages = [];

  @override
  Future<ChatBackendRequest> buildRequest({
    required String message,
    required UserProfile profile,
  }) async {
    calls++;
    messages.add(message);
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
