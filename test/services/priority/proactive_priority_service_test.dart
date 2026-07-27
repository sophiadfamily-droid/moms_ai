import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/life_context/life_context_domains.dart';
import 'package:moms_ai/models/life_context/life_context_graph.dart';
import 'package:moms_ai/models/life_context/life_context_projection.dart';
import 'package:moms_ai/models/priority/proactive_priority_models.dart';
import 'package:moms_ai/models/priority/priority_suggestion_models.dart';
import 'package:moms_ai/models/task_model.dart';
import 'package:moms_ai/screens/tasks_screen.dart';
import 'package:moms_ai/services/priority/proactive_priority_service.dart';
import 'package:moms_ai/services/priority/proactive_interaction_registry.dart';
import 'package:moms_ai/services/priority/proactive_suggestion_presentation_builder.dart';
import 'package:moms_ai/services/priority/proactive_suggestion_history_repository.dart';
import 'package:moms_ai/services/task_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final now = DateTime(2026, 7, 27, 10);

  test('zero candidates and incomplete context fail closed', () async {
    final repository = _History();
    final empty = _service(repository, _projection(now, const []), now);
    expect(
      (await empty.evaluate(
        dashboardReady: true,
        interactionActive: false,
      ))
          .type,
      ProactiveSuggestionDecisionType.noSuggestion,
    );
    final partial = _service(
      repository,
      _projection(now, [_task(now, 'task-1')], complete: false),
      now,
    );
    expect(
      (await partial.evaluate(
        dashboardReady: true,
        interactionActive: false,
      ))
          .type,
      ProactiveSuggestionDecisionType.noSuggestion,
    );
  });

  test('shows only the first official suggestion and never reranks', () async {
    final repository = _History();
    final service = _service(
      repository,
      _projection(now, [
        _task(now, 'later', dueAfter: const Duration(hours: 10)),
        _task(now, 'soon', dueAfter: const Duration(hours: 1)),
      ]),
      now,
    );

    final decision = await service.evaluate(
      dashboardReady: true,
      interactionActive: false,
    );

    expect(decision.type, ProactiveSuggestionDecisionType.showSuggestion);
    expect(decision.suggestion!.priorityRank, 0);
    expect(decision.suggestion!.sourceEntityReferences, hasLength(1));
  });

  test(
      'reservation is not quota and confirmed presentation keeps its precise '
      'session reason', () async {
    final repository = _History();
    final service = _service(
      repository,
      _projection(now, [_task(now, 'task-1')]),
      now,
    );

    final reserved = await service.evaluate(
      dashboardReady: true,
      interactionActive: false,
    );
    expect(reserved.suggestion, isNotNull);
    expect(service.lastEvaluationSnapshot!.presentationReserved, isTrue);
    expect(service.lastEvaluationSnapshot!.sessionQuotaConsumed, isFalse);

    final whileReserved = await service.evaluate(
      dashboardReady: true,
      interactionActive: false,
    );
    expect(whileReserved.code, 'presentation_reserved');
    expect(service.lastEvaluationSnapshot!.sessionQuotaConsumed, isFalse);

    expect(await service.confirmShown(reserved.suggestion!), isTrue);
    expect(service.lastEvaluationSnapshot!.presentationConfirmed, isTrue);
    expect(service.lastEvaluationSnapshot!.historyState, 'shown');
    expect(service.lastEvaluationSnapshot!.sessionQuotaConsumed, isTrue);

    final afterRender = await service.evaluate(
      dashboardReady: true,
      interactionActive: false,
    );
    expect(afterRender.code, 'session_quota_consumed');
    expect(service.currentVisibleSuggestion, same(reserved.suggestion));
    expect(
      service.currentVisibleFingerprint,
      reserved.suggestion!.materialFingerprint,
    );
    expect(service.presentationConfirmed, isTrue);
    expect(service.lastEvaluationSnapshot!.historyState, 'shown');
    expect(service.lastEvaluationSnapshot!.presentationConfirmed, isTrue);
    expect(
      service.lastEvaluationSnapshot!.evaluationDecision,
      'session_quota_consumed',
    );
    expect(
      service.lastEvaluationSnapshot!.renderedState,
      'existing_suggestion_preserved',
    );
    expect(
      service.lastEvaluationSnapshot!.visibleSuggestionPresent,
      isTrue,
    );
  });

  test('confirming the same rendered suggestion twice is idempotent', () async {
    final repository = _History();
    final service = _service(
      repository,
      _projection(now, [_task(now, 'task-1')]),
      now,
    );
    final reserved = await service.evaluate(
      dashboardReady: true,
      interactionActive: false,
    );

    expect(await service.confirmShown(reserved.suggestion!), isTrue);
    expect(await service.confirmShown(reserved.suggestion!), isTrue);

    expect(repository.saveCalls, 1);
    expect(repository.values, hasLength(1));
    expect(service.currentVisibleSuggestion, same(reserved.suggestion));
  });

  test('session, civil day, dismissal and restart are deduplicated', () async {
    final repository = _History();
    final projection = _projection(now, [_task(now, 'task-1')]);
    final first = _service(repository, projection, now);
    final shown = await first.evaluate(
      dashboardReady: true,
      interactionActive: false,
    );
    expect(shown.suggestion, isNotNull);
    expect(await first.confirmShown(shown.suggestion!), isTrue);
    expect(
      (await first.evaluate(
        dashboardReady: true,
        interactionActive: false,
      ))
          .suggestion,
      isNull,
    );

    final restarted = _service(repository, projection, now);
    expect(
      (await restarted.evaluate(
        dashboardReady: true,
        interactionActive: false,
      ))
          .suggestion,
      isNull,
    );
    await first.dismiss(shown.suggestion!);
    final afterDismiss = _service(repository, projection, now);
    expect(
      (await afterDismiss.evaluate(
        dashboardReady: true,
        interactionActive: false,
      ))
          .suggestion,
      isNull,
    );
  });

  test('material revision change allows a new suggestion', () async {
    final repository = _History();
    final first = _service(
      repository,
      _projection(now, [_task(now, 'task-1', revision: 1)]),
      now,
    );
    final shown = await first.evaluate(
      dashboardReady: true,
      interactionActive: false,
    );
    expect(shown.suggestion, isNotNull);
    expect(await first.confirmShown(shown.suggestion!), isTrue);
    final changed = _service(
      repository,
      _projection(now, [_task(now, 'task-1', revision: 2)]),
      now,
    );
    expect(
      (await changed.evaluate(
        dashboardReady: true,
        interactionActive: false,
      ))
          .suggestion,
      isNotNull,
    );
  });

  test(
      'material change retires the visible suggestion before selecting '
      'the replacement', () async {
    final repository = _History();
    var projection = _projection(now, [_task(now, 'task-1', revision: 1)]);
    final service = ProactivePriorityService(
      accountScopeId: 'account',
      loadProjection: () async => projection,
      history: repository,
      clock: () => now,
    );
    final first = await service.evaluate(
      dashboardReady: true,
      interactionActive: false,
    );
    expect(await service.confirmShown(first.suggestion!), isTrue);

    projection = _projection(now, [_task(now, 'task-1', revision: 2)]);
    final replacement = await service.evaluate(
      dashboardReady: true,
      interactionActive: false,
    );

    expect(replacement.type, ProactiveSuggestionDecisionType.showSuggestion);
    expect(
      replacement.suggestion!.materialFingerprint,
      isNot(first.suggestion!.materialFingerprint),
    );
    expect(service.currentVisibleSuggestion, isNull);
    expect(service.lastEvaluationSnapshot!.sessionQuotaConsumed, isFalse);
  });

  test('completed presentation is removed and cannot be preserved', () async {
    final repository = _History();
    final service = _service(
      repository,
      _projection(now, [_task(now, 'task-1')]),
      now,
    );
    final decision = await service.evaluate(
      dashboardReady: true,
      interactionActive: false,
    );
    expect(await service.confirmShown(decision.suggestion!), isTrue);

    await service.markCompleted(decision.suggestion!);

    expect(service.currentVisibleSuggestion, isNull);
    expect(repository.values.single.state,
        ProactiveSuggestionHistoryState.completed);
  });

  test('missing duration presentation names the task and explains the CTA', () {
    final presentation = const ProactiveSuggestionPresentationBuilder().build(
      suggestion: _proactiveMissingDuration(now),
      sourceLabel: 'Préparer les documents pour la banque',
    );

    expect(presentation.title, 'Durée à préciser');
    expect(
      presentation.message,
      'Il manque la durée de “Préparer les documents pour la banque”. '
      'Ajoute une durée pour que je puisse vérifier si cette tâche est '
      'réalisable avant son échéance.',
    );
    expect(presentation.callToActionLabel, 'Ajouter une durée');
    expect(
      presentation.assistantPrompt,
      'Combien de temps veux-tu prévoir pour '
      '“Préparer les documents pour la banque” ?',
    );
  });

  test(
      'sixteen ordered candidates skip two shown and one completed '
      'and select rank four after restart', () async {
    final repository = _History();
    final projection = _projection(
      now,
      List.generate(
        16,
        (index) => _task(
          now,
          'rank-${index + 1}',
          dueAfter: Duration(minutes: 30 * (index + 1)),
        ),
      ),
    );

    final qaSession = _service(repository, projection, now);
    final first = await qaSession.evaluate(
      dashboardReady: true,
      interactionActive: false,
    );
    expect(first.suggestion!.priorityRank, 0);
    expect(await qaSession.confirmShown(first.suggestion!), isTrue);

    final secondSession = _service(repository, projection, now);
    final second = await secondSession.evaluate(
      dashboardReady: true,
      interactionActive: false,
    );
    expect(second.suggestion!.priorityRank, 1);
    expect(second.skippedShownCount, 1);
    expect(await secondSession.confirmShown(second.suggestion!), isTrue);

    final completionSession = _service(repository, projection, now);
    final third = await completionSession.evaluate(
      dashboardReady: true,
      interactionActive: false,
    );
    expect(third.suggestion!.priorityRank, 2);
    expect(await completionSession.confirmShown(third.suggestion!), isTrue);
    repository.values = [
      ...repository.values.take(2),
      ProactiveSuggestionReceipt(
        suggestionId: repository.values[2].suggestionId,
        canonicalSuggestionKey: repository.values[2].canonicalSuggestionKey,
        materialFingerprint: repository.values[2].materialFingerprint,
        firstShownAt: repository.values[2].firstShownAt,
        lastShownAt: repository.values[2].lastShownAt,
        completedAt: now,
        state: ProactiveSuggestionHistoryState.completed,
        sourceRevision: repository.values[2].sourceRevision,
      ),
    ];

    final normalRestart = _service(repository, projection, now);
    final fourth = await normalRestart.evaluate(
      dashboardReady: true,
      interactionActive: false,
    );

    expect(fourth.type, ProactiveSuggestionDecisionType.showSuggestion);
    expect(fourth.suggestion!.priorityRank, 3);
    expect(fourth.inputSuggestionCount, 16);
    expect(fourth.evaluatedCandidateCount, 4);
    expect(fourth.skippedShownCount, 2);
    expect(fourth.skippedCompletedCount, 1);
    expect(fourth.selectedCandidateRank, 4);
    expect(fourth.code, 'suggestion_selected');
    expect(repository.values, hasLength(3));

    expect(await normalRestart.confirmShown(fourth.suggestion!), isTrue);
    await normalRestart.dismiss(fourth.suggestion!);
    final fifth = await _service(repository, projection, now).evaluate(
      dashboardReady: true,
      interactionActive: false,
    );
    expect(fifth.selectedCandidateRank, 5);
    expect(fifth.skippedShownCount, 2);
    expect(fifth.skippedCompletedCount, 1);
    expect(fifth.skippedDismissedCount, 1);
  });

  test('all official suggestions deduplicated returns a precise terminal code',
      () async {
    final repository = _History();
    final projection = _projection(now, [
      _task(now, 'rank-1'),
      _task(now, 'rank-2', dueAfter: const Duration(hours: 2)),
      _task(now, 'rank-3', dueAfter: const Duration(hours: 3)),
    ]);
    for (var index = 0; index < 3; index++) {
      final session = _service(repository, projection, now);
      final decision = await session.evaluate(
        dashboardReady: true,
        interactionActive: false,
      );
      expect(decision.suggestion, isNotNull);
      expect(await session.confirmShown(decision.suggestion!), isTrue);
    }

    final restarted = _service(repository, projection, now);
    final terminal = await restarted.evaluate(
      dashboardReady: true,
      interactionActive: false,
    );

    expect(terminal.code, 'all_candidates_deduplicated');
    expect(terminal.inputSuggestionCount, 3);
    expect(terminal.evaluatedCandidateCount, 3);
    expect(terminal.skippedShownCount, 3);
    expect(terminal.suggestion, isNull);
  });

  test('proactive evaluation window is bounded and reports exhaustion',
      () async {
    final repository = _History();
    final projection = _projection(
      now,
      List.generate(
        21,
        (index) => _task(
          now,
          'bounded-${index + 1}',
          dueAfter: Duration(minutes: 20 * (index + 1)),
        ),
      ),
    );
    for (var index = 0;
        index < PrioritySuggestionLimits.proactiveEvaluation;
        index++) {
      final session = _service(repository, projection, now);
      final decision = await session.evaluate(
        dashboardReady: true,
        interactionActive: false,
      );
      expect(decision.suggestion, isNotNull);
      expect(await session.confirmShown(decision.suggestion!), isTrue);
    }

    final terminal = await _service(repository, projection, now).evaluate(
      dashboardReady: true,
      interactionActive: false,
    );

    expect(terminal.inputSuggestionCount,
        PrioritySuggestionLimits.proactiveEvaluation);
    expect(terminal.evaluatedCandidateCount,
        PrioritySuggestionLimits.proactiveEvaluation);
    expect(terminal.code, 'candidate_window_exhausted');
    expect(terminal.suggestion, isNull);
  });

  test('active conversation or Smart Planning blocks presentation', () async {
    final service = _service(
      _History(),
      _projection(now, [_task(now, 'task-1')]),
      now,
    );
    expect(
      (await service.evaluate(
        dashboardReady: true,
        interactionActive: true,
      ))
          .suggestion,
      isNull,
    );
  });

  test(
      'closing Smart Planning reevaluates the latest canonical projection '
      'without consuming noSuggestion', () async {
    final repository = _History();
    var projection = _projection(now, const []);
    var projectionLoads = 0;
    final service = ProactivePriorityService(
      accountScopeId: 'account',
      loadProjection: () async {
        projectionLoads++;
        return projection;
      },
      history: repository,
      clock: () => now,
    );

    projection = _projection(
      now,
      [_task(now, 'new-task', dueAfter: const Duration(hours: 14))],
    );
    final blocked = await service.evaluate(
      dashboardReady: true,
      interactionActive: true,
    );

    expect(blocked.code, 'active_continuation');
    expect(repository.values, isEmpty);
    expect(repository.saveCalls, 0);

    final afterNo = await service.evaluate(
      dashboardReady: true,
      interactionActive: false,
    );

    expect(projectionLoads, 2);
    expect(afterNo.type, ProactiveSuggestionDecisionType.showSuggestion);
    expect(afterNo.suggestion!.sourceEntityReferences, hasLength(1));
    expect(repository.values, isEmpty);
    expect(await service.confirmShown(afterNo.suggestion!), isTrue);
    expect(repository.values, hasLength(1));
    expect(
        repository.values.single.state, ProactiveSuggestionHistoryState.shown);

    final refresh = await service.evaluate(
      dashboardReady: true,
      interactionActive: false,
    );
    expect(refresh.type, ProactiveSuggestionDecisionType.noSuggestion);
    expect(repository.values, hasLength(1));
  });

  test('interaction registry notifies only real active-state transitions', () {
    final registry = ProactiveInteractionRegistry();
    var notifications = 0;
    void listener() => notifications++;
    registry.addListener(listener);
    addTearDown(() {
      registry.deactivateOwner('registry-account', ownerId: 'test');
      registry.removeListener(listener);
    });

    registry.activate(
      'registry-account',
      ownerId: 'test',
      source: ProactiveInteractionSource.smartPlanningConsent,
    );
    registry.activate(
      'registry-account',
      ownerId: 'test',
      source: ProactiveInteractionSource.smartPlanningConsent,
    );
    registry.deactivate(
      'registry-account',
      ownerId: 'test',
      source: ProactiveInteractionSource.smartPlanningConsent,
    );

    expect(notifications, 2);
  });

  test('interaction owners release independently and transitions are typed',
      () {
    final registry = ProactiveInteractionRegistry();
    registry.activate(
      'account',
      ownerId: 'chat',
      source: ProactiveInteractionSource.smartPlanningConsent,
    );
    registry.activate(
      'account',
      ownerId: 'event-flow',
      source: ProactiveInteractionSource.eventConfirmation,
    );

    registry.deactivateOwner('account', ownerId: 'chat');

    expect(registry.isActive('account'), isTrue);
    expect(
      registry.activeSources('account'),
      {ProactiveInteractionSource.eventConfirmation},
    );
    expect(registry.snapshot('account').generation, 3);

    registry.deactivateOwner('account', ownerId: 'event-flow');
    expect(registry.isActive('account'), isFalse);
  });

  testWidgets('active Dashboard reevaluates once when Smart Planning closes',
      (tester) async {
    _seedTask('dashboard-task', 'Préparer les documents pour la banque', now);
    final history = _History();
    final registry = ProactiveInteractionRegistry();
    final service = _service(
      history,
      _projection(
        now,
        [_task(now, 'dashboard-task', dueAfter: const Duration(hours: 14))],
      ),
      now,
    );
    registry.activate(
      'account',
      ownerId: 'conversation',
      source: ProactiveInteractionSource.smartPlanningConsent,
    );
    addTearDown(
      () => registry.deactivateOwner('account', ownerId: 'conversation'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TasksScreen(
          proactivePriorityService: service,
          proactiveInteractionRegistry: registry,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Rien de prioritaire à suggérer pour le moment.'),
      findsOneWidget,
    );
    expect(history.values, isEmpty);

    registry.deactivate(
      'account',
      ownerId: 'conversation',
      source: ProactiveInteractionSource.smartPlanningConsent,
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Rien de prioritaire à suggérer pour le moment.'),
      findsNothing,
    );
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(history.values, hasLength(1));

    TaskService.notifyTasksChanged();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(service.lastEvaluationSnapshot!.reasonCodes,
        const ['session_quota_consumed']);
    expect(service.lastEvaluationSnapshot!.historyState, 'shown');
    expect(service.lastEvaluationSnapshot!.presentationConfirmed, isTrue);
    expect(service.lastEvaluationSnapshot!.sessionQuotaConsumed, isTrue);
    expect(
      service.lastEvaluationSnapshot!.evaluationDecision,
      'session_quota_consumed',
    );
    expect(
      service.lastEvaluationSnapshot!.renderedState,
      'existing_suggestion_preserved',
    );
    expect(
      service.lastEvaluationSnapshot!.visibleSuggestionPresent,
      isTrue,
    );
    expect(history.values, hasLength(1));
    expect(history.saveCalls, 1);
  });

  testWidgets(
      'missing duration card stays complete at large text and CTA only opens '
      'the official task completion sheet', (tester) async {
    const longTitle =
        'Préparer les documents administratifs pour le rendez-vous bancaire';
    _seedTask('duration-task', longTitle, now);
    final history = _History();
    final service = _service(
      history,
      _projection(
        now,
        [_task(now, 'duration-task', includeDuration: false)],
      ),
      now,
    );
    ProactiveTaskDurationHandoff? openedHandoff;

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.6),
          ),
          child: child!,
        ),
        home: TasksScreen(
          proactivePriorityService: service,
          onOpenZeliaSuggestion: (value) => openedHandoff = value,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Durée à préciser'), findsOneWidget);
    final expectedMessage = 'Il manque la durée de “$longTitle”. '
        'Ajoute une durée pour que je puisse vérifier si cette tâche est '
        'réalisable avant son échéance.';
    expect(find.text(expectedMessage), findsOneWidget);
    expect(find.text('Ajouter une durée'), findsOneWidget);
    final message = tester.widget<Text>(find.text(expectedMessage));
    expect(message.maxLines, isNull);
    expect(message.overflow, isNull);

    await tester.ensureVisible(find.text('Ajouter une durée'));
    await tester.tap(find.text('Ajouter une durée'));
    await tester.pumpAndSettle();

    expect(find.text('Modifier la tâche'), findsNothing);
    expect(
      openedHandoff?.question,
      'Combien de temps veux-tu prévoir pour “$longTitle” ?',
    );
    expect(openedHandoff?.taskId, 'duration-task');
    expect(openedHandoff?.sourceSuggestionId, isNotEmpty);
    final stored = (await SharedPreferences.getInstance())
        .getStringList(TaskService.tasksKey)!;
    expect(stored, hasLength(1));
    expect(TaskModel.fromJson(jsonDecode(stored.single)).title, longTitle);
  });

  testWidgets(
      'transition missed offscreen is reevaluated from current state '
      'on tab activation', (tester) async {
    _seedTask('offscreen-task', 'Une tâche au titre suffisamment long', now);
    final history = _History();
    final registry = ProactiveInteractionRegistry()
      ..activate(
        'account',
        ownerId: 'conversation',
        source: ProactiveInteractionSource.smartPlanningConsent,
      );
    final service = _service(
      history,
      _projection(
        now,
        [_task(now, 'offscreen-task', dueAfter: const Duration(hours: 14))],
      ),
      now,
    );

    Widget screen(bool active) => MaterialApp(
          home: TasksScreen(
            key: const ValueKey('tasks-dashboard'),
            isDashboardActive: active,
            proactivePriorityService: service,
            proactiveInteractionRegistry: registry,
          ),
        );

    await tester.pumpWidget(screen(false));
    await tester.pumpAndSettle();
    expect(history.values, isEmpty);

    registry.deactivate(
      'account',
      ownerId: 'conversation',
      source: ProactiveInteractionSource.smartPlanningConsent,
    );
    await tester.pump();
    expect(history.values, isEmpty);

    await tester.pumpWidget(screen(true));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(history.values, hasLength(1));
  });

  test('history persistence failure is fail-closed for the session', () async {
    final history = _History()..failSave = true;
    final service = _service(
      history,
      _projection(now, [_task(now, 'task-1')]),
      now,
    );
    final first = await service.evaluate(
      dashboardReady: true,
      interactionActive: false,
    );
    expect(first.suggestion, isNotNull);
    expect(await service.confirmShown(first.suggestion!), isFalse);
    final second = await service.evaluate(
      dashboardReady: true,
      interactionActive: false,
    );

    expect(second.suggestion, isNull);
    expect(second.code, 'history_persistence_blocked');
    expect(service.lastEvaluationSnapshot!.sessionQuotaConsumed, isFalse);
  });

  test('account-scoped history survives a repository restart', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final first = SharedPreferencesProactiveSuggestionHistoryRepository(
      preferences,
    );
    final receipt = ProactiveSuggestionReceipt(
      suggestionId: 'suggestion',
      canonicalSuggestionKey: 'canonical',
      materialFingerprint: 'material',
      firstShownAt: now,
      lastShownAt: now,
      state: ProactiveSuggestionHistoryState.dismissed,
      sourceRevision: '1:1',
      dismissedAt: now,
    );
    await first.save('account', [receipt]);

    final restarted = SharedPreferencesProactiveSuggestionHistoryRepository(
      await SharedPreferences.getInstance(),
    );
    final restored = await restarted.load('account');

    expect(restored, hasLength(1));
    expect(restored.single.materialFingerprint, 'material');
    expect(restored.single.state, ProactiveSuggestionHistoryState.dismissed);
    expect(await restarted.load('other-account'), isEmpty);
  });
}

ProactivePriorityService _service(
  _History history,
  LifeContextProjection projection,
  DateTime now,
) =>
    ProactivePriorityService(
      accountScopeId: 'account',
      loadProjection: () async => projection,
      history: history,
      clock: () => now,
    );

LifeContextProjection _projection(
  DateTime now,
  List<LifeContextProjectionItem> items, {
  bool complete = true,
}) =>
    LifeContextProjection(
      projectionId: 'projection',
      sourceSnapshotId: 'snapshot',
      accountScopeId: 'account',
      purpose: LifeContextConsumerPurpose.conversation,
      generatedAt: now.toUtc(),
      state: complete
          ? LifeContextProjectionState.complete
          : LifeContextProjectionState.partial,
      budgetRequested: items.fold(0, (sum, item) => sum + item.budgetCost) > 100
          ? items.fold(0, (sum, item) => sum + item.budgetCost)
          : 100,
      budgetUsed: items.fold(0, (sum, item) => sum + item.budgetCost),
      sections: [
        LifeContextProjectionSection(
          type: LifeContextProjectionSectionType.task,
          availability: LifeContextAvailability.available,
          freshness: LifeContextFreshness.current,
          items: items,
          budgetLimit: items.fold(0, (sum, item) => sum + item.budgetCost) > 100
              ? items.fold(0, (sum, item) => sum + item.budgetCost)
              : 100,
          budgetUsed: items.fold(0, (sum, item) => sum + item.budgetCost),
          omittedCount: 0,
          truncated: false,
        ),
      ],
      omittedCount: 0,
      warningCodes: const [],
    );

LifeContextProjectionItem _task(
  DateTime now,
  String id, {
  Duration dueAfter = const Duration(hours: 1),
  int revision = 1,
  bool includeDuration = true,
}) =>
    LifeContextProjectionItem(
      id: 'task:$id',
      domain: LifeContextDomain.task,
      type: 'task',
      facts: [
        _fact(LifeContextProjectionFactKeys.status, 'active'),
        _fact(
          LifeContextProjectionFactKeys.dueDate,
          now.add(dueAfter).toUtc().toIso8601String(),
        ),
        _fact(LifeContextProjectionFactKeys.urgency, '0.9'),
        if (includeDuration)
          _fact(LifeContextProjectionFactKeys.durationMinutes, '30'),
        _fact(LifeContextProjectionFactKeys.revision, '$revision'),
      ],
      confirmation: LifeContextConfirmation.confirmed,
      freshness: LifeContextFreshness.current,
      provenance: LifeContextProjectionProvenance(
        sourceDomain: LifeContextDomain.task,
        sourceId: id,
        sourceSnapshotId: 'snapshot',
        sourceKind: LifeContextSourceKind.taskService,
      ),
    );

ProactiveSuggestion _proactiveMissingDuration(DateTime now) =>
    ProactiveSuggestion(
      suggestionId: 'suggestion',
      canonicalSuggestionKey: 'canonical',
      materialFingerprint: 'fingerprint',
      suggestionType: PrioritySuggestionType.clarifyMissingInformation,
      message: 'generic',
      reasonCodes: const [
        PrioritySuggestionReason.missingDurationBlocksAssessment,
      ],
      sourceEntityReferences: const ['priority:task:task-1'],
      generatedAt: now,
      expiresAt: now.add(const Duration(days: 1)),
      validityState: ProactiveSuggestionValidityState.valid,
      callToAction: ProactiveSuggestionCallToActionType.completeInformation,
      requiresConfirmation: true,
      priorityRank: 0,
      sourceRevision: '1:1',
    );

void _seedTask(String id, String title, DateTime now) {
  final task = TaskModel(
    id: id,
    title: title,
    category: 'To-do',
    isDone: false,
    createdAt: now,
    dueDate: now.add(const Duration(days: 1)).toIso8601String(),
    priority: 'Haute',
    isImportant: true,
  );
  SharedPreferences.setMockInitialValues({
    TaskService.tasksKey: [jsonEncode(task.toJson())],
  });
}

LifeContextProjectionFact _fact(String key, String value) =>
    LifeContextProjectionFact(
      key: key,
      value: value,
      sensitivity: LifeContextSensitivityLevel.publicTechnical,
    );

final class _History implements ProactiveSuggestionHistoryRepository {
  List<ProactiveSuggestionReceipt> values = [];
  bool failSave = false;
  int saveCalls = 0;

  @override
  Future<List<ProactiveSuggestionReceipt>> load(String accountScopeId) async =>
      List.unmodifiable(values);

  @override
  Future<void> save(
    String accountScopeId,
    List<ProactiveSuggestionReceipt> receipts,
  ) async {
    saveCalls++;
    if (failSave) throw StateError('synthetic_history_failure');
    values = List.of(receipts);
  }
}
