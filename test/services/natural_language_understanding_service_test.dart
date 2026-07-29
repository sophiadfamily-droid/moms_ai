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
}
