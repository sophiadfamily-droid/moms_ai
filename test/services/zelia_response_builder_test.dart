import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/services/zelia_response_builder.dart';

void main() {
  group('ZeliaResponseBuilder.eventCreated', () {
    test('describes outbound and return travel separately', () {
      final message = ZeliaResponseBuilder.eventCreated(
        title: 'Médecin',
        date: '2026-07-20',
        time: '14:00',
        durationMinutes: 45,
        travelGoMinutes: 15,
        travelBackMinutes: 30,
        marginMinutes: 10,
        isRecurring: false,
      );

      expect(message, contains('Médecin'));
      expect(message, contains('20/07/2026'));
      expect(message, contains('14:00'));
      expect(message, contains('Durée du rendez-vous : 45 min.'));
      expect(message, contains('Trajet aller prévu : 15 min.'));
      expect(message, contains('Trajet retour prévu : 30 min.'));
      expect(message, contains('Marge de sécurité prévue : 10 min.'));

      expect(
        message,
        isNot(contains('45 minutes de trajet aller')),
      );
    });

    test('preserves an explicit zero return travel in the wording', () {
      final message = ZeliaResponseBuilder.eventCreated(
        title: 'Dentiste',
        date: '2026-07-21',
        time: '09:30',
        durationMinutes: 45,
        travelGoMinutes: 20,
        travelBackMinutes: 0,
        marginMinutes: 5,
        isRecurring: false,
      );

      expect(message, contains('Trajet aller prévu : 20 min.'));
      expect(message, isNot(contains('Trajet retour prévu')));
      expect(message, contains('Marge de sécurité prévue : 5 min.'));
    });

    test('omits travel and margin lines when all values are zero', () {
      final message = ZeliaResponseBuilder.eventCreated(
        title: 'Appel',
        date: '2026-07-22',
        time: '10:30',
        durationMinutes: 20,
        travelGoMinutes: 0,
        travelBackMinutes: 0,
        marginMinutes: 0,
        isRecurring: false,
      );

      expect(message, contains('Durée du rendez-vous : 20 min.'));
      expect(message, isNot(contains('Trajet aller prévu')));
      expect(message, isNot(contains('Trajet retour prévu')));
      expect(message, isNot(contains('Marge de sécurité prévue')));
    });

    test('mentions weekly recurrence', () {
      final message = ZeliaResponseBuilder.eventCreated(
        title: 'Football',
        date: '2026-07-22',
        time: '10:00',
        durationMinutes: 60,
        travelGoMinutes: 10,
        travelBackMinutes: 10,
        marginMinutes: 0,
        isRecurring: true,
      );

      expect(
        message,
        contains('C’est ajouté à ton agenda chaque semaine'),
      );
    });
  });
}
