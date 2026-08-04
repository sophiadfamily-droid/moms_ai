import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/services/natural_time_service.dart';

void main() {
  test('parses initial and conflict alternative clock times', () {
    for (final entry in <String, String>{
      'médecin demain 15h': '15:00',
      'rdv demain 15 h': '15:00',
      'rdv demain 15heur': '15:00',
      'rdv demain 15heure': '15:00',
      'rdv demain 15heures': '15:00',
      'rdv demain 15 heure': '15:00',
      'médecin demain 15 heures': '15:00',
      'rdv demain 15hr': '15:00',
      'rdv demain 15 hrs': '15:00',
      'rdv demain 15h30': '15:30',
      'rdv demain 15 heure 30': '15:30',
      'rdv demain 15 heures et quart': '15:15',
      'rdv demain 15h et demie': '15:30',
      'rdv demain 15:30': '15:30',
      'rdv demain 15 : 30': '15:30',
      'rdv demain quinzeh': '15:00',
      'rdv demain quinze heur': '15:00',
      'rdv demain quinze heures': '15:00',
      'rdv demain quinze heures et quart': '15:15',
      'plutôt 19 heures': '19:00',
      '23h': '23:00',
    }.entries) {
      expect(NaturalTimeService.parseTime(entry.key), entry.value,
          reason: entry.key);
    }
  });

  test('rejects invalid clock values despite tolerant transcription', () {
    for (final text in <String>['24h', '15h75', '99 heures', '25:00']) {
      expect(NaturalTimeService.parseTime(text), isEmpty, reason: text);
    }
  });

  test('accepts every valid numeric hour with dictated unit variants', () {
    for (var hour = 0; hour <= 23; hour++) {
      for (final unit in <String>['h', 'heur', 'heure', 'heures']) {
        expect(
          NaturalTimeService.parseTime('rdv demain $hour$unit'),
          '${hour.toString().padLeft(2, '0')}:00',
          reason: '$hour$unit',
        );
      }
    }
  });
}
