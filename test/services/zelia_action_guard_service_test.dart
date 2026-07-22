import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/services/zelia_action_guard_service.dart';

void main() {
  group('ZeliaActionGuardService', () {
    test('rejects non-map actions', () {
      final result = ZeliaActionGuardService.guard('invalid');

      expect(result.isAccepted, false);
      expect(result.rejectionReason, 'invalid_action_object');
    });

    test('rejects unsupported action types', () {
      final result = ZeliaActionGuardService.guard({
        'type': 'delete_everything',
        'title': 'Tout supprimer',
      });

      expect(result.isAccepted, false);
      expect(result.rejectionReason, 'unsupported_action_type');
    });

    test('rejects empty titles', () {
      final result = ZeliaActionGuardService.guard({
        'type': 'task',
        'title': '   ',
      });

      expect(result.isAccepted, false);
      expect(result.rejectionReason, 'empty_action_title');
    });

    test('normalizes task aliases and safe defaults', () {
      final result = ZeliaActionGuardService.guard({
        'type': 'to-do',
        'title': '  Appeler   le médecin  ',
        'planning': '',
        'priority': '',
      });

      expect(result.isAccepted, true);
      expect(result.action!['type'], 'task');
      expect(result.action!['title'], 'Appeler le médecin');
      expect(result.action!['planning'], 'Cette semaine');
      expect(result.action!['priority'], 'Normale');
    });

    test('clears invalid event values instead of inventing them', () {
      final result = ZeliaActionGuardService.guard({
        'type': 'event',
        'title': 'Médecin',
        'date': 'demain',
        'time': '38:75',
        'durationMinutes': 100000,
        'travelGoMinutes': -20,
        'travelBackMinutes': 9000,
        'marginMinutes': 5000,
      });

      expect(result.isAccepted, true);
      expect(result.action!['date'], '');
      expect(result.action!['time'], '');
      expect(result.action!['durationMinutes'], 0);
      expect(result.action!['needsDuration'], true);
      expect(result.action!['travelGoMinutes'], 0);
      expect(result.action!['travelBackMinutes'], 0);
      expect(result.action!['marginMinutes'], 0);
    });

    test('normalizes valid event time and separate travel', () {
      final result = ZeliaActionGuardService.guard({
        'type': 'event',
        'title': 'Dentiste',
        'date': '2026-07-20',
        'time': '9h5',
        'durationMinutes': 45,
        'travelGoMinutes': 15,
        'travelBackMinutes': 30,
        'usesSeparateTravelTimes': true,
      });

      expect(result.isAccepted, true);
      expect(result.action!['date'], '2026-07-20');
      expect(result.action!['time'], '09:05');
      expect(result.action!['durationMinutes'], 45);
      expect(result.action!['needsDuration'], false);
      expect(result.action!['travelMinutes'], 45);
      expect(result.action!['usesSeparateTravelTimes'], true);
    });

    test('resets incoherent recurrence', () {
      final result = ZeliaActionGuardService.guard({
        'type': 'event',
        'title': 'Cours',
        'isRecurring': true,
        'recurringType': 'weekly',
        'recurringWeekday': 12,
      });

      expect(result.isAccepted, true);
      expect(result.action!['isRecurring'], false);
      expect(result.action!['recurringType'], '');
      expect(result.action!['recurringWeekday'], 0);
    });

    test('keeps a valid weekly recurrence', () {
      final result = ZeliaActionGuardService.guard({
        'type': 'event',
        'title': 'Football',
        'isRecurring': true,
        'recurringWeekday': 3,
      });

      expect(result.isAccepted, true);
      expect(result.action!['isRecurring'], true);
      expect(result.action!['recurringType'], 'weekly');
      expect(result.action!['recurringWeekday'], 3);
    });

    test('accepts only a closed typed event mutation', () {
      final result = ZeliaActionGuardService.guard({
        'type': 'event_mutation',
        'operation': 'update',
        'target': {'title': 'Médecin', 'date': '2026-07-23'},
        'changes': {'time': '11:00'},
      });
      expect(result.isAccepted, true);
      expect(result.action!['type'], 'event_mutation');
      expect(result.action!['eventMutation'], isNotNull);
      expect(result.action, isNot(contains('id')));
    });

    test('rejects empty, unknown and forbidden event mutations', () {
      for (final action in [
        {
          'type': 'event_mutation',
          'operation': 'delete',
          'target': {'title': 'Médecin'},
          'changes': {'time': '11:00'},
        },
        {
          'type': 'event_mutation',
          'operation': 'update',
          'target': <String, dynamic>{},
          'changes': {'time': '11:00'},
        },
        {
          'type': 'event_mutation',
          'operation': 'update',
          'target': {'id': 'event-1'},
          'changes': {'participantIdentity': 'forbidden'},
        },
      ]) {
        expect(ZeliaActionGuardService.guard(action).isAccepted, false);
      }
    });

    test('removes event-only fields from shopping actions', () {
      final result = ZeliaActionGuardService.guard({
        'type': 'shopping',
        'title': 'Lait',
        'time': '14:00',
        'durationMinutes': 60,
        'travelGoMinutes': 20,
        'section': '',
      });

      expect(result.isAccepted, true);
      expect(result.action!['time'], '');
      expect(result.action!['durationMinutes'], 0);
      expect(result.action!['travelGoMinutes'], 0);
      expect(result.action!['section'], 'Aujourd’hui');
    });
  });
}
