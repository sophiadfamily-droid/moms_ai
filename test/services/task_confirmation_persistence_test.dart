import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/chat_backend_request.dart';
import 'package:moms_ai/models/action_autonomy_policy.dart';
import 'package:moms_ai/models/conversation_context_envelope.dart';
import 'package:moms_ai/models/conversation_session_models.dart';
import 'package:moms_ai/models/life_context/life_context_projection.dart';
import 'package:moms_ai/models/task_model.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/services/callable_chat_backend_client.dart';
import 'package:moms_ai/services/conversation_context_service.dart';
import 'package:moms_ai/services/conversation_coordinator.dart';
import 'package:moms_ai/services/conversation_legacy_action_executor.dart';
import 'package:moms_ai/services/conversation_session_controller.dart';
import 'package:moms_ai/services/smart_planning_continuation_coordinator.dart';
import 'package:moms_ai/services/task_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('full Task clarification confirmation persists exactly once', () async {
    SharedPreferences.setMockInitialValues({});
    final backend = CallableChatBackendClient.withInvoker(
      (_) async => _taskClarificationJson(),
    );
    final controller = ConversationSessionController.production(
      profile: _profile(),
      backendClient: backend,
      contextProvider: _ContextProvider(_request()),
      messageStore: const _NoopMessageStore(),
      accountScopeId: 'synthetic-account',
      clock: () => DateTime.utc(2026, 7, 27, 10),
    );

    await controller.submitText('Crée une tâche prioritaire pour demain.');
    expect(controller.state.messages.last.text, 'Quelle tâche veux-tu créer ?');

    await controller.submitText('Envoyer le dossier à la mutuelle.');
    expect(controller.state.messages.last.text, contains('2026-07-28'));
    expect(controller.state.messages.last.text, contains('Priorité : Haute'));

    await controller.submitText('oui');

    expect(
      controller.state.messages.last.text,
      isNot(contains('problème temporaire')),
    );
    expect(controller.state.messages.last.text, contains('C’est fait.'));
    expect(
      controller.state.messages.last.text,
      contains('cherche un créneau'),
    );
    final tasks = await _storedTasks();
    expect(tasks, hasLength(1));
    expect(tasks.single.title, 'Envoyer le dossier à la mutuelle.');
    expect(tasks.single.dueDate, '2026-07-28');
    expect(tasks.single.priority, 'Haute');
    expect(tasks.single.isImportant, isTrue);

    await controller.submitText('oui');
    expect(controller.state.messages.last.text, contains('30 min'));
    expect(await _storedTasks(), hasLength(1));
  });

  test('an independent Priority intent closes planning consent and routes',
      () async {
    SharedPreferences.setMockInitialValues({});
    var backendCalls = 0;
    final backend = CallableChatBackendClient.withInvoker(
      (_) async {
        backendCalls++;
        return _taskClarificationJson();
      },
    );
    final controller = ConversationSessionController.production(
      profile: _profile(),
      backendClient: backend,
      contextProvider: _ContextProvider(_request()),
      messageStore: const _NoopMessageStore(),
      accountScopeId: 'synthetic-account',
      clock: () => DateTime.utc(2026, 7, 27, 10),
    );

    await controller.submitText('Crée une tâche prioritaire pour demain.');
    await controller.submitText('Vérifier les documents de la mutuelle.');
    await controller.submitText('oui');
    expect(controller.state.messages.last.text, contains('cherche un créneau'));

    await controller.submitText('Quelles sont mes priorités cette semaine ?');

    expect(controller.state.messages.last.text, isNot(contains('oui ou non')));
    expect(
      controller.state.messages.last.text,
      contains('priorité fiable'),
    );
    expect(backendCalls, 1);
    expect(await _storedTasks(), hasLength(1));

    await controller.submitText('oui');
    expect(controller.state.messages.last.text, isNot(contains('30 min')));
    expect(backendCalls, 2);
    expect(await _storedTasks(), hasLength(1));
  });

  test('does not reload policy after a confirmed Task has been persisted',
      () async {
    SharedPreferences.setMockInitialValues({});
    var policyLoads = 0;
    Future<ActionAutonomyPolicy> loadPolicy() async {
      policyLoads++;
      if (policyLoads == 5) {
        throw const FormatException('synthetic_post_write_policy_failure');
      }
      return ActionAutonomyPolicy(
        mode: ActionAutonomyMode.suggestions,
        changedAt: DateTime.utc(2026, 7, 27),
        changeSource: ActionAutonomyChangeSource.explicitUserSetting,
        accountScopeId: 'synthetic-account',
      );
    }

    final coordinator = ConversationCoordinator(
      backend: CallableChatBackendClient.withInvoker(
        (_) async => _taskClarificationJson(),
      ),
      contextProvider: _ContextProvider(_request()),
      loadAutonomyPolicy: loadPolicy,
      clock: () => DateTime.utc(2026, 7, 27, 10),
    );
    final smartPlanning = SmartPlanningContinuationCoordinator(
      gateway: ProductionSmartPlanningContinuationGateway(_profile()),
      loadAutonomyPolicy: loadPolicy,
      clock: () => DateTime.utc(2026, 7, 27, 10),
    );
    final executor = ConversationLegacyActionExecutor(
      coordinator: coordinator,
      smartPlanning: smartPlanning,
      loadAutonomyPolicy: loadPolicy,
    );
    final controller = ConversationSessionController(
      profile: _profile(),
      coordinator: coordinator,
      executeAction: executor.execute,
      resolvePending: executor.resolvePending,
      messageStore: const _NoopMessageStore(),
      accountScopeId: 'synthetic-account',
      clock: () => DateTime.utc(2026, 7, 27, 10),
    );

    await controller.submitText('Crée une tâche prioritaire pour demain.');
    await controller.submitText('Envoyer le dossier à la mutuelle.');
    await controller.submitText('oui');

    expect(policyLoads, 3);
    expect(await _storedTasks(), hasLength(1));
    expect(
      controller.state.messages.last.text,
      isNot(contains('problème temporaire')),
    );
  });

  test('planning consent accepts non and closes the visible proposal',
      () async {
    final fixture = _planningFixture();
    fixture.smartPlanning.beginTaskPlanning(
      task: _planningTask(),
      originalMessage: 'Créer la tâche',
      sessionGeneration: 0,
    );

    final outcome = await fixture.executor.resolvePending('non', 0);

    expect(outcome?.reply, contains('seulement dans ta to-do'));
    expect(fixture.smartPlanning.active, isNull);
  });

  test('planning consent releases an independent general message', () async {
    final fixture = _planningFixture();
    fixture.smartPlanning.beginTaskPlanning(
      task: _planningTask(),
      originalMessage: 'Créer la tâche',
      sessionGeneration: 0,
    );

    final outcome = await fixture.executor.resolvePending(
      'Explique-moi comment organiser mes documents.',
      0,
    );

    expect(outcome, isNull);
    expect(fixture.smartPlanning.active, isNull);
  });
}

({
  ConversationLegacyActionExecutor executor,
  SmartPlanningContinuationCoordinator smartPlanning,
}) _planningFixture() {
  final policy = ActionAutonomyPolicy(
    mode: ActionAutonomyMode.suggestions,
    changedAt: DateTime.utc(2026, 7, 27),
    changeSource: ActionAutonomyChangeSource.explicitUserSetting,
    accountScopeId: 'synthetic-account',
  );
  final coordinator = ConversationCoordinator(
    backend: CallableChatBackendClient.withInvoker(
      (_) async => _taskClarificationJson(),
    ),
    contextProvider: _ContextProvider(_request()),
    loadAutonomyPolicy: () async => policy,
    clock: () => DateTime.utc(2026, 7, 27, 10),
  );
  final smartPlanning = SmartPlanningContinuationCoordinator(
    gateway: ProductionSmartPlanningContinuationGateway(_profile()),
    loadAutonomyPolicy: () async => policy,
    clock: () => DateTime.utc(2026, 7, 27, 10),
  );
  return (
    executor: ConversationLegacyActionExecutor(
      coordinator: coordinator,
      smartPlanning: smartPlanning,
      loadAutonomyPolicy: () async => policy,
    ),
    smartPlanning: smartPlanning,
  );
}

TaskModel _planningTask() => TaskModel(
      id: 'conversation-action-id',
      title: 'Vérifier les documents de la mutuelle',
      category: 'To-do',
      isDone: false,
      createdAt: DateTime.utc(2026, 7, 27, 10),
      dueDate: '2026-07-28',
      priority: 'Haute',
      isImportant: true,
    );

final class _ContextProvider
    implements
        ConversationContextProvider,
        PriorityConversationContextProvider {
  const _ContextProvider(this.request);

  final ChatBackendRequest request;

  @override
  Future<ChatBackendRequest> buildRequest({
    required String message,
    required UserProfile profile,
  }) async =>
      request;

  @override
  Future<void> saveResponseMemory(dynamic memory) async {}

  @override
  Future<LifeContextProjection> loadPriorityProjection() async =>
      LifeContextProjection(
        projectionId: 'priority-projection',
        sourceSnapshotId: 'priority-snapshot',
        accountScopeId: 'synthetic-account',
        purpose: LifeContextConsumerPurpose.conversation,
        generatedAt: DateTime.utc(2026, 7, 27, 10),
        state: LifeContextProjectionState.complete,
        budgetRequested: 100,
        budgetUsed: 0,
        sections: const [],
        omittedCount: 0,
        warningCodes: const [],
      );
}

final class _NoopMessageStore implements ConversationMessageStore {
  const _NoopMessageStore();

  @override
  Future<void> save({
    required String sessionId,
    required ConversationMessageRole role,
    required String text,
  }) async {}
}

ChatBackendRequest _request() => ChatBackendRequest(
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

UserProfile _profile() => UserProfile(
      firstName: 'Sophia',
      familyStatus: '',
      workStatus: '',
      partnerName: '',
      wantsNotifications: true,
      children: const [],
    );

Future<List<TaskModel>> _storedTasks() async {
  final values = (await SharedPreferences.getInstance())
      .getStringList(TaskService.tasksKey);
  return (values ?? const [])
      .map((value) => TaskModel.fromJson(jsonDecode(value)))
      .toList();
}

Map<String, dynamic> _taskClarificationJson() => {
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
        },
        'uncertaintyCodes': ['missingRequiredInformation'],
        'contextStateObserved': 'complete',
        'warningCodes': <dynamic>[],
        'responseId': 'task-clarification-0',
      },
    };
