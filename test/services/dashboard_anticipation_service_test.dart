import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/models/life_context/life_context_domains.dart';
import 'package:moms_ai/models/life_context/life_context_graph.dart';
import 'package:moms_ai/models/life_context/life_context_projection.dart';
import 'package:moms_ai/models/proactive_detection.dart';
import 'package:moms_ai/models/proactive_notification_policy.dart';
import 'package:moms_ai/models/shopping_item_model.dart';
import 'package:moms_ai/models/task_model.dart';
import 'package:moms_ai/services/daily_summary_view_service.dart';
import 'package:moms_ai/services/dashboard_anticipation_service.dart';

void main() {
  final now = DateTime.utc(2026, 8, 21, 8);

  test('a confirmed conflict is the single strongest dashboard thought',
      () async {
    final service = DashboardAnticipationService(
      loadProjection: () => throw StateError('projection not needed'),
      clock: () => now,
    );
    final result = await service.evaluate(
      accountScopeId: 'account',
      events: const [],
      tasks: const [],
      shoppingItems: const [],
      dailySummary: _summary(
        conflicts: [
          ConflictAttentionViewData(
            eventTitle: 'Dentiste',
            routineTitle: 'Pilates',
            targetDate: now,
            eventId: 'event-1',
            routineId: 'routine-1',
          ),
        ],
        tasks: [
          TaskAttentionViewData(
            taskTitle: 'Appeler la banque',
            category: ProactiveAlertCategory.deadlinePassed,
            taskId: 'task-1',
            targetDate: now,
          ),
        ],
      ),
    );

    expect(result.title, 'À regarder');
    expect(result.message, contains('Dentiste'));
    expect(result.message, contains('Pilates'));
    expect(result.destination, DashboardAnticipationDestination.agenda);
    expect(result.agendaFocus?.eventId, 'event-1');
  });

  test('a proven overdue task is named and opens that exact task', () async {
    final service = DashboardAnticipationService(
      loadProjection: () => throw StateError('projection not needed'),
      clock: () => now,
    );
    final result = await service.evaluate(
      accountScopeId: 'account',
      events: const [],
      tasks: const [],
      shoppingItems: const [],
      dailySummary: _summary(
        tasks: [
          TaskAttentionViewData(
            taskTitle: 'Préparer le dossier',
            category: ProactiveAlertCategory.deadlineApproaching,
            taskId: 'task-later',
            targetDate: now.add(const Duration(days: 1)),
          ),
          TaskAttentionViewData(
            taskTitle: 'Appeler le dentiste',
            category: ProactiveAlertCategory.objectivelyDelayed,
            taskId: 'task-overdue',
            targetDate: now.subtract(const Duration(days: 2)),
          ),
        ],
      ),
    );

    expect(result.message, contains('Appeler le dentiste'));
    expect(result.destination, DashboardAnticipationDestination.task);
    expect(result.sourceId, 'task-overdue');
  });

  test('the shared Priority engine provides the dashboard task thought',
      () async {
    final task = TaskModel(
      id: 'task-1',
      title: 'Préparer les papiers',
      category: 'Admin',
      isDone: false,
      createdAt: now.subtract(const Duration(days: 1)),
      dueDate: '2026-08-21',
      durationMinutes: 30,
      isImportant: true,
    );
    final service = DashboardAnticipationService(
      loadProjection: () async => _taskProjection(now, task.id!),
      clock: () => now,
    );
    final result = await service.evaluate(
      accountScopeId: 'account',
      events: const [],
      tasks: [task],
      shoppingItems: const [],
    );

    expect(result.destination, DashboardAnticipationDestination.task);
    expect(result.sourceId, task.id);
    expect(result.message, contains(task.title));
  });

  test('shopping stays in its own screen and never replaces home chat',
      () async {
    final urgent = ShoppingItemModel(
      id: 'shopping-1',
      title: 'Kiwis',
      isBought: false,
      isUrgent: true,
      createdAt: now,
    );
    final service = DashboardAnticipationService(
      loadProjection: () async => _emptyProjection(now),
      clock: () => now,
    );
    final result = await service.evaluate(
      accountScopeId: 'account',
      events: const <EventModel>[],
      tasks: const <TaskModel>[],
      shoppingItems: [urgent],
    );

    expect(result.destination, DashboardAnticipationDestination.chat);
    expect(result.title, 'Tu peux souffler');
    expect(result.message, isNot(contains('Kiwis')));
  });

  test('a quiet day is expressed with a short human reassurance', () async {
    final service = DashboardAnticipationService(
      loadProjection: () async => _emptyProjection(now),
      clock: () => now,
    );
    final result = await service.evaluate(
      accountScopeId: 'account',
      events: const <EventModel>[],
      tasks: const <TaskModel>[],
      shoppingItems: const <ShoppingItemModel>[],
    );

    expect(result.title, 'Tu peux souffler');
    expect(result.message, 'Rien ne presse pour le moment.');
    expect(result.destination, DashboardAnticipationDestination.chat);
  });
}

DailySummaryViewData _summary({
  List<ConflictAttentionViewData> conflicts = const [],
  List<TaskAttentionViewData> tasks = const [],
}) =>
    DailySummaryViewData(
      localDate: '2026-08-21',
      categoryCounts: const {},
      coverageState: DetectionCoverageKind.complete,
      omittedCount: 0,
      hasStaleInformation: false,
      conflicts: conflicts,
      tasks: tasks,
    );

LifeContextProjection _taskProjection(DateTime now, String taskId) {
  final item = LifeContextProjectionItem(
    id: 'task:$taskId',
    domain: LifeContextDomain.task,
    type: 'task',
    facts: [
      _fact(LifeContextProjectionFactKeys.status, 'active'),
      _fact(
        LifeContextProjectionFactKeys.dueDate,
        now.add(const Duration(hours: 2)).toIso8601String(),
      ),
      _fact(LifeContextProjectionFactKeys.durationMinutes, '30'),
      _fact(LifeContextProjectionFactKeys.urgency, '0.9'),
      _fact(LifeContextProjectionFactKeys.importance, '0.9'),
      _fact(LifeContextProjectionFactKeys.revision, '1'),
    ],
    confirmation: LifeContextConfirmation.confirmed,
    freshness: LifeContextFreshness.current,
    provenance: LifeContextProjectionProvenance(
      sourceDomain: LifeContextDomain.task,
      sourceId: taskId,
      sourceSnapshotId: 'snapshot',
      sourceKind: LifeContextSourceKind.taskService,
    ),
  );
  return _projection(now, [item]);
}

LifeContextProjection _emptyProjection(DateTime now) => _projection(now, []);

LifeContextProjection _projection(
  DateTime now,
  List<LifeContextProjectionItem> items,
) =>
    LifeContextProjection(
      projectionId: 'projection',
      sourceSnapshotId: 'snapshot',
      accountScopeId: 'account',
      purpose: LifeContextConsumerPurpose.proactivePriority,
      generatedAt: now,
      state: LifeContextProjectionState.complete,
      budgetRequested: 100,
      budgetUsed: items.fold(0, (sum, item) => sum + item.budgetCost),
      sections: [
        LifeContextProjectionSection(
          type: LifeContextProjectionSectionType.task,
          availability: LifeContextAvailability.available,
          freshness: LifeContextFreshness.current,
          items: items,
          budgetLimit: 100,
          budgetUsed: items.fold(0, (sum, item) => sum + item.budgetCost),
          omittedCount: 0,
          truncated: false,
        ),
      ],
      omittedCount: 0,
      warningCodes: const [],
    );

LifeContextProjectionFact _fact(String key, String value) =>
    LifeContextProjectionFact(
      key: key,
      value: value,
      sensitivity: LifeContextSensitivityLevel.publicTechnical,
    );
