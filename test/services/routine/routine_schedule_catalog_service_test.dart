import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/routine/routine_schedule_definition.dart';
import 'package:moms_ai/models/routine_model.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/services/routine/routine_schedule_catalog_service.dart';

void main() {
  final profile = UserProfile(
    humanPersonId: 'person-user',
    firstName: 'Sophia',
    familyStatus: 'Nous sommes une famille avec enfants',
    workStatus: 'Je suis salariée',
    partnerName: '',
    wantsNotifications: true,
    workDays: const ['Lundi'],
    workTimeRanges: [
      TimeRangeModel(
        label: 'Bureau',
        startTime: '09:00',
        endTime: '17:00',
      ),
    ],
    personalActivities: [
      ActivityModel(
        title: 'Pilates',
        days: const ['Mercredi'],
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
            notes: '__DAYS__:Lundi|Mardi__',
          ),
        ],
        activities: [
          ActivityModel(
            title: 'Football',
            days: const ['Samedi'],
            timeRanges: [
              TimeRangeModel(startTime: '10:00', endTime: '11:00'),
            ],
          ),
        ],
      ),
    ],
  );

  test('creates stable typed definitions from every structured profile range',
      () {
    final first = RoutineScheduleCatalogService.fromProfile(
      profile: profile,
      accountScopeId: 'account-a',
    );
    final second = RoutineScheduleCatalogService.fromProfile(
      profile: profile,
      accountScopeId: 'account-a',
    );

    expect(first, hasLength(4));
    expect(first.map((item) => item.routine.id),
        orderedEquals(second.map((item) => item.routine.id)));
    expect(first.map((item) => item.kind).toSet(), {
      RoutineScheduleKind.personalActivity,
      RoutineScheduleKind.work,
      RoutineScheduleKind.school,
      RoutineScheduleKind.householdActivity,
    });
    expect(
      first
          .singleWhere((item) => item.kind == RoutineScheduleKind.school)
          .subjectLabel,
      'Kassim',
    );
    expect(
      first
          .where((item) => {
                RoutineScheduleKind.school,
                RoutineScheduleKind.householdActivity,
              }.contains(item.kind))
          .every((item) => !item.blocksPrimaryUser),
      isTrue,
    );
  });

  test('deduplicates a canonical routine mirrored in Profile', () async {
    final canonical = RoutineModel(
      id: 'canonical-pilates',
      accountScopeId: 'account-a',
      logicalRequestId: 'request-pilates',
      title: 'Pilates',
      recurrenceType: RoutineRecurrenceType.weekly,
      days: const [DateTime.wednesday],
      startTime: '09:00',
      durationMinutes: 60,
      travelGoMinutes: 0,
      travelBackMinutes: 0,
      marginMinutes: 0,
      createdAt: DateTime.utc(2026, 8, 1),
      updatedAt: DateTime.utc(2026, 8, 1),
    );
    final service = RoutineScheduleCatalogService(
      loadRoutines: (_) async => [canonical],
      loadProfile: () async => profile,
    );

    final catalog = await service.forAccount('account-a');
    final pilates = catalog.where((item) => item.routine.title == 'Pilates');

    expect(pilates, hasLength(1));
    expect(pilates.single.routine.id, 'canonical-pilates');
    expect(pilates.single.kind, RoutineScheduleKind.personalActivity);
  });
}
