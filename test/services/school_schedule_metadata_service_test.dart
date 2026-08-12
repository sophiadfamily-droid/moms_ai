import 'package:flutter_test/flutter_test.dart';

import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/services/profile_reasoning_service.dart';
import 'package:moms_ai/services/school_schedule_metadata_service.dart';
import 'package:moms_ai/services/smart_planning_service.dart';

void main() {
  group('SchoolScheduleMetadataService', () {
    test('decodes school days and preserves human notes', () {
      final range = TimeRangeModel(
        startTime: '08:30',
        endTime: '11:50',
        travelMinutes: '15',
        notes: '__DAYS__:Lundi|Mardi|Jeudi|Vendredi__ Déposer Kassim à l’école',
      );

      expect(
        SchoolScheduleMetadataService.daysFromRange(range),
        ['Lundi', 'Mardi', 'Jeudi', 'Vendredi'],
      );

      expect(
        SchoolScheduleMetadataService.cleanNotes(range),
        'Déposer Kassim à l’école',
      );
    });

    test('encodes days without losing existing notes', () {
      final encoded = SchoolScheduleMetadataService.encodeNotes(
        days: ['Lundi', 'Mercredi'],
        notes: 'Sortie à midi',
      );

      expect(
        encoded,
        '__DAYS__:Lundi|Mercredi__ Sortie à midi',
      );
    });

    test('keeps legacy ranges compatible', () {
      final range = TimeRangeModel(
        startTime: '08:30',
        endTime: '11:50',
        notes: 'Ancienne plage scolaire',
      );

      expect(
        SchoolScheduleMetadataService.daysFromRange(range),
        isEmpty,
      );

      expect(
        SchoolScheduleMetadataService.cleanNotes(range),
        'Ancienne plage scolaire',
      );
    });
  });

  group('ProfileReasoningService school schedule', () {
    UserProfile buildProfile() {
      return UserProfile(
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
                label: 'École matin',
                startTime: '08:30',
                endTime: '11:50',
                travelMinutes: '15',
                notes:
                    '__DAYS__:Lundi|Mardi|Jeudi|Vendredi__ Horaires scolaires',
              ),
            ],
          ),
        ],
      );
    }

    test('keeps school days as other-person context', () {
      final reasoning = ProfileReasoningService.buildReasoning(
        buildProfile(),
      );

      final schoolPeriod = reasoning.firstWhere(
        (item) => item['sourceType'] == 'child_school',
      );

      expect(
        schoolPeriod['days'],
        ['Lundi', 'Mardi', 'Jeudi', 'Vendredi'],
      );
      expect(schoolPeriod['notes'], 'Horaires scolaires');
      expect(schoolPeriod['travelBeforeMinutes'], 15);
      expect(schoolPeriod['travelAfterMinutes'], 15);
      expect(schoolPeriod['type'], 'other_person_commitment');
      expect(schoolPeriod['blocksPrimaryUser'], isFalse);
    });

    test('does not block the primary user during Monday school hours', () {
      final reasoning = ProfileReasoningService.buildReasoning(
        buildProfile(),
      );

      expect(
        SmartPlanningService.overlapsBlockedReasoning(
          start: DateTime(2026, 7, 20, 8, 20),
          end: DateTime(2026, 7, 20, 8, 40),
          reasoning: reasoning,
        ),
        false,
      );
    });

    test('does not block Wednesday', () {
      final reasoning = ProfileReasoningService.buildReasoning(
        buildProfile(),
      );

      expect(
        SmartPlanningService.overlapsBlockedReasoning(
          start: DateTime(2026, 7, 22, 9),
          end: DateTime(2026, 7, 22, 10),
          reasoning: reasoning,
        ),
        false,
      );
    });

    test('does not block Saturday', () {
      final reasoning = ProfileReasoningService.buildReasoning(
        buildProfile(),
      );

      expect(
        SmartPlanningService.overlapsBlockedReasoning(
          start: DateTime(2026, 7, 25, 9),
          end: DateTime(2026, 7, 25, 10),
          reasoning: reasoning,
        ),
        false,
      );
    });
  });
}
