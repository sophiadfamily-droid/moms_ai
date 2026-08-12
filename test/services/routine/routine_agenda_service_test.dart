import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/routine/routine_occurrence_override.dart';
import 'package:moms_ai/models/routine/routine_schedule_definition.dart';
import 'package:moms_ai/models/routine_model.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/services/routine/routine_agenda_service.dart';
import 'package:moms_ai/services/routine/routine_schedule_catalog_service.dart';

void main() {
  RoutineModel routine({
    required String account,
    RoutineStatus status = RoutineStatus.active,
  }) =>
      RoutineModel(
        id: 'routine-1',
        accountScopeId: account,
        logicalRequestId: 'request-1',
        title: 'Préparer les enfants',
        recurrenceType: RoutineRecurrenceType.weekly,
        days: const [3],
        startTime: '07:30',
        durationMinutes: 45,
        travelGoMinutes: 0,
        travelBackMinutes: 0,
        marginMinutes: 0,
        createdAt: DateTime.utc(2026, 8, 1),
        updatedAt: DateTime.utc(2026, 8, 1),
        status: status,
      );

  test('shows a named read-only projection on the requested day', () async {
    final service = RoutineAgendaService(
      loadRoutines: (_) async => [routine(account: 'account-a')],
    );

    final items = await service.forDay(
      accountScopeId: 'account-a',
      day: DateTime(2026, 8, 5),
    );

    expect(items, hasLength(1));
    expect(items.single.title, 'Préparer les enfants');
    expect(items.single.dateIso, '2026-08-05');
    expect(items.single.startTime, '07:30');
    expect(items.single.endTime, '08:15');
    expect(items.single.protectedStart, DateTime(2026, 8, 5, 7, 30));
    expect(items.single.protectedEnd, DateTime(2026, 8, 5, 8, 15));
  });

  test('does not show a cancelled routine', () async {
    final service = RoutineAgendaService(
      loadRoutines: (_) async => [
        routine(account: 'account-a', status: RoutineStatus.cancelled),
      ],
    );

    final items = await service.forDay(
      accountScopeId: 'account-a',
      day: DateTime(2026, 8, 5),
    );

    expect(items, isEmpty);
  });

  test('shows the moved occurrence at its exceptional day and time', () async {
    final service = RoutineAgendaService(
      loadRoutines: (_) async => [routine(account: 'account-a')],
      loadOverrides: (_) async => [
        RoutineOccurrenceOverride(
          overrideId: 'routine-1-2026-08-05',
          accountScopeId: 'account-a',
          routineId: 'routine-1',
          sourceDateIso: '2026-08-05',
          type: RoutineOccurrenceOverrideType.moved,
          replacementDateIso: '2026-08-06',
          replacementStartTime: '18:30',
          overrideRevision: 1,
          lastMutationId: 'mutation-a',
          createdAt: DateTime.utc(2026, 8, 2),
          updatedAt: DateTime.utc(2026, 8, 2),
        ),
      ],
    );

    expect(
      await service.forDay(
        accountScopeId: 'account-a',
        day: DateTime(2026, 8, 5),
      ),
      isEmpty,
    );
    final moved = await service.forDay(
      accountScopeId: 'account-a',
      day: DateTime(2026, 8, 6),
    );
    expect(moved.single.startTime, '18:30');
    expect(moved.single.endTime, '19:15');
  });

  test('guest agenda does not query the routine repository', () async {
    var queried = false;
    final service = RoutineAgendaService(loadRoutines: (_) async {
      queried = true;
      return const [];
    });

    expect(
      await service.forDay(
        accountScopeId: 'guest',
        day: DateTime(2026, 8, 5),
      ),
      isEmpty,
    );
    expect(queried, isFalse);
  });

  test('projects structured profile schedules as light Agenda items', () async {
    final profile = _profileWithSchedules();
    final service = RoutineAgendaService(
      loadRoutines: (_) async => const [],
      loadProfile: () async => profile,
    );

    final tuesday = await service.forDay(
      accountScopeId: 'account-a',
      day: DateTime(2026, 8, 4),
    );

    expect(
        tuesday.map((item) => item.title), containsAll(['Pilates', 'Bureau']));
    expect(
      tuesday.singleWhere((item) => item.title == 'Pilates').kind,
      RoutineScheduleKind.personalActivity,
    );
    expect(
      tuesday.singleWhere((item) => item.title == 'Bureau').kind,
      RoutineScheduleKind.work,
    );
    expect(tuesday.every((item) => item.blocksPrimaryUser), isTrue);

    final wednesday = await service.forDay(
      accountScopeId: 'account-a',
      day: DateTime(2026, 8, 5),
    );
    final school = wednesday.singleWhere((item) => item.title == 'École');
    expect(school.kind, RoutineScheduleKind.school);
    expect(school.subjectLabel, 'Kassim');
    expect(school.blocksPrimaryUser, isFalse);
  });

  test('a profile activity cancellation hides only the selected occurrence',
      () async {
    final profile = _profileWithSchedules();
    final definition = RoutineScheduleCatalogService.fromProfile(
      profile: profile,
      accountScopeId: 'account-a',
    ).singleWhere(
      (entry) => entry.kind == RoutineScheduleKind.personalActivity,
    );
    final service = RoutineAgendaService(
      loadRoutines: (_) async => const [],
      loadProfile: () async => profile,
      loadOverrides: (_) async => [
        RoutineOccurrenceOverride(
          overrideId: 'cancel-pilates-2026-08-04',
          accountScopeId: 'account-a',
          routineId: definition.routine.id,
          sourceDateIso: '2026-08-04',
          type: RoutineOccurrenceOverrideType.cancelled,
          overrideRevision: 1,
          lastMutationId: 'cancel-pilates',
          createdAt: DateTime.utc(2026, 8, 2),
          updatedAt: DateTime.utc(2026, 8, 2),
        ),
      ],
    );

    final cancelled = await service.forDay(
      accountScopeId: 'account-a',
      day: DateTime(2026, 8, 4),
    );
    final nextWeek = await service.forDay(
      accountScopeId: 'account-a',
      day: DateTime(2026, 8, 11),
    );

    expect(cancelled.where((item) => item.title == 'Pilates'), isEmpty);
    expect(nextWeek.where((item) => item.title == 'Pilates'), hasLength(1));
  });
}

UserProfile _profileWithSchedules() => UserProfile(
      humanPersonId: 'person-user',
      firstName: 'Sophia',
      familyStatus: 'Nous sommes une famille avec enfants',
      workStatus: 'Je suis salariée',
      partnerName: '',
      wantsNotifications: true,
      workDays: const ['Mardi'],
      workTimeRanges: [
        TimeRangeModel(
          label: 'Bureau',
          startTime: '13:00',
          endTime: '17:00',
        ),
      ],
      personalActivities: [
        ActivityModel(
          title: 'Pilates',
          days: const ['Mardi'],
          timeRanges: [
            TimeRangeModel(startTime: '09:00', endTime: '10:00'),
          ],
        ),
      ],
      children: [
        ChildProfile(
          humanPersonId: 'person-kassim',
          firstName: 'Kassim',
          age: '4',
          birthDate: '',
          gender: '',
          school: '',
          notes: '',
          schoolTimeRanges: [
            TimeRangeModel(
              label: 'École',
              startTime: '08:30',
              endTime: '11:50',
              notes: '__DAYS__:Mercredi__',
            ),
          ],
        ),
      ],
    );
