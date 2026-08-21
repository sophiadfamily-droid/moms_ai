import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/human/human_model.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/services/structured_schedule_profile_service.dart';

void main() {
  test('conserve les horaires futurs et retire les horaires datés passés', () {
    final model = _model([
      _record('past', '2026-08-16', '09:00', '17:00'),
      _record('future', '2026-08-18', '21:00', '09:00', nextDay: true),
      _weeklyRecord(),
    ]);

    final cleaned = StructuredScheduleProfileService.pruneExpired(
      model,
      at: DateTime(2026, 8, 17, 12),
    );
    final entries = StructuredScheduleProfileService.entriesForPerson(
      cleaned.persons.single,
      at: DateTime(2026, 8, 17, 12),
    );

    expect(entries.map((entry) => entry.sourceKey), ['weekly', 'future']);
    expect(entries.last.endsNextDay, isTrue);
  });

  test('ne retire une plage de nuit qu’après sa fin le lendemain', () {
    final model = _model([
      _record('night', '2026-08-17', '21:00', '09:00', nextDay: true),
    ]);

    expect(
      StructuredScheduleProfileService.entriesForPerson(
        model.persons.single,
        at: DateTime(2026, 8, 18, 8, 59),
      ),
      hasLength(1),
    );
    expect(
      StructuredScheduleProfileService.entriesForPerson(
        model.persons.single,
        at: DateTime(2026, 8, 18, 9, 1),
      ),
      isEmpty,
    );
  });

  test('migre les horaires du profil vers la bonne personne sans doublon', () {
    final profile = _profile();
    final first =
        StructuredScheduleProfileService.reconcileCompatibilitySchedules(
      model: _householdModel(),
      profile: profile,
    );
    final second =
        StructuredScheduleProfileService.reconcileCompatibilitySchedules(
      model: first,
      profile: profile,
    );

    expect(second.toJson(), first.toJson());
    final primary = StructuredScheduleProfileService.entriesForPerson(
      second.personById('person-a')!,
      at: DateTime(2026, 8, 17),
    );
    final child = StructuredScheduleProfileService.entriesForPerson(
      second.personById('person-child')!,
      at: DateTime(2026, 8, 17),
    );
    expect(primary.map((entry) => entry.target).toSet(), {
      'workSchedule',
      'activitySchedule',
    });
    expect(child.map((entry) => entry.target).toSet(), {'schoolSchedule'});
  });

  test('projette le planning canonique vers les anciens écrans', () {
    final profile = _profile();
    final canonical =
        StructuredScheduleProfileService.reconcileCompatibilitySchedules(
      model: _householdModel(),
      profile: profile,
    );
    final projected =
        StructuredScheduleProfileService.projectOntoCompatibilityProfile(
      model: canonical,
      profile: profile.copyWith(
        workDays: const [],
        workTimeRanges: const [],
        personalActivities: const [],
        children: [
          profile.children.single.copyWith(schoolTimeRanges: const [])
        ],
      ),
      at: DateTime(2026, 8, 17),
    );

    expect(projected.workDays, ['Lundi']);
    expect(projected.workTimeRanges.single.startTime, '09:00');
    expect(projected.personalActivities.single.title, 'Pilates');
    expect(projected.children.single.schoolTimeRanges.single.endTime, '16:30');
  });

  test('une suppression dans le profil retire seulement son miroir canonique',
      () {
    final withCompatibility =
        StructuredScheduleProfileService.reconcileCompatibilitySchedules(
      model: _model([_weeklyRecord()]),
      profile: _profile().copyWith(humanPersonId: 'person-a'),
    );
    final cleared =
        StructuredScheduleProfileService.reconcileCompatibilitySchedules(
      model: withCompatibility,
      profile: _profile().copyWith(
        humanPersonId: 'person-a',
        workDays: const [],
        workTimeRanges: const [],
        personalActivities: const [],
        children: const [],
      ),
    );
    final entries = StructuredScheduleProfileService.entriesForPerson(
      cleared.persons.single,
      at: DateTime(2026, 8, 17),
    );

    expect(entries.map((entry) => entry.sourceKey), ['weekly']);
  });
}

UserProfile _profile() => UserProfile(
      humanPersonId: 'person-a',
      firstName: 'Sophia',
      familyStatus: 'Famille',
      workStatus: 'Salariée',
      partnerName: '',
      wantsNotifications: true,
      workDays: const ['Lundi'],
      workTimeRanges: [
        TimeRangeModel(label: 'Bureau', startTime: '09:00', endTime: '17:00'),
      ],
      personalActivities: [
        ActivityModel(
          title: 'Pilates',
          days: const ['Mercredi'],
          timeRanges: [
            TimeRangeModel(startTime: '10:00', endTime: '11:00'),
          ],
        ),
      ],
      children: [
        ChildProfile(
          humanPersonId: 'person-child',
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
              endTime: '16:30',
              notes: '__DAYS__:Lundi__',
            ),
          ],
        ),
      ],
    );

HumanModel _householdModel() => HumanModel(
      accountScopeId: 'account-a',
      primaryPersonId: 'person-a',
      persons: [
        HumanPerson(
          id: 'person-a',
          accountScopeId: 'account-a',
          displayName: 'Sophia',
          evidence: const HumanEvidence(
            source: HumanInformationSource.explicitUserInput,
            confirmation: HumanConfirmationStatus.confirmed,
          ),
        ),
        HumanPerson(
          id: 'person-child',
          accountScopeId: 'account-a',
          displayName: 'Kassim',
          evidence: const HumanEvidence(
            source: HumanInformationSource.explicitUserInput,
            confirmation: HumanConfirmationStatus.confirmed,
          ),
        ),
      ],
    );

HumanModel _model(List<Map<String, Object?>> schedules) => HumanModel(
      accountScopeId: 'account-a',
      primaryPersonId: 'person-a',
      persons: [
        HumanPerson(
          id: 'person-a',
          accountScopeId: 'account-a',
          displayName: 'Willy',
          evidence: const HumanEvidence(
            source: HumanInformationSource.imported,
            confirmation: HumanConfirmationStatus.confirmed,
          ),
          customFields: {'structuredSchedulesV1': schedules},
        ),
      ],
    );

Map<String, Object?> _record(
  String key,
  String date,
  String start,
  String end, {
  bool nextDay = false,
}) =>
    {
      'sourceKey': key,
      'target': 'workSchedule',
      'temporalKind': 'dated',
      'title': 'Travail',
      'dateIso': date,
      'weekdays': const <int>[],
      'startTime': start,
      'endTime': end,
      if (nextDay) 'endsNextDay': true,
    };

Map<String, Object?> _weeklyRecord() => {
      'sourceKey': 'weekly',
      'target': 'workSchedule',
      'temporalKind': 'recurringWeekly',
      'title': 'Travail habituel',
      'weekdays': const [DateTime.monday],
      'startTime': '09:00',
      'endTime': '17:00',
    };
