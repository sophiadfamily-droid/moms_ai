import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/models/action_autonomy_policy.dart';
import 'package:moms_ai/models/smart_planning_continuation.dart';
import 'package:moms_ai/models/task_model.dart';
import 'package:moms_ai/services/planning_proposal_engine.dart';
import 'package:moms_ai/services/selected_slot_revalidation_service.dart';
import 'package:moms_ai/services/smart_planning_continuation_coordinator.dart';
import 'package:moms_ai/services/smart_planning_service.dart';

void main() {
  late DateTime now;
  late _FakeGateway gateway;
  late SmartPlanningContinuationCoordinator coordinator;
  var id = 0;

  setUp(() {
    now = DateTime.utc(2026, 7, 23, 8);
    gateway = _FakeGateway();
    coordinator = SmartPlanningContinuationCoordinator(
      gateway: gateway,
      clock: () => now,
      idGenerator: () => 'continuation-${++id}',
    );
  });

  TaskModel task() => TaskModel(
        title: 'Dentiste',
        category: 'To-do',
        isDone: false,
        createdAt: now,
        dueDate: '2026-07-24',
        planning: '2026-07-24',
      );

  test('task continuation is typed, immutable and session scoped', () {
    coordinator.beginTaskPlanning(
      task: task(),
      originalMessage: 'Ajoute dentiste',
      sessionGeneration: 4,
    );

    final active = coordinator.active!;
    expect(active.schemaVersion, 1);
    expect(active.type, SmartPlanningContinuationType.taskPlanning);
    expect(active.step, SmartPlanningContinuationStep.planningConsent);
    expect(active.sessionGeneration, 4);
    expect(active.actionType, ActionType.smartPlanningReservation);
    expect(active.origin, ActionOrigin.structuredContinuation);
    expect(active.riskLevel, ActionRiskLevel.mutation);
    expect(active.policyModeAtCreation, ActionAutonomyMode.suggestions);
    expect(active.policyVersionAtCreation, 1);
    expect(active.mutationId, isNotEmpty);
    expect(() => active.groupedTasks.add(task()), throwsUnsupportedError);
  });

  test('current paused policy blocks reservation and preserves continuation',
      () async {
    var mode = ActionAutonomyMode.suggestions;
    coordinator = SmartPlanningContinuationCoordinator(
      gateway: gateway,
      clock: () => now,
      idGenerator: () => 'policy-${++id}',
      loadAutonomyPolicy: () async => ActionAutonomyPolicy(
        mode: mode,
        changedAt: now,
        changeSource: ActionAutonomyChangeSource.explicitUserSetting,
        accountScopeId: 'scope-a',
      ),
    );
    await _reachOptions(coordinator, task(), generation: 7);
    mode = ActionAutonomyMode.paused;
    final blocked = await coordinator.resolve('1', sessionGeneration: 7);
    expect(blocked!.reply, contains('pause'));
    expect(gateway.addedEvents, isEmpty);
    expect(
      coordinator.active!.policyState,
      SmartPlanningPolicyState.blockedByPolicy,
    );
    mode = ActionAutonomyMode.normal;
    expect(gateway.addedEvents, isEmpty);
    final completed = await coordinator.resolve('oui', sessionGeneration: 7);
    expect(completed!.reply, contains('C’est fait'));
    expect(gateway.addedEvents, hasLength(1));
  });

  test('task consent, duration and travel reproduce historical questions',
      () async {
    coordinator.beginTaskPlanning(
      task: task(),
      originalMessage: 'Dentiste demain',
      sessionGeneration: 1,
    );

    await coordinator.resolve('oui', sessionGeneration: 1);
    expect(coordinator.active!.step, SmartPlanningContinuationStep.duration);

    final invalid =
        await coordinator.resolve('longtemps', sessionGeneration: 1);
    expect(invalid!.reply, contains('30 min'));
    expect(coordinator.active!.step, SmartPlanningContinuationStep.duration);

    await coordinator.resolve('45 min', sessionGeneration: 1);
    expect(coordinator.active!.step, SmartPlanningContinuationStep.travelGo);
    await coordinator.resolve('15 min', sessionGeneration: 1);
    expect(coordinator.active!.step, SmartPlanningContinuationStep.travelBack);
    await coordinator.resolve('pareil', sessionGeneration: 1);
    expect(
        coordinator.active!.step, SmartPlanningContinuationStep.optionChoice);
    expect(coordinator.active!.travelGoMinutes, 15);
    expect(coordinator.active!.travelBackMinutes, 15);
  });

  test('negative planning consent keeps only the todo and clears state',
      () async {
    coordinator.beginTaskPlanning(
      task: task(),
      originalMessage: 'Dentiste',
      sessionGeneration: 1,
    );
    final result = await coordinator.resolve('non', sessionGeneration: 1);
    expect(result!.reply, contains('to-do'));
    expect(coordinator.active, isNull);
  });

  test('explicit slot request follows duration and both travel steps',
      () async {
    final started = await coordinator.resolve(
      'Propose-moi un créneau pour le dentiste demain',
      sessionGeneration: 2,
    );
    expect(started!.reply, contains('durée'));
    expect(
      coordinator.active!.type,
      SmartPlanningContinuationType.explicitSlotRequest,
    );

    await coordinator.resolve('1 heure', sessionGeneration: 2);
    await coordinator.resolve('0', sessionGeneration: 2);
    await coordinator.resolve('0', sessionGeneration: 2);
    expect(
        coordinator.active!.step, SmartPlanningContinuationStep.optionChoice);
  });

  test('explicit slot request without options asks to search farther',
      () async {
    gateway.options = const [];
    await coordinator.resolve(
      'Propose-moi un créneau pour le dentiste demain',
      sessionGeneration: 2,
    );
    await coordinator.resolve('1 heure', sessionGeneration: 2);
    await coordinator.resolve('0', sessionGeneration: 2);
    final result = await coordinator.resolve('0', sessionGeneration: 2);

    expect(result!.reply, contains('cherche plus loin'));
    expect(
      coordinator.active!.step,
      SmartPlanningContinuationStep.alternativeConfirmation,
    );
    expect(gateway.proposalCalls, 0);
  });

  test('option choice, recap and confirmation add one event', () async {
    await _reachOptions(coordinator, task(), generation: 3);
    final recap = await coordinator.resolve('1', sessionGeneration: 3);
    expect(recap!.reply, contains('Tu confirmes'));
    expect(
        coordinator.active!.step, SmartPlanningContinuationStep.confirmation);

    final success = await coordinator.resolve('oui', sessionGeneration: 3);
    expect(success!.reply, contains('C’est fait'));
    expect(gateway.addedEvents, hasLength(1));
    expect(gateway.addedEvents.single.travelGoMinutes, 15);
    expect(gateway.addedEvents.single.travelBackMinutes, 15);
    expect(coordinator.active, isNull);
  });

  test('invalid option and invalid confirmation do not execute', () async {
    await _reachOptions(coordinator, task(), generation: 1);
    final invalidChoice = await coordinator.resolve('9', sessionGeneration: 1);
    expect(invalidChoice!.reply, contains('numéro'));
    expect(gateway.addedEvents, isEmpty);

    await coordinator.resolve('1', sessionGeneration: 1);
    final invalidConfirmation =
        await coordinator.resolve('peut-être', sessionGeneration: 1);
    expect(invalidConfirmation!.reply, contains('oui'));
    expect(gateway.addedEvents, isEmpty);
  });

  test('revalidation conflict offers alternatives without writing', () async {
    gateway.revalidationConflict = true;
    await _reachOptions(coordinator, task(), generation: 1);
    await coordinator.resolve('1', sessionGeneration: 1);
    final result = await coordinator.resolve('oui', sessionGeneration: 1);
    expect(result!.reply, contains('vient d’être pris'));
    expect(gateway.addedEvents, isEmpty);
    expect(
        coordinator.active!.step, SmartPlanningContinuationStep.optionChoice);
  });

  test('simple proposal checks conflict and transitions to alternative search',
      () async {
    gateway.options = const [];
    gateway.conflictEvent = EventModel(
      title: 'Occupé',
      date: '2026-07-24',
      time: '10:00',
      category: 'Agenda',
      notes: '',
      createdAt: now,
      startDateTimeIso: '2026-07-24T10:00:00',
    );
    await _reachProposal(coordinator, task(), generation: 1);
    final result = await coordinator.resolve('oui', sessionGeneration: 1);
    expect(result!.reply, contains('conflit'));
    expect(
      coordinator.active!.step,
      SmartPlanningContinuationStep.alternativeConfirmation,
    );
    expect(gateway.addedEvents, isEmpty);
  });

  test('alternative search is bounded and can produce a new confirmation',
      () async {
    gateway.options = const [];
    gateway.proposalCanSucceedAfter = 2;
    await _reachProposal(coordinator, task(), generation: 1);

    final result = await coordinator.resolve('oui', sessionGeneration: 1);
    expect(result!.reply, contains('autre possibilité'));
    expect(gateway.proposalCalls, lessThanOrEqualTo(14));
    expect(
        coordinator.active!.step, SmartPlanningContinuationStep.confirmation);
  });

  test('cancellation, stale generation, expiration and invalidate are safe',
      () async {
    coordinator.beginTaskPlanning(
      task: task(),
      originalMessage: 'Dentiste',
      sessionGeneration: 1,
    );
    final stale = await coordinator.resolve('oui', sessionGeneration: 2);
    expect(stale!.reply, contains('plus active'));
    expect(coordinator.active, isNull);

    coordinator.beginTaskPlanning(
      task: task(),
      originalMessage: 'Dentiste',
      sessionGeneration: 2,
    );
    now = now.add(const Duration(hours: 3));
    final expired = await coordinator.resolve('oui', sessionGeneration: 2);
    expect(expired!.reply, contains('expiré'));
    expect(coordinator.active, isNull);

    coordinator.beginTaskPlanning(
      task: task(),
      originalMessage: 'Dentiste',
      sessionGeneration: 3,
    );
    coordinator.invalidate();
    expect(coordinator.active, isNull);
  });
}

Future<void> _reachOptions(
  SmartPlanningContinuationCoordinator coordinator,
  TaskModel task, {
  required int generation,
}) async {
  coordinator.beginTaskPlanning(
    task: task,
    originalMessage: 'Dentiste demain',
    sessionGeneration: generation,
  );
  await coordinator.resolve('oui', sessionGeneration: generation);
  await coordinator.resolve('45 min', sessionGeneration: generation);
  await coordinator.resolve('15 min', sessionGeneration: generation);
  await coordinator.resolve('pareil', sessionGeneration: generation);
}

Future<void> _reachProposal(
  SmartPlanningContinuationCoordinator coordinator,
  TaskModel task, {
  required int generation,
}) async {
  await _reachOptions(coordinator, task, generation: generation);
}

final class _FakeGateway implements SmartPlanningContinuationGateway {
  List<PlanningProposalOption> options = [
    PlanningProposalOption(
      start: DateTime.utc(2026, 7, 24, 9),
      end: DateTime.utc(2026, 7, 24, 11),
      score: 90,
      dateIso: '2026-07-24',
      startTime: '09:00',
      endTime: '11:00',
      label: 'vendredi 24 juillet à 9 h',
    ),
  ];
  final List<EventModel> addedEvents = [];
  EventModel? conflictEvent;
  bool revalidationConflict = false;
  int proposalCalls = 0;
  int proposalCanSucceedAfter = 0;

  @override
  Future<void> addEvent(EventModel event) async => addedEvents.add(event);

  @override
  Future<SmartPlanningProposal> buildProposal({
    required TaskModel task,
    required String originalMessage,
    required int actionMinutes,
    required int travelGoMinutes,
    required int travelBackMinutes,
    required List<TaskModel> groupedTasks,
  }) async {
    proposalCalls++;
    final success = proposalCalls > proposalCanSucceedAfter;
    return SmartPlanningProposal(
      canPropose: success,
      taskTitle: task.title,
      taskType: 'appointment',
      needsTravel: true,
      date: task.dueDate.isEmpty ? '2026-07-24' : task.dueDate,
      startTime: '10:00',
      endTime: '10:45',
      actionMinutes: actionMinutes,
      travelGoMinutes: travelGoMinutes,
      travelBackMinutes: travelBackMinutes,
      marginMinutes: 15,
      totalMinutes: actionMinutes + travelGoMinutes + travelBackMinutes + 15,
      explanation: '',
      confirmationMessage:
          success ? 'Tu confirmes ce créneau ?' : 'Chercher un autre jour ?',
    );
  }

  @override
  Future<EventModel?> conflict(EventModel event) async => conflictEvent;

  @override
  Future<PlanningProposalEngineResult> findOptions({
    required DateTime startDate,
    required int totalMinutes,
    required int searchDays,
  }) async =>
      PlanningProposalEngineResult(
        hasOptions: options.isNotEmpty,
        options: options,
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
      revalidationConflict
          ? SelectedSlotRevalidationResult(
              isAvailable: false,
              conflictEvent: EventModel(
                title: 'Occupé',
                date: '2026-07-24',
                time: '09:00',
                category: 'Agenda',
                notes: '',
                createdAt: DateTime.utc(2026, 7, 23),
                startDateTimeIso: '2026-07-24T09:00:00',
              ),
              alternatives: PlanningProposalEngineResult(
                hasOptions: true,
                options: options,
                explanation: '',
              ),
            )
          : const SelectedSlotRevalidationResult(
              isAvailable: true,
              conflictEvent: null,
              alternatives: PlanningProposalEngineResult(
                hasOptions: false,
                options: [],
                explanation: '',
              ),
            );
}
