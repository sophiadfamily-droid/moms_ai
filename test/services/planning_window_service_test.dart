import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/services/planning_window_service.dart';

void main() {
  group('PlanningWindowService', () {
    test('uses the standard window without structured preferences', () {
      final window = PlanningWindowService.build(
        reasoning: const [],
      );

      expect(window.startHour, 8);
      expect(window.endHour, 21);
      expect(window.preferredStartHour, 9);
      expect(window.preferredEndHour, 18);
      expect(window.allowNightHours, false);
      expect(window.avoidMorning, false);
    });

    test('uses the afternoon preference from a structured signal', () {
      final window = PlanningWindowService.build(
        reasoning: const [
          {
            'type': 'schedule_preference',
            'preferredPeriod': 'afternoon',
          },
        ],
      );

      expect(window.startHour, 8);
      expect(window.endHour, 21);
      expect(window.preferredStartHour, 13);
      expect(window.preferredEndHour, 20);
      expect(window.allowNightHours, false);
      expect(window.avoidMorning, false);
    });

    test('avoids mornings only from an explicit constraint', () {
      final window = PlanningWindowService.build(
        reasoning: const [
          {
            'type': 'schedule_constraint',
            'avoidMorning': true,
          },
        ],
      );

      expect(window.startHour, 12);
      expect(window.endHour, 21);
      expect(window.preferredStartHour, 13);
      expect(window.preferredEndHour, 20);
      expect(window.allowNightHours, false);
      expect(window.avoidMorning, true);
    });

    test('opens night hours only from the structured night mode', () {
      final window = PlanningWindowService.build(
        reasoning: const [
          {
            'type': 'schedule_constraint',
            'scheduleMode': 'night',
            'avoidMorning': true,
          },
        ],
      );

      expect(window.startHour, 12);
      expect(window.endHour, 24);
      expect(window.preferredStartHour, 16);
      expect(window.preferredEndHour, 23);
      expect(window.allowNightHours, true);
      expect(window.avoidMorning, true);
    });

    test('uses a late window from the structured late mode', () {
      final window = PlanningWindowService.build(
        reasoning: const [
          {
            'type': 'schedule_constraint',
            'scheduleMode': 'late',
            'avoidMorning': false,
          },
        ],
      );

      expect(window.startHour, 8);
      expect(window.endHour, 23);
      expect(window.preferredStartHour, 14);
      expect(window.preferredEndHour, 22);
      expect(window.allowNightHours, false);
      expect(window.avoidMorning, false);
    });

    test('night mode has priority over late mode', () {
      final window = PlanningWindowService.build(
        reasoning: const [
          {
            'type': 'schedule_constraint',
            'scheduleMode': 'late',
          },
          {
            'type': 'schedule_constraint',
            'scheduleMode': 'night',
            'avoidMorning': true,
          },
        ],
      );

      expect(window.startHour, 12);
      expect(window.endHour, 24);
      expect(window.allowNightHours, true);
      expect(window.avoidMorning, true);
    });

    test('does not infer a night schedule from unrelated text', () {
      final window = PlanningWindowService.build(
        reasoning: const [
          {
            'type': 'blocked_period',
            'label': 'Nuit des musées',
            'notes': 'Sortie prévue le soir',
            'startTime': '18:00',
            'endTime': '20:00',
          },
        ],
      );

      expect(window.startHour, 8);
      expect(window.endHour, 21);
      expect(window.preferredStartHour, 9);
      expect(window.preferredEndHour, 18);
      expect(window.allowNightHours, false);
      expect(window.avoidMorning, false);
    });

    test('does not infer a late schedule from an arbitrary memory source', () {
      final window = PlanningWindowService.build(
        reasoning: const [
          {
            'type': 'routine',
            'source': 'Acheter du lait ce soir',
          },
        ],
      );

      expect(window.startHour, 8);
      expect(window.endHour, 21);
      expect(window.allowNightHours, false);
      expect(window.avoidMorning, false);
    });
  });
}
