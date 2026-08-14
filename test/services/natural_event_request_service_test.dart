import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/services/natural_event_request_service.dart';

void main() {
  group('NaturalEventRequestService', () {
    final now = DateTime(2026, 8, 11, 12);

    test('recognizes general explicit Event requests locally', () {
      final cases = <String, Map<String, String>>{
        'Coiffeur demain à 9h30': {
          'title': 'Rendez-vous Coiffeur',
          'date': '2026-08-12',
          'time': '09:30',
        },
        'Médecin après-demain à 14 heures': {
          'title': 'Rendez-vous Médecin',
          'date': '2026-08-13',
          'time': '14:00',
        },
        'rendez-vous dentiste demain à quatorze heures': {
          'title': 'Rendez-vous dentiste',
          'date': '2026-08-12',
          'time': '14:00',
        },
        'Consultation banque le 18 août 2026 à 16h45': {
          'title': 'Consultation banque',
          'date': '2026-08-18',
          'time': '16:45',
        },
      };

      for (final entry in cases.entries) {
        final action = NaturalEventRequestService.parseAction(
          entry.key,
          now: now,
        );
        expect(action, isNotNull, reason: entry.key);
        expect(action!['type'], 'event', reason: entry.key);
        expect(action['title'], entry.value['title'], reason: entry.key);
        expect(action['date'], entry.value['date'], reason: entry.key);
        expect(action['time'], entry.value['time'], reason: entry.key);
      }
    });

    test('keeps a generic appointment title for the motif question', () {
      final action = NaturalEventRequestService.parseAction(
        'rdv demain 14heur',
        now: now,
      );

      expect(action, isNotNull);
      expect(action!['title'], 'Rendez-vous');
      expect(action['date'], '2026-08-12');
      expect(action['time'], '14:00');
    });

    test('separates an explicit place from the appointment motif', () {
      final action = NaturalEventRequestService.parseAction(
        'Dentiste demain à 9h30 au 45 avenue Pasteur, Tremblay-en-France',
        now: now,
      );

      expect(action, isNotNull);
      expect(action!['title'], 'Rendez-vous Dentiste');
      expect(action['date'], '2026-08-12');
      expect(action['time'], '09:30');
      expect(action['location'], '45 avenue Pasteur, Tremblay-en-France');
    });

    test('recognizes bounded spelling and dictation variants generally', () {
      final cases = <String, Map<String, String>>{
        'rendezvous dentiste dem1 a quatorze hure': {
          'title': 'Rendez-vous dentiste',
          'date': '2026-08-12',
          'time': '14:00',
        },
        'Coiffeur dmain 15:30': {
          'title': 'Rendez-vous Coiffeur',
          'date': '2026-08-12',
          'time': '15:30',
        },
      };

      for (final entry in cases.entries) {
        final action = NaturalEventRequestService.parseAction(
          entry.key,
          now: now,
        );
        expect(action, isNotNull, reason: entry.key);
        expect(action!['title'], entry.value['title'], reason: entry.key);
        expect(action['date'], entry.value['date'], reason: entry.key);
        expect(action['time'], entry.value['time'], reason: entry.key);
      }
    });

    test('does not intercept questions, mutations, tasks or routines', () {
      final messages = [
        'Quand est mon coiffeur demain à 9h30 ?',
        'Déplace mon coiffeur demain à 9h30',
        'Rappelle-moi le dentiste demain à 9h30',
        'Pilates chaque mercredi à 9h30',
        'Ajoute du lait demain à 9h30',
        'Un rendez-vous demain',
      ];

      for (final message in messages) {
        expect(
          NaturalEventRequestService.parseAction(message, now: now),
          isNull,
          reason: message,
        );
      }
    });
  });
}
