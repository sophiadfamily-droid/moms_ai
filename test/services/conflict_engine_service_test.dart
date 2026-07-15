import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/services/conflict_engine_service.dart';

void main() {
  group('ConflictEngineService.buildRescheduledAction', () {
    test('preserves stable event information and applies the new time', () {
      final result = ConflictEngineService.buildRescheduledAction(
        pendingAction: {
          'type': 'event',
          'title': 'Médecin',
          'date': '2026-07-20',
          'time': '',
          'category': 'Santé',
          'notes': 'Contrôle annuel',
          'isRecurring': true,
          'recurringType': 'weekly',
          'recurringWeekday': 1,
        },
        time: ' 15:30 ',
      );

      expect(result['type'], 'event');
      expect(result['title'], 'Médecin');
      expect(result['date'], '2026-07-20');
      expect(result['time'], '15:30');
      expect(result['category'], 'Santé');
      expect(result['notes'], 'Contrôle annuel');
      expect(result['isRecurring'], true);
      expect(result['recurringType'], 'weekly');
      expect(result['recurringWeekday'], 1);
    });

    test('resets duration so the existing flow asks for it again', () {
      final result = ConflictEngineService.buildRescheduledAction(
        pendingAction: {
          'type': 'event',
          'title': 'Dentiste',
          'durationMinutes': 45,
          'needsDuration': false,
        },
        time: '11:00',
      );

      expect(result['durationMinutes'], 0);
      expect(result['needsDuration'], true);
    });

    test('clears every legacy and separate travel field atomically', () {
      final result = ConflictEngineService.buildRescheduledAction(
        pendingAction: {
          'type': 'event',
          'title': 'Dentiste',
          'travelMinutes': 45,
          'travelGoMinutes': 15,
          'travelBackMinutes': 30,
          'usesSeparateTravelTimes': true,
          'marginMinutes': 10,
          'departureContext': 'home',
          'arrivalContext': 'school',
          'travelStep': 'travelBack',
        },
        time: '16:00',
      );

      expect(result['travelMinutes'], 0);
      expect(result['travelGoMinutes'], 0);
      expect(result['travelBackMinutes'], 0);
      expect(result['usesSeparateTravelTimes'], false);
      expect(result['marginMinutes'], 0);
      expect(result['departureContext'], 'unknown');
      expect(result['arrivalContext'], 'unknown');
      expect(result.containsKey('travelStep'), false);
    });

    test('does not mutate the original pending action', () {
      final pending = <String, dynamic>{
        'type': 'event',
        'title': 'Médecin',
        'time': '',
        'durationMinutes': 60,
        'travelGoMinutes': 20,
        'travelBackMinutes': 25,
        'usesSeparateTravelTimes': true,
        'marginMinutes': 10,
      };

      final result = ConflictEngineService.buildRescheduledAction(
        pendingAction: pending,
        time: '14:00',
      );

      expect(result, isNot(same(pending)));
      expect(pending['time'], '');
      expect(pending['durationMinutes'], 60);
      expect(pending['travelGoMinutes'], 20);
      expect(pending['travelBackMinutes'], 25);
      expect(pending['usesSeparateTravelTimes'], true);
      expect(pending['marginMinutes'], 10);
    });
  });
}
