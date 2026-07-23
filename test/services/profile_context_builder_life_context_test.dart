import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/services/life_context/life_context_engine.dart';
import 'package:moms_ai/services/life_context/user_profile_life_context_mapper.dart';
import 'package:moms_ai/services/profile_context_builder_service.dart';
import 'package:moms_ai/services/profile_reasoning_service.dart';

void main() {
  final generatedAt = DateTime.utc(2026, 7, 20, 12);

  test('preserves the complete legacy profile context locally', () {
    final profile = _completeProfile();

    final context = ProfileContextBuilderService.buildStructuredContext(
      profile,
      generatedAt: generatedAt,
    );
    final expectedContext = Map<String, dynamic>.from(_expectedContext)
      ..['planningReasoning'] = ProfileReasoningService.buildReasoning(
        profile,
        generatedAt: generatedAt,
      );

    expect(context, expectedContext);
  });

  test('builds through the injected LifeContextEngine', () {
    final input = _completeProfile();
    final projected = UserProfile(
      firstName: 'Projection',
      familyStatus: 'projection-family',
      workStatus: 'projection-work',
      partnerName: 'Projection Partner',
      wantsNotifications: false,
      children: const [],
      personalNotes: 'projection-personal',
      adminNotes: 'projection-admin',
      budgetNotes: 'projection-budget',
    );
    var projectionCalls = 0;
    final engine = LifeContextEngine(
      profileProjection: ({required profile, required generatedAt}) {
        projectionCalls++;
        expect(profile, same(input));
        expect(generatedAt, DateTime.utc(2026, 7, 20, 12));
        return const UserProfileLifeContextMapper().map(
          profile: projected,
          generatedAt: generatedAt,
        );
      },
    );

    final context = ProfileContextBuilderService.buildStructuredContext(
      input,
      lifeContextEngine: engine,
      generatedAt: generatedAt,
    );

    expect(projectionCalls, 1);
    expect(context['identity'], containsPair('firstName', 'Projection'));
    expect(
        context['family'], containsPair('familyStatus', 'projection-family'));
    expect(context['work'], containsPair('workStatus', 'projection-work'));
    expect(
      context['lifeContext'],
      {
        'personalNotes': 'projection-personal',
        'vehicleInfo': '',
        'petsInfo': '',
        'transportInfo': '',
        'adminNotes': 'projection-admin',
        'budgetNotes': 'projection-budget',
        'importantPlaces': '',
        'personalActivities': const <Map<String, dynamic>>[],
      },
    );
  });

  test('snapshot API produces the same ordered context as the bridge', () {
    final profile = _completeProfile();
    final snapshot = LifeContextEngine().buildSnapshot(
      profile: profile,
      generatedAt: generatedAt,
    );

    final fromProfile = ProfileContextBuilderService.buildStructuredContext(
      profile,
      generatedAt: generatedAt,
    );
    final fromSnapshot =
        ProfileContextBuilderService.buildStructuredContextFromSnapshot(
      snapshot,
    );

    expect(fromSnapshot, fromProfile);
    expect(fromSnapshot.keys.toList(), fromProfile.keys.toList());
    for (final key in fromProfile.keys) {
      final profileValue = fromProfile[key];
      final snapshotValue = fromSnapshot[key];
      if (profileValue is Map && snapshotValue is Map) {
        expect(snapshotValue.keys.toList(), profileValue.keys.toList());
      }
    }
  });

  for (final notes in [
    const <String>[],
    const ['personnelle'],
    const ['personnelle', 'administrative', 'budget'],
  ]) {
    test('preserves ${notes.length} note values from the snapshot', () {
      final profile = UserProfile(
        firstName: 'Sophia',
        familyStatus: '',
        workStatus: '',
        partnerName: '',
        wantsNotifications: true,
        children: const [],
        personalNotes: notes.isNotEmpty ? notes[0] : '',
        adminNotes: notes.length > 1 ? notes[1] : '',
        budgetNotes: notes.length > 2 ? notes[2] : '',
      );
      final snapshot = LifeContextEngine().buildSnapshot(
        profile: profile,
        generatedAt: generatedAt,
      );

      final context =
          ProfileContextBuilderService.buildStructuredContextFromSnapshot(
        snapshot,
      );

      expect(context['lifeContext'],
          containsPair('personalNotes', notes.isNotEmpty ? notes[0] : ''));
      expect(context['lifeContext'],
          containsPair('adminNotes', notes.length > 1 ? notes[1] : ''));
      expect(context['lifeContext'],
          containsPair('budgetNotes', notes.length > 2 ? notes[2] : ''));
    });
  }
}

UserProfile _completeProfile() {
  return UserProfile(
    firstName: 'Sophia',
    familyStatus: 'family',
    workStatus: 'active',
    partnerName: 'Alex',
    wantsNotifications: true,
    children: [
      ChildProfile(
        firstName: 'Lina',
        age: '8',
        birthDate: '2018-01-02',
        gender: 'female',
        school: 'École',
        notes: 'notes enfant',
        className: 'CE2',
        allergies: 'aucune',
        medicalNotes: 'suivi',
        schoolTimeRanges: [
          TimeRangeModel(
            label: 'École',
            startTime: '08:30',
            endTime: '16:30',
            travelMinutes: '10',
            notes: 'lun-ven',
          ),
        ],
        activities: [
          ActivityModel(
            title: 'Danse',
            location: 'Studio',
            days: const ['mercredi'],
            timeRanges: [
              TimeRangeModel(startTime: '14:00', endTime: '15:00'),
            ],
            travelMinutes: '15',
            notes: 'hebdomadaire',
          ),
        ],
      ),
    ],
    age: '35',
    birthDate: '1991-03-04',
    relationshipStatus: 'mariée',
    workHours: 'horaires fixes',
    workScheduleType: 'fixed',
    workDays: const ['lundi', 'mardi'],
    morningStart: '09:00',
    morningEnd: '12:00',
    afternoonStart: '13:00',
    afternoonEnd: '17:00',
    variableWorkDetails: 'aucun',
    workTimeRanges: [
      TimeRangeModel(
        label: 'Bureau',
        startTime: '09:00',
        endTime: '17:00',
        travelMinutes: '20',
        notes: 'sur site',
      ),
    ],
    habits: 'lecture',
    personalNotes: 'note personnelle',
    preferences: 'calme',
    goals: 'objectif historique',
    allergies: 'pollen',
    medicalNotes: 'note médicale',
    bloodType: 'A+',
    doctorName: 'Dr Test',
    emergencyContactName: 'Alex',
    emergencyContactPhone: '0102030405',
    aiTone: 'warm',
    planningStyle: 'souple',
    notificationLevel: 'normal',
    mainLifePriority: 'famille',
    spokenLanguage: 'fr',
    country: 'France',
    timeZone: 'Europe/Paris',
    personalGoals: 'repos',
    businessGoals: 'projet',
    familyGoals: 'vacances',
    vehicleInfo: 'voiture',
    petsInfo: 'chat',
    transportInfo: 'métro',
    childcareInfo: 'nounou',
    foodPreferences: 'végétarien',
    adminNotes: 'note admin',
    budgetNotes: 'note budget',
    importantPlaces: 'domicile',
    personalActivities: [
      ActivityModel(
        title: 'Yoga',
        location: 'Maison',
        days: const ['samedi'],
        timeRanges: [
          TimeRangeModel(startTime: '10:00', endTime: '11:00'),
        ],
        travelMinutes: '0',
        notes: 'tapis',
      ),
    ],
  );
}

const _emptyRangeSuffix = {
  'label': '',
  'travelMinutes': '',
  'notes': '',
};

final Map<String, dynamic> _expectedContext = {
  'identity': {
    'firstName': 'Sophia',
    'age': '35',
    'birthDate': '1991-03-04',
    'country': 'France',
    'timeZone': 'Europe/Paris',
    'spokenLanguage': 'fr',
  },
  'family': {
    'familyStatus': 'family',
    'relationshipStatus': 'mariée',
    'partnerName': 'Alex',
    'childrenCount': 1,
    'childcareInfo': 'nounou',
    'familyGoals': 'vacances',
  },
  'work': {
    'workStatus': 'active',
    'workHours': 'horaires fixes',
    'workScheduleType': 'fixed',
    'workDays': const ['lundi', 'mardi'],
    'morningStart': '09:00',
    'morningEnd': '12:00',
    'afternoonStart': '13:00',
    'afternoonEnd': '17:00',
    'variableWorkDetails': 'aucun',
    'workTimeRanges': const [
      {
        'label': 'Bureau',
        'startTime': '09:00',
        'endTime': '17:00',
        'travelMinutes': '20',
        'notes': 'sur site',
      },
    ],
    'businessGoals': 'projet',
  },
  'children': [
    {
      'firstName': 'Lina',
      'age': '8',
      'birthDate': '2018-01-02',
      'gender': 'female',
      'school': 'École',
      'className': 'CE2',
      'allergies': 'aucune',
      'medicalNotes': 'suivi',
      'schoolTimeRanges': [
        {
          'label': 'École',
          'startTime': '08:30',
          'endTime': '16:30',
          'travelMinutes': '10',
          'notes': 'lun-ven',
        },
      ],
      'activities': [
        {
          'title': 'Danse',
          'location': 'Studio',
          'days': ['mercredi'],
          'timeRanges': [
            {
              ..._emptyRangeSuffix,
              'startTime': '14:00',
              'endTime': '15:00',
            },
          ],
          'travelMinutes': '15',
          'notes': 'hebdomadaire',
        },
      ],
      'notes': 'notes enfant',
    },
  ],
  'preferences': {
    'aiTone': 'warm',
    'planningStyle': 'souple',
    'notificationLevel': 'normal',
    'mainLifePriority': 'famille',
    'preferences': 'calme',
    'habits': 'lecture',
    'goals': 'objectif historique',
    'personalGoals': 'repos',
    'foodPreferences': 'végétarien',
  },
  'health': {
    'allergies': 'pollen',
    'medicalNotes': 'note médicale',
    'bloodType': 'A+',
    'doctorName': 'Dr Test',
    'emergencyContactName': 'Alex',
    'emergencyContactPhone': '0102030405',
  },
  'lifeContext': {
    'personalNotes': 'note personnelle',
    'vehicleInfo': 'voiture',
    'petsInfo': 'chat',
    'transportInfo': 'métro',
    'adminNotes': 'note admin',
    'budgetNotes': 'note budget',
    'importantPlaces': 'domicile',
    'personalActivities': [
      {
        'title': 'Yoga',
        'location': 'Maison',
        'days': ['samedi'],
        'timeRanges': [
          {
            ..._emptyRangeSuffix,
            'startTime': '10:00',
            'endTime': '11:00',
          },
        ],
        'travelMinutes': '0',
        'notes': 'tapis',
      },
    ],
  },
};
