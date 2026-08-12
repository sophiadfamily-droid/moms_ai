import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/services/action_handler_service.dart';
import 'package:moms_ai/services/event_planning_conflict_service.dart';
import 'package:moms_ai/services/life_context/life_context_projection_compatibility.dart';
import 'package:moms_ai/services/routine/routine_planning_blocker_service.dart';

void main() {
  test('finds a profile schedule conflict when the agenda is free', () async {
    final service = EventPlanningConflictService(
      loadEventConflict: ({required candidate}) async => null,
      routinePlanningBlockers: _profileBlockers(),
      currentAccountScopeId: () => 'account-a',
    );

    final conflict = await service.findConflict(
      candidate: _event(time: '09:30'),
    );

    expect(conflict, isNotNull);
    expect(conflict!.title, 'Tes horaires de travail');
  });

  test('finds a conflict as soon as the requested start is already occupied',
      () async {
    final service = EventPlanningConflictService(
      loadEventConflict: ({required candidate}) async => null,
      routinePlanningBlockers: _profileBlockers(),
      currentAccountScopeId: () => 'account-a',
    );

    final conflict = await service.findConflictAtStart(
      startDateTimeIso: '2026-08-17T09:30:00',
    );

    expect(conflict, isNotNull);
    expect(conflict!.title, 'Tes horaires de travail');
  });

  test('suggests the first free quarter-hour after the blocking item',
      () async {
    final service = EventPlanningConflictService(
      loadEventConflict: ({required candidate}) async => null,
      routinePlanningBlockers: _profileBlockers(),
      currentAccountScopeId: () => 'account-a',
    );
    final conflict = await service.findConflictAtStart(
      startDateTimeIso: '2026-08-17T09:30:00',
    );

    final suggestion = await service.suggestAlternativeAtStart(
      startDateTimeIso: '2026-08-17T09:30:00',
      conflict: conflict!,
    );

    expect(suggestion, DateTime(2026, 8, 17, 10));
  });

  test('moves the full protected range after a conflict', () async {
    final service = EventPlanningConflictService(
      loadEventConflict: ({required candidate}) async => null,
      routinePlanningBlockers: _profileBlockers(),
      currentAccountScopeId: () => 'account-a',
    );
    final conflict = await service.findConflictAtStart(
      startDateTimeIso: '2026-08-17T09:30:00',
    );
    final candidate = EventModel(
      title: 'Dentiste',
      date: '2026-08-17',
      time: '09:30',
      notes: '',
      category: 'Personnel',
      createdAt: DateTime(2026, 8, 17),
      startDateTimeIso: '2026-08-17T09:30:00',
      endTime: '10:30',
      endDateTimeIso: '2026-08-17T10:30:00',
      durationMinutes: 60,
      travelGoMinutes: 20,
      travelBackMinutes: 10,
      usesSeparateTravelTimes: true,
      marginMinutes: 5,
    );

    final suggestion = await service.suggestAlternative(
      candidate: candidate,
      conflict: conflict!,
    );

    expect(suggestion, DateTime(2026, 8, 17, 10, 20));
  });

  test('profile conflict survives a failing canonical planning source',
      () async {
    final profile = UserProfile(
      firstName: 'Sophia',
      familyStatus: '',
      workStatus: '',
      partnerName: '',
      wantsNotifications: true,
      children: const [],
      personalActivities: [
        ActivityModel(
          title: 'Pilates',
          days: const ['mercredi'],
          timeRanges: [
            TimeRangeModel(startTime: '09:00', endTime: '10:00'),
          ],
        ),
      ],
    );
    final service = EventPlanningConflictService(
      loadEventConflict: ({required candidate}) async => null,
      routinePlanningBlockers: RoutinePlanningBlockerService(
        loadPlanningContext: (_) => throw StateError('source unavailable'),
      ),
      profilePlanningBlockers:
          RoutinePlanningBlockerService.fromProfile(() => profile),
      currentAccountScopeId: () => 'account-a',
    );

    final conflict = await service.findConflictAtStart(
      startDateTimeIso: '2026-08-12T09:30:00',
    );

    expect(conflict, isNotNull);
    expect(conflict!.title, 'Pilates');
  });

  test('another person school schedule does not create an Event conflict',
      () async {
    final profile = UserProfile(
      firstName: 'Sophia',
      familyStatus: '',
      workStatus: '',
      partnerName: '',
      wantsNotifications: true,
      children: [
        ChildProfile(
          firstName: 'Kassim',
          age: '4',
          birthDate: '',
          gender: '',
          school: 'École',
          notes: '',
          schoolTimeRanges: [
            TimeRangeModel(
              startTime: '08:30',
              endTime: '11:50',
              notes: '__DAYS__:Lundi__ Horaires scolaires',
            ),
          ],
        ),
      ],
    );
    final service = EventPlanningConflictService(
      loadEventConflict: ({required candidate}) async => null,
      routinePlanningBlockers:
          RoutinePlanningBlockerService.fromProfile(() => profile),
      currentAccountScopeId: () => 'account-a',
    );

    final conflict = await service.findConflictAtStart(
      startDateTimeIso: '2026-08-17T09:30:00',
    );

    expect(conflict, isNull);
  });

  test('explicit recurring transport blocks only its short transition',
      () async {
    final service = EventPlanningConflictService(
      loadEventConflict: ({required candidate}) async => null,
      routinePlanningBlockers: RoutinePlanningBlockerService(
        loadPlanningContext: (_) async => PlanningProjectionContext(
          primaryPersonNodeId: 'human:person:primary',
          events: const [],
          routines: const [
            PlanningProjectionRoutine(
              id: 'school-schedule',
              routineKind: 'schoolSchedule',
              subjectNodeId: 'human:person:child',
              days: ['lundi'],
              startTime: '08:30',
              endTime: '16:30',
              travelMinutes: 0,
            ),
          ],
          temporalResponsibilities: const [],
          recurringPlanningConsequences: [
            PlanningProjectionRecurringConsequence(
              id: 'school-drop-off',
              kind: 'transport',
              responsiblePersonNodeId: 'human:person:primary',
              subjectPersonNodeId: 'human:person:child',
              weekdays: const [DateTime.monday],
              startTime: '08:20',
              endTime: '08:40',
            ),
          ],
          warningCodes: const [],
        ),
      ),
      currentAccountScopeId: () => 'account-a',
    );

    final duringDropOff = await service.findConflictAtStart(
      startDateTimeIso: '2026-08-17T08:30:00',
    );
    final duringSchool = await service.findConflictAtStart(
      startDateTimeIso: '2026-08-17T09:30:00',
    );

    expect(duringDropOff?.title, 'Un trajet à assurer');
    expect(duringSchool, isNull);
  });

  test('an unavailable conflict source never breaks event preparation',
      () async {
    final service = EventPlanningConflictService(
      loadEventConflict: ({required candidate}) =>
          throw StateError('event source unavailable'),
      routinePlanningBlockers: RoutinePlanningBlockerService(
        loadPlanningContext: (_) => throw StateError('routine unavailable'),
      ),
      currentAccountScopeId: () => 'account-a',
    );

    expect(
      await service.findConflictAtStart(
        startDateTimeIso: '2026-08-12T09:30:00',
      ),
      isNull,
    );
  });

  test('keeps a persisted agenda conflict as the first authority', () async {
    var profileLoads = 0;
    final agendaConflict = _event(title: 'Médecin', time: '09:15');
    final service = EventPlanningConflictService(
      loadEventConflict: ({required candidate}) async => agendaConflict,
      routinePlanningBlockers: RoutinePlanningBlockerService(
        loadPlanningContext: (_) async {
          profileLoads++;
          return _planningContext();
        },
      ),
      currentAccountScopeId: () => 'account-a',
    );

    expect(
      await service.findConflict(candidate: _event(time: '09:30')),
      same(agendaConflict),
    );
    expect(profileLoads, 0);
  });

  test('event preparation asks for another time when profile is occupied',
      () async {
    final conflictService = EventPlanningConflictService(
      loadEventConflict: ({required candidate}) async => null,
      routinePlanningBlockers: _profileBlockers(),
      currentAccountScopeId: () => 'account-a',
    );

    final result = await ActionHandlerService.handleAction(
      action: const {
        'type': 'event',
        'title': 'Dentiste',
        'date': '2026-08-17',
        'time': '09:30',
        'durationMinutes': 30,
      },
      currentUserMessage: 'Dentiste lundi à 9 h 30 pendant 30 minutes',
      normalizeTime: (value) => value,
      parseDurationMinutes: (_) => 30,
      weekdayFromText: () => 0,
      messageLooksRecurringWeekly: () => false,
      nextDateForWeekday: (_) => '',
      eventNeedsTravel: (_) => false,
      buildStartDateTimeIso: ({required date, required time}) =>
          '${date}T$time:00',
      buildEndDateTimeIso: ({
        required date,
        required time,
        required durationMinutes,
      }) =>
          '2026-08-17T10:00:00',
      endTimeFromDuration: ({
        required date,
        required time,
        required durationMinutes,
      }) =>
          '10:00',
      eventStartConflictChecker: ({required startDateTimeIso}) async => null,
      eventConflictChecker: conflictService.findConflict,
    );

    expect(result.pendingConflictResolutionEvent, isNotNull);
    expect(result.pendingConfirmationEvent, isNull);
    expect(result.message, contains('Tes horaires de travail'));
  });

  test('event preparation reports an occupied start before asking duration',
      () async {
    final conflictService = EventPlanningConflictService(
      loadEventConflict: ({required candidate}) async => null,
      routinePlanningBlockers: _profileBlockers(),
      currentAccountScopeId: () => 'account-a',
    );

    final result = await ActionHandlerService.handleAction(
      action: const {
        'type': 'event',
        'title': 'Dentiste',
        'date': '2026-08-17',
        'time': '09:30',
        'durationMinutes': 0,
      },
      currentUserMessage: 'Dentiste lundi à 9 h 30',
      normalizeTime: (value) => value,
      parseDurationMinutes: (_) => 0,
      weekdayFromText: () => 0,
      messageLooksRecurringWeekly: () => false,
      nextDateForWeekday: (_) => '',
      eventNeedsTravel: (_) => false,
      buildStartDateTimeIso: ({required date, required time}) =>
          '${date}T$time:00',
      buildEndDateTimeIso: ({
        required date,
        required time,
        required durationMinutes,
      }) =>
          '2026-08-17T09:30:00',
      endTimeFromDuration: ({
        required date,
        required time,
        required durationMinutes,
      }) =>
          '09:30',
      eventStartConflictChecker: conflictService.findConflictAtStart,
      eventConflictChecker: conflictService.findConflict,
    );

    expect(result.pendingConflictResolutionEvent, isNotNull);
    expect(result.pendingDurationEvent, isNull);
    expect(result.conflictEvent?.title, 'Tes horaires de travail');
    expect(result.conflictingStartDateTimeIso, '2026-08-17T09:30:00');
    expect(result.message, contains('Tes horaires de travail'));
  });
}

RoutinePlanningBlockerService _profileBlockers() =>
    RoutinePlanningBlockerService(
      loadPlanningContext: (_) async => _planningContext(),
    );

PlanningProjectionContext _planningContext() => PlanningProjectionContext(
      events: const [],
      routines: const [
        PlanningProjectionRoutine(
          id: 'workSchedule:0',
          routineKind: 'workSchedule',
          days: ['lundi'],
          startTime: '09:00',
          endTime: '10:00',
          travelMinutes: 0,
        ),
      ],
      temporalResponsibilities: const [],
      warningCodes: const [],
    );

EventModel _event({String title = 'Dentiste', required String time}) =>
    EventModel(
      id: 'event-$time',
      title: title,
      date: '2026-08-17',
      time: time,
      notes: '',
      category: 'Personnel',
      createdAt: DateTime(2026, 8, 17),
      startDateTimeIso: '2026-08-17T$time:00',
      endDateTimeIso: '2026-08-17T10:00:00',
      endTime: '10:00',
      durationMinutes: 30,
    );
