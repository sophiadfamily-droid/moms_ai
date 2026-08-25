import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/life_context/life_context_domains.dart';
import 'package:moms_ai/models/life_context/life_context_graph.dart';
import 'package:moms_ai/models/life_context/life_context_projection.dart';
import 'package:moms_ai/models/mental_load_anticipation.dart';
import 'package:moms_ai/models/proactive_detection.dart';
import 'package:moms_ai/models/proactive_notification_policy.dart';
import 'package:moms_ai/models/task_model.dart';
import 'package:moms_ai/services/daily_summary_view_service.dart';
import 'package:moms_ai/services/dashboard_anticipation_service.dart';
import 'package:moms_ai/services/mental_load_anticipation_suggestion_service.dart';

void main() {
  final now = DateTime.utc(2026, 8, 21, 8);

  test('a confirmed conflict is the single strongest dashboard thought',
      () async {
    final service = DashboardAnticipationService(
      loadMentalLoadAnticipations: () =>
          throw StateError('anticipation not needed'),
    );
    final result = await service.evaluate(
      accountScopeId: 'account',
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

  test('a standalone overdue task stays on the Tasks screen', () async {
    final service = DashboardAnticipationService(
      loadMentalLoadAnticipations: () async => const [],
    );
    final result = await service.evaluate(
      accountScopeId: 'account',
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

    expect(result.title, 'Tu peux souffler');
    expect(result.message, isNot(contains('Appeler le dentiste')));
    expect(result.destination, DashboardAnticipationDestination.chat);
  });

  test('a proven Task preparation linked to an Event reaches the dashboard',
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
      loadMentalLoadAnticipations: () async => [
        _mentalLoadSuggestion(
          now,
          taskId: task.id!,
          taskTitle: task.title,
        ),
      ],
    );
    final result = await service.evaluate(
      accountScopeId: 'account',
    );

    expect(result.destination, DashboardAnticipationDestination.task);
    expect(result.sourceId, task.id);
    expect(result.message, contains(task.title));
    expect(result.message, contains('Inscription à l’école'));
  });

  test('a quiet day is expressed with a short human reassurance', () async {
    final service = DashboardAnticipationService(
      loadMentalLoadAnticipations: () async => const [],
    );
    final result = await service.evaluate(
      accountScopeId: 'account',
    );

    expect(result.title, 'Tu peux souffler');
    expect(result.message, 'Rien ne presse pour le moment.');
    expect(result.destination, DashboardAnticipationDestination.chat);
  });

  test('another account anticipation can never reach the dashboard', () async {
    final service = DashboardAnticipationService(
      loadMentalLoadAnticipations: () async => [
        _mentalLoadSuggestion(
          now,
          taskId: 'task-other',
          taskTitle: 'Préparer le dossier privé',
          accountScopeId: 'other-account',
        ),
      ],
    );
    final result = await service.evaluate(accountScopeId: 'account');

    expect(result.title, 'Tu peux souffler');
    expect(result.message, isNot(contains('dossier privé')));
  });

  test('a temporary cross-domain failure keeps the home calm', () async {
    final service = DashboardAnticipationService(
      loadMentalLoadAnticipations: () => Future.error(StateError('offline')),
    );
    final result = await service.evaluate(
      accountScopeId: 'account',
    );

    expect(result.title, 'Tu peux souffler');
    expect(result.destination, DashboardAnticipationDestination.chat);
  });

  test('a major trip can be anticipated sixty days ahead', () async {
    final projection = _projection(
      now,
      events: [
        _item(
          id: 'event-trip',
          domain: LifeContextDomain.event,
          type: 'event',
          sourceKind: LifeContextSourceKind.eventService,
          facts: {
            LifeContextProjectionFactKeys.title: 'Voyage à Lisbonne',
            LifeContextProjectionFactKeys.start:
                now.add(const Duration(days: 60)).toIso8601String(),
          },
        ),
      ],
      tasks: [
        _item(
          id: 'task-passport',
          domain: LifeContextDomain.task,
          type: 'task',
          sourceKind: LifeContextSourceKind.taskService,
          facts: const {
            LifeContextProjectionFactKeys.title: 'Préparer le voyage',
          },
        ),
      ],
    );
    final service = DashboardAnticipationService(
      loadMentalLoadAnticipations: () async => const [],
      loadLifeContext: () async => projection,
    );

    final result = await service.evaluate(accountScopeId: 'account');

    expect(result.message, contains('Voyage à Lisbonne'));
    expect(result.preparedChatMessage, contains('Voyage à Lisbonne'));
    expect(result.preparedChatMessage, contains('tes tâches'));
    expect(result.destination, DashboardAnticipationDestination.chat);
  });

  test('an ordinary appointment forty days away does not take over home',
      () async {
    final projection = _projection(
      now,
      events: [
        _item(
          id: 'event-dentist',
          domain: LifeContextDomain.event,
          type: 'event',
          sourceKind: LifeContextSourceKind.eventService,
          facts: {
            LifeContextProjectionFactKeys.title: 'Dentiste',
            LifeContextProjectionFactKeys.start:
                now.add(const Duration(days: 40)).toIso8601String(),
          },
        ),
      ],
    );
    final service = DashboardAnticipationService(
      loadMentalLoadAnticipations: () async => const [],
      loadLifeContext: () async => projection,
    );

    final result = await service.evaluate(accountScopeId: 'account');

    expect(result.message, isNot(contains('On anticipe')));
    expect(result.message, contains('Rien de nouveau à préparer'));
  });

  test('a related person birthday prepares a personal chat', () async {
    final projection = _projection(
      now,
      people: [
        _item(
          id: 'person-primary',
          domain: LifeContextDomain.human,
          type: 'person',
          sourceKind: LifeContextSourceKind.humanModelLocal,
          facts: const {
            LifeContextProjectionFactKeys.personRole: 'primary',
            LifeContextProjectionFactKeys.displayName: 'Sophia',
          },
        ),
        _item(
          id: 'person-kassim',
          domain: LifeContextDomain.human,
          type: 'person',
          sourceKind: LifeContextSourceKind.humanModelLocal,
          facts: const {
            LifeContextProjectionFactKeys.personRole: 'related',
            LifeContextProjectionFactKeys.displayName: 'Kassim',
            LifeContextProjectionFactKeys.birthDate: '2022-10-10',
          },
        ),
      ],
    );
    final service = DashboardAnticipationService(
      loadMentalLoadAnticipations: () async => const [],
      loadLifeContext: () async => projection,
    );

    final result = await service.evaluate(accountScopeId: 'account');

    expect(result.message, contains('Kassim'));
    expect(result.preparedChatMessage, contains('anticiper les préparatifs'));
    expect(result.preparedChatMessage, isNot(contains('Tu préfères')));
    expect(result.preparedChatMessage, isNot(contains('plus tard')));
    expect(
        result.preparedChatMessage, isNot(contains('ne te le repropose pas')));
  });

  test('a calm card uses the verified first name', () async {
    final service = DashboardAnticipationService(
      loadMentalLoadAnticipations: () async => const [],
      loadLifeContext: () async => _projection(
        now,
        people: [
          _item(
            id: 'person-primary',
            domain: LifeContextDomain.human,
            type: 'person',
            sourceKind: LifeContextSourceKind.humanModelLocal,
            facts: const {
              LifeContextProjectionFactKeys.personRole: 'primary',
              LifeContextProjectionFactKeys.displayName: 'Sophia',
            },
          ),
        ],
      ),
    );

    final result = await service.evaluate(accountScopeId: 'account');

    expect(result.title, 'Tu peux souffler, Sophia');
    expect(result.message, 'Rien ne presse pour le moment.');
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

MentalLoadAnticipationSuggestion _mentalLoadSuggestion(
  DateTime now, {
  required String taskId,
  required String taskTitle,
  String accountScopeId = 'account',
}) =>
    MentalLoadAnticipationSuggestion(
      anticipation: MentalLoadAnticipation(
        id: 'mental-load:task-event',
        accountScopeId: accountScopeId,
        reason: MentalLoadAnticipationReason.explicitPreparationBeforeEvent,
        priority: MentalLoadAnticipationPriority.urgent,
        preparationSourceId: taskId,
        eventSourceId: 'event-1',
        preparationDeadline: now.add(const Duration(hours: 6)),
        eventStart: now.add(const Duration(days: 1)),
        evidence: [
          DetectionEvidence(
            sourceType: DetectionEvidenceSource.explicitDeadline,
            domain: LifeContextDomain.task,
            sourceId: taskId,
            revision: 1,
            freshness: LifeContextFreshness.current,
            availability: LifeContextAvailability.available,
            certainty: DetectionEvidenceLevel.explicit,
            instant: now.add(const Duration(hours: 6)),
            confirmed: true,
          ),
        ],
      ),
      preparationLabel: taskTitle,
      eventLabel: 'Inscription à l’école',
    );

LifeContextProjection _projection(
  DateTime now, {
  List<LifeContextProjectionItem> people = const [],
  List<LifeContextProjectionItem> events = const [],
  List<LifeContextProjectionItem> tasks = const [],
}) {
  final sections = <LifeContextProjectionSection>[
    if (people.isNotEmpty)
      _section(LifeContextProjectionSectionType.human, people),
    if (events.isNotEmpty)
      _section(LifeContextProjectionSectionType.event, events),
    if (tasks.isNotEmpty)
      _section(LifeContextProjectionSectionType.task, tasks),
  ];
  if (sections.isEmpty) {
    sections.add(_section(LifeContextProjectionSectionType.human, const []));
  }
  return LifeContextProjection(
    projectionId: 'projection-dashboard',
    sourceSnapshotId: 'snapshot-dashboard',
    accountScopeId: 'account',
    purpose: LifeContextConsumerPurpose.dashboardAnticipation,
    generatedAt: now,
    state: LifeContextProjectionState.complete,
    budgetRequested: 900,
    budgetUsed: sections.fold(0, (sum, section) => sum + section.budgetUsed),
    sections: sections,
    omittedCount: 0,
    warningCodes: const [],
  );
}

LifeContextProjectionSection _section(
  LifeContextProjectionSectionType type,
  List<LifeContextProjectionItem> items,
) =>
    LifeContextProjectionSection(
      type: type,
      availability: items.isEmpty
          ? LifeContextAvailability.empty
          : LifeContextAvailability.available,
      freshness: LifeContextFreshness.current,
      items: items,
      budgetLimit: 220,
      budgetUsed: items.fold(0, (sum, item) => sum + item.budgetCost),
      omittedCount: 0,
      truncated: false,
      accountScopeMatch: true,
    );

LifeContextProjectionItem _item({
  required String id,
  required LifeContextDomain domain,
  required String type,
  required LifeContextSourceKind sourceKind,
  required Map<String, String> facts,
}) =>
    LifeContextProjectionItem(
      id: id,
      domain: domain,
      type: type,
      facts: facts.entries
          .map(
            (entry) => LifeContextProjectionFact(
              key: entry.key,
              value: entry.value,
              sensitivity: {
                LifeContextProjectionFactKeys.displayName,
                LifeContextProjectionFactKeys.title,
              }.contains(entry.key)
                  ? LifeContextSensitivityLevel.ordinaryPersonal
                  : entry.key == LifeContextProjectionFactKeys.birthDate
                      ? LifeContextSensitivityLevel.privatePersonal
                      : LifeContextSensitivityLevel.publicTechnical,
            ),
          )
          .toList(),
      confirmation: LifeContextConfirmation.confirmed,
      freshness: LifeContextFreshness.current,
      provenance: LifeContextProjectionProvenance(
        sourceDomain: domain,
        sourceId: id,
        sourceSnapshotId: 'snapshot-dashboard',
        sourceKind: sourceKind,
      ),
    );
