import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/services/life_context/life_context_engine.dart';
import 'package:moms_ai/services/life_context/user_profile_life_context_mapper.dart';
import 'package:moms_ai/services/profile_reasoning_service.dart';

void main() {
  final generatedAt = DateTime.utc(2026, 7, 20, 14);

  group('ProfileReasoningService Life Context migration', () {
    test('builds reasoning from the snapshot supplied by LifeContextEngine',
        () {
      final callerProfile = _profile(workHours: 'Je travaille le soir');
      final projectedProfile = _profile(workHours: 'Je travaille de nuit');
      final projectedSnapshot = const UserProfileLifeContextMapper().map(
        profile: projectedProfile,
        generatedAt: generatedAt,
      );
      UserProfile? receivedProfile;
      DateTime? receivedGeneratedAt;
      var projectionCalls = 0;
      final engine = LifeContextEngine(
        profileProjection: ({required profile, required generatedAt}) {
          projectionCalls++;
          receivedProfile = profile;
          receivedGeneratedAt = generatedAt;
          return projectedSnapshot;
        },
      );

      final reasoning = ProfileReasoningService.buildReasoning(
        callerProfile,
        lifeContextEngine: engine,
        generatedAt: generatedAt,
      );

      expect(projectionCalls, 1);
      expect(receivedProfile, same(callerProfile));
      expect(receivedGeneratedAt, same(generatedAt));
      expect(
        reasoning.where((item) => item['scheduleMode'] == 'night'),
        hasLength(1),
      );
      expect(
        reasoning.where((item) => item['scheduleMode'] == 'late'),
        isEmpty,
      );
    });

    test('keeps bridge and snapshot reasoning outputs identical', () {
      final profile = _completeProfile();
      final engine = LifeContextEngine();
      final snapshot = engine.buildSnapshot(
        profile: profile,
        generatedAt: generatedAt,
      );

      final bridged = ProfileReasoningService.buildReasoning(
        profile,
        lifeContextEngine: engine,
        generatedAt: generatedAt,
      );
      final fromSnapshot = ProfileReasoningService.buildReasoningFromSnapshot(
        snapshot,
      );

      expect(bridged, fromSnapshot);
      expect(
        bridged.map((item) => item['sourceType']),
        [
          'work',
          'work',
          'child_school',
          'child_activity',
          'personal_activity',
          'profile'
        ],
      );
      expect(bridged[0]['label'], 'Bureau');
      expect(bridged[0]['travelBeforeMinutes'], 20);
      expect(bridged[1]['scheduleMode'], 'night');
      expect(bridged[2]['days'], ['Lundi', 'Mardi']);
      expect(bridged[2]['notes'], 'École primaire');
      expect(bridged[3]['label'], 'Danse - Lina');
      expect(bridged[4]['label'], 'Yoga');
      expect(bridged[5]['preferredPeriod'], 'afternoon');
    });

    test('reads personalNotes exclusively from the snapshot notes context', () {
      final profile = _profile(
        personalNotes: 'Je préfère organiser mes rendez-vous l’après-midi',
      );
      final snapshot = const UserProfileLifeContextMapper().map(
        profile: profile,
        generatedAt: generatedAt,
      );

      final reasoning =
          ProfileReasoningService.buildReasoningFromSnapshot(snapshot);

      expect(reasoning.single['type'], 'schedule_preference');
      expect(reasoning.single['preferredPeriod'], 'afternoon');
    });
  });
}

UserProfile _profile({
  String workHours = '',
  String personalNotes = '',
}) {
  return UserProfile(
    firstName: 'Sophia',
    familyStatus: '',
    workStatus: '',
    partnerName: '',
    wantsNotifications: true,
    children: const [],
    workHours: workHours,
    personalNotes: personalNotes,
  );
}

UserProfile _completeProfile() {
  return UserProfile(
    firstName: 'Sophia',
    familyStatus: '',
    workStatus: 'Indépendante',
    partnerName: '',
    wantsNotifications: true,
    children: [
      ChildProfile(
        firstName: 'Lina',
        age: '8',
        birthDate: '',
        gender: '',
        school: 'École',
        notes: '',
        schoolTimeRanges: [
          TimeRangeModel(
            startTime: '08:30',
            endTime: '16:30',
            travelMinutes: '15',
            notes: '__DAYS__:Lundi|Mardi__ École primaire',
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
    workHours: 'Je travaille de nuit',
    workDays: const ['Lundi', 'Mardi'],
    workTimeRanges: [
      TimeRangeModel(
        label: 'Bureau',
        startTime: '09:00',
        endTime: '17:00',
        travelMinutes: '20',
      ),
    ],
    personalActivities: [
      ActivityModel(
        title: 'Yoga',
        location: 'Maison',
        days: const ['Samedi'],
        timeRanges: [
          TimeRangeModel(startTime: '10:00', endTime: '11:00'),
        ],
      ),
    ],
    planningStyle: 'Je préfère planifier l’après-midi',
  );
}
