import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/natural_language_models.dart';
import 'package:moms_ai/services/natural_language_understanding_service.dart';

void main() {
  final reference = DateTime(2026, 7, 29);

  test('extracts dictated French clock forms as structured entities', () {
    for (final entry in <String, String>{
      'neuf heure': '09:00',
      'neuf heures trente': '09:30',
      'neuf heure et demie': '09:30',
    }.entries) {
      final result = NaturalLanguageUnderstandingService.parse(
        'médecin demain ${entry.key}',
        now: reference,
      );
      expect(result.time, entry.value, reason: entry.key);
      expect(result.entities.map((entity) => entity.type), contains('time'));
      expect(result.originalText, contains(entry.key));
    }
  });

  test('extracts date and time after bounded SMS and dictation variants', () {
    final cases = <String, (String, String)>{
      'rdv dem1 14 hure': ('2026-07-30', '14:00'),
      'rendezvous dmain quatorze heurs trente': ('2026-07-30', '14:30'),
      'médecin ajd 9h': ('2026-07-29', '09:00'),
      'dentiste apresdemain quinze heure': ('2026-07-31', '15:00'),
    };

    for (final entry in cases.entries) {
      final result = NaturalLanguageUnderstandingService.parse(
        entry.key,
        now: reference,
      );
      expect(result.dateIso, entry.value.$1, reason: entry.key);
      expect(result.time, entry.value.$2, reason: entry.key);
      expect(result.hasDuration, isFalse, reason: entry.key);
    }
  });

  test('keeps colon clock forms after shared normalization', () {
    final result = NaturalLanguageUnderstandingService.parse(
      'dentiste dem1 15:30',
      now: reference,
    );

    expect(result.dateIso, '2026-07-30');
    expect(result.time, '15:30');
    expect(result.hasDuration, isFalse);
  });

  test('understanding is fail closed when normalization preserves ambiguity',
      () {
    for (final text in <String>[
      'je veux plus de bananes demain',
      'annule pas le rendez-vous demain',
      'achète du lait et décale le rendez-vous demain',
      'mets-le demain',
    ]) {
      final result = NaturalLanguageUnderstandingService.parse(
        text,
        now: reference,
      );
      expect(
        result.understandingLevel,
        UnderstandingLevel.ambiguous,
        reason: text,
      );
    }
  });

  test('empty and bounded noisy input never invent entities', () {
    for (final text in <String>[
      '',
      '   ',
      'euh euh enfin bon',
      'hello, peux-tu expliquer ? 🙂',
      List<String>.filled(1000, 'blabla').join(' '),
    ]) {
      final result = NaturalLanguageUnderstandingService.parse(
        text,
        now: reference,
      );
      expect(result.hasDate, isFalse, reason: text.length.toString());
      expect(result.hasTime, isFalse, reason: text.length.toString());
      expect(result.hasDuration, isFalse, reason: text.length.toString());
    }
  });

  test('relative life-context phrases never invent a universal clock time', () {
    for (final text in <String>[
      "après l'école",
      'avant de partir',
      'après le travail',
    ]) {
      final result = NaturalLanguageUnderstandingService.parse(
        text,
        now: reference,
      );
      expect(result.hasTime, isFalse, reason: text);
    }
  });

  test('a clock occurrence is never reused as a duration', () {
    for (final text in <String>[
      'médecin demain 15h',
      'rdv demain 15heur',
      'médecin demain 15 heures',
      '23h',
    ]) {
      final result = NaturalLanguageUnderstandingService.parse(
        text,
        now: reference,
      );
      expect(result.hasTime, isTrue, reason: text);
      expect(result.hasDuration, isFalse, reason: text);
      expect(result.durationMinutes, 0, reason: text);
    }
  });

  test('keeps distinct time and explicit duration entities', () {
    for (final entry in <String, int>{
      'médecin demain 15h durée 1h': 60,
      'médecin demain à 15h pendant 45 minutes': 45,
    }.entries) {
      final result = NaturalLanguageUnderstandingService.parse(
        entry.key,
        now: reference,
      );
      expect(result.time, '15:00', reason: entry.key);
      expect(result.durationMinutes, entry.value, reason: entry.key);
    }
  });
}
