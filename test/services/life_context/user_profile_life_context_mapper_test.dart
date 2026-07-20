import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/life_context/identity_context.dart';
import 'package:moms_ai/models/life_context/intent_context.dart';
import 'package:moms_ai/models/life_context/life_context_provenance.dart';
import 'package:moms_ai/models/life_context/life_context_snapshot.dart';
import 'package:moms_ai/models/life_context/schedule_context.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/services/life_context/user_profile_life_context_mapper.dart';

void main() {
  const mapper = UserProfileLifeContextMapper();
  final generatedAt = DateTime.utc(2026, 7, 20, 10, 30);

  group('LifeContextSnapshot v1', () {
    test('can represent a minimal immutable snapshot', () {
      final snapshot = LifeContextSnapshot(
        generatedAt: generatedAt,
        identity: const IdentityContext(),
        household: HouseholdContext(),
        places: const PlaceContext(),
        mobility: const MobilityContext(),
        work: WorkContext(),
        agenda: AgendaContext(),
        routines: RoutineContext(),
        goals: GoalContext(),
        preferences: PreferenceContext(
          wantsNotifications: LifeContextFact(
            value: false,
            provenance: _profileProvenance('wantsNotifications'),
          ),
        ),
        constraints: const ConstraintContext(),
      );

      expect(snapshot.schemaVersion, 1);
      expect(snapshot.generatedAt, same(generatedAt));
      expect(snapshot.identity.firstName, isNull);
      expect(snapshot.household.children, isEmpty);
      expect(
        () => snapshot.household.children.add(HouseholdMemberContext()),
        throwsUnsupportedError,
      );
    });

    test('maps a complete UserProfile without interpreting its facts', () {
      final snapshot =
          mapper.map(profile: _completeProfile(), generatedAt: generatedAt);

      expect(snapshot.schemaVersion, 1);
      expect(snapshot.generatedAt, same(generatedAt));
      expect(snapshot.identity.firstName?.value, 'Sophia');
      expect(snapshot.identity.birthDate?.value, '01/01/1990');
      expect(snapshot.identity.age?.value, '36');
      expect(snapshot.identity.spokenLanguage?.value, 'fr');
      expect(snapshot.identity.country?.value, 'France');
      expect(snapshot.identity.timeZone?.value, 'Europe/Paris');
      expect(snapshot.household.partnerName?.value, 'Alex');
      expect(snapshot.household.children.single.firstName?.value, 'Lina');
      expect(snapshot.places.importantPlaces?.value, 'École et pharmacie');
      expect(snapshot.mobility.vehicleInfo?.value, 'Voiture familiale');
      expect(snapshot.work.workDays?.value, ['Lundi', 'Mardi']);
      expect(snapshot.work.timeRanges.single.startTime?.value, '09:00');
      expect(snapshot.routines.personalActivities.single.title?.value, 'Yoga');
      expect(snapshot.routines.childRoutines.single.childName?.value, 'Lina');
      expect(
        snapshot.routines.childRoutines.single.schoolTimeRanges.single.startTime
            ?.value,
        '08:30',
      );
      expect(
        snapshot.routines.childRoutines.single.activities.single.title?.value,
        'Danse',
      );
      expect(snapshot.goals.goals.map((goal) => goal.domain), [
        GoalDomain.personal,
        GoalDomain.professional,
        GoalDomain.family,
        GoalDomain.historical,
      ]);
      expect(snapshot.preferences.aiTone?.value, 'chaleureux');
      expect(snapshot.constraints.allergies?.value, 'Pénicilline');
    });

    test('preserves absent values instead of inventing them', () {
      final snapshot = mapper.map(
        profile: _minimalProfile(),
        generatedAt: generatedAt,
      );
      final json = snapshot.toJson();

      expect(snapshot.identity.firstName?.value, 'Sophia');
      expect(snapshot.identity.birthDate, isNull);
      expect(snapshot.identity.age, isNull);
      expect(snapshot.identity.country, isNull);
      expect(snapshot.identity.timeZone, isNull);
      expect(snapshot.household.partnerName, isNull);
      expect(snapshot.places.importantPlaces, isNull);
      expect(snapshot.work.workDays, isNull);
      expect(snapshot.goals.goals, isEmpty);
      expect((json['identity'] as Map<String, dynamic>).containsKey('lastName'),
          isFalse);
      expect((json['identity'] as Map<String, dynamic>).containsKey('city'),
          isFalse);
    });

    test('marks explicit profile facts and only calculated age as derived', () {
      final snapshot =
          mapper.map(profile: _completeProfile(), generatedAt: generatedAt);

      expect(
        snapshot.identity.firstName?.provenance.sourceType,
        LifeContextSourceType.profile,
      );
      expect(
        snapshot.identity.firstName?.provenance.evidenceType,
        LifeContextEvidenceType.explicit,
      );
      expect(
        snapshot.identity.age?.provenance.sourceType,
        LifeContextSourceType.derived,
      );
      expect(
        snapshot.identity.age?.provenance.evidenceType,
        LifeContextEvidenceType.derived,
      );
      expect(
        _allProvenances(snapshot.toJson())
            .where((item) => item['sourceType'] == 'derived')
            .map((item) => item['sourceId']),
        ['UserProfile.age'],
      );
    });

    test('keeps preferences distinct from constraints', () {
      final snapshot =
          mapper.map(profile: _completeProfile(), generatedAt: generatedAt);

      expect(snapshot.preferences.planningStyle?.value, 'souple');
      expect(snapshot.preferences.foodPreferences?.value, 'Végétarien');
      expect(snapshot.constraints.allergies?.value, 'Pénicilline');
      expect(
          snapshot.constraints.toJson().containsKey('planningStyle'), isFalse);
      expect(snapshot.constraints.toJson().containsKey('foodPreferences'),
          isFalse);
    });

    test('preserves structured schedules and labels legacy fields', () {
      final snapshot =
          mapper.map(profile: _completeProfile(), generatedAt: generatedAt);

      expect(snapshot.work.timeRanges.single.endTime?.value, '17:00');
      expect(snapshot.work.timeRanges.single.travelMinutes?.value, '20');
      expect(
        snapshot.work.timeRanges.single.startTime?.provenance.evidenceType,
        LifeContextEvidenceType.explicit,
      );
      expect(snapshot.work.legacyWorkHours?.value, 'Ancien horaire libre');
      expect(
        snapshot.work.legacyWorkHours?.provenance.evidenceType,
        LifeContextEvidenceType.historical,
      );
      expect(snapshot.routines.legacyHabits?.value, 'Anciennes habitudes');
      expect(snapshot.preferences.legacyPreferences?.value, 'Préférence libre');
      expect(
        snapshot.goals.goals.last.description.provenance.evidenceType,
        LifeContextEvidenceType.historical,
      );
    });

    test('contains no event, task, shopping, or memory collections', () {
      final json = mapper
          .map(profile: _completeProfile(), generatedAt: generatedAt)
          .toJson();

      expect(json.keys, {
        'schemaVersion',
        'generatedAt',
        'identity',
        'household',
        'places',
        'mobility',
        'work',
        'agenda',
        'routines',
        'goals',
        'preferences',
        'constraints',
      });
      final serialized = json.toString().toLowerCase();
      expect(RegExp(r'\bevents?\b').hasMatch(serialized), isFalse);
      expect(RegExp(r'\btasks?\b').hasMatch(serialized), isFalse);
      expect(RegExp(r'\bshopping\b').hasMatch(serialized), isFalse);
      expect(RegExp(r'\bmemories?\b').hasMatch(serialized), isFalse);
    });

    test('is deterministic and does not mutate UserProfile lists', () {
      final profile = _completeProfile();
      final originalDays = List<String>.from(profile.workDays);
      final originalChildren = List<ChildProfile>.from(profile.children);
      final originalActivities =
          List<ActivityModel>.from(profile.personalActivities);

      final first = mapper.map(profile: profile, generatedAt: generatedAt);
      final second = mapper.map(profile: profile, generatedAt: generatedAt);

      expect(first.toJson(), second.toJson());
      expect(profile.workDays, originalDays);
      expect(profile.children, originalChildren);
      expect(profile.personalActivities, originalActivities);
      expect(() => first.work.workDays?.value.add('Vendredi'),
          throwsUnsupportedError);
      expect(
        () => first.routines.personalActivities.add(
          LifeContextActivity(),
        ),
        throwsUnsupportedError,
      );
    });
  });
}

LifeContextProvenance _profileProvenance(String sourceId) {
  return LifeContextProvenance(
    sourceType: LifeContextSourceType.profile,
    sourceId: 'UserProfile.$sourceId',
    evidenceType: LifeContextEvidenceType.explicit,
  );
}

Iterable<Map<String, dynamic>> _allProvenances(Object? value) sync* {
  if (value is Map) {
    final map = Map<String, dynamic>.from(value);
    if (map['sourceType'] is String && map['evidenceType'] is String) {
      yield map;
    }
    for (final child in map.values) {
      yield* _allProvenances(child);
    }
  } else if (value is Iterable) {
    for (final child in value) {
      yield* _allProvenances(child);
    }
  }
}

UserProfile _minimalProfile() {
  return UserProfile(
    firstName: 'Sophia',
    familyStatus: '',
    workStatus: '',
    partnerName: '',
    wantsNotifications: false,
    children: const [],
  );
}

UserProfile _completeProfile() {
  return UserProfile(
    firstName: 'Sophia',
    familyStatus: 'En couple',
    workStatus: 'Indépendante',
    partnerName: 'Alex',
    wantsNotifications: true,
    children: [
      ChildProfile(
        firstName: 'Lina',
        age: '8',
        birthDate: '02/02/2018',
        gender: 'Fille',
        school: 'École du Centre',
        notes: 'Sortie accompagnée',
        photoPath: '/local/lina.jpg',
        className: 'CE2',
        allergies: 'Arachides',
        doctor: 'Dr Martin',
        medicalNotes: 'Traitement connu',
        schoolTimeRanges: [
          TimeRangeModel(
            label: 'École',
            startTime: '08:30',
            endTime: '16:30',
            travelMinutes: '15',
            notes: 'Lundi à vendredi',
          ),
        ],
        activities: [
          ActivityModel(
            title: 'Danse',
            location: 'Studio',
            days: const ['Mercredi'],
            timeRanges: [
              TimeRangeModel(startTime: '14:00', endTime: '15:00'),
            ],
            travelMinutes: '10',
          ),
        ],
      ),
    ],
    age: '36',
    birthDate: '01/01/1990',
    profilePhotoPath: '/local/sophia.jpg',
    partnerBirthDate: '03/03/1989',
    partnerPhotoPath: '/local/alex.jpg',
    relationshipStatus: 'Pacsée',
    marriageDate: '04/04/2020',
    engagementDate: '05/05/2019',
    workHours: 'Ancien horaire libre',
    workScheduleType: 'fixe',
    workDays: const ['Lundi', 'Mardi'],
    morningStart: '09:00',
    morningEnd: '12:00',
    afternoonStart: '13:00',
    afternoonEnd: '17:00',
    variableWorkDetails: 'Une semaine sur deux',
    workTimeRanges: [
      TimeRangeModel(
        label: 'Bureau',
        startTime: '09:00',
        endTime: '17:00',
        travelMinutes: '20',
        notes: 'Présentiel',
      ),
    ],
    habits: 'Anciennes habitudes',
    personalNotes: 'Notes personnelles non classées',
    preferences: 'Préférence libre',
    goals: 'Objectif historique',
    allergies: 'Pénicilline',
    medicalNotes: 'Suivi annuel',
    bloodType: 'A+',
    doctorName: 'Dr Dupont',
    emergencyContactName: 'Alex',
    emergencyContactPhone: '0102030405',
    aiTone: 'chaleureux',
    planningStyle: 'souple',
    notificationLevel: 'important',
    mainLifePriority: 'Famille',
    spokenLanguage: 'fr',
    country: 'France',
    timeZone: 'Europe/Paris',
    personalGoals: 'Faire du sport',
    businessGoals: 'Développer ZELIA',
    familyGoals: 'Voyager ensemble',
    vehicleInfo: 'Voiture familiale',
    petsInfo: 'Un chat',
    transportInfo: 'Métro privilégié',
    childcareInfo: 'Nounou le jeudi',
    foodPreferences: 'Végétarien',
    adminNotes: 'Dossier administratif',
    budgetNotes: 'Budget mensuel',
    importantPlaces: 'École et pharmacie',
    personalActivities: [
      ActivityModel(
        title: 'Yoga',
        location: 'Maison',
        days: const ['Samedi'],
        timeRanges: [
          TimeRangeModel(startTime: '10:00', endTime: '11:00'),
        ],
        notes: 'Routine personnelle',
      ),
    ],
  );
}
