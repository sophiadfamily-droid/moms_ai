import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/natural_language_models.dart';
import 'package:moms_ai/services/conversation_answer_classifier.dart';
import 'package:moms_ai/services/natural_language_normalizer.dart';

void main() {
  const normalizer = NaturalLanguageNormalizer();

  test('preserves original text and applies only bounded corrections', () {
    const original = '  AJOUTR un rdv demian à neuf heure stp ! ';
    final result = normalizer.normalize(original);

    expect(result.originalText, original);
    expect(
      result.normalizedText,
      'ajouter un rendez vous demain a 09:00 s il te plait',
    );
    expect(
      result.normalizationCodes,
      containsAll(<String>[
        'trimmed',
        'lowercased',
        'accents_folded',
        'oral_form_normalized',
        'safe_typo_corrected',
      ]),
    );
  });

  test('never removes critical negation', () {
    for (final text in <String>[
      'je ne veux plus de bananes',
      'annule pas le rendez-vous',
      'ne crée pas de tâche',
      'rappelle-moi de ne pas oublier',
      'je veux pas le supprimer',
    ]) {
      final result = normalizer.normalize(text);
      expect(
        NaturalLanguageNormalizer.hasNegation(text),
        isTrue,
        reason: text,
      );
      expect(
        result.normalizationCodes,
        contains('negation_preserved'),
        reason: text,
      );
    }
  });

  test('preserves both possible meanings of plus', () {
    for (final text in <String>[
      'je veux plus de bananes',
      "j'ai plus de bananes",
      'ajoute plus de bananes',
    ]) {
      expect(
        normalizer.normalize(text).preservedAmbiguities,
        isNotEmpty,
        reason: text,
      );
    }
  });

  test('confirmation classifier accepts simple oral answers only', () {
    const classifier = ConversationAnswerClassifier();
    for (final answer in <String>['ouais', 'yep', "d'accord", 'vas-y']) {
      expect(classifier.classify(answer), ConversationAnswer.positive);
    }
    for (final answer in <String>['nan', 'laisse tomber']) {
      expect(classifier.classify(answer), ConversationAnswer.negative);
    }
    for (final answer in <String>[
      'oui mais demain',
      'non plutôt mardi',
      'peut-être',
    ]) {
      expect(classifier.classify(answer), ConversationAnswer.ambiguous);
    }
  });

  test('understanding and entity confidence are closed enums', () {
    expect(UnderstandingLevel.values.map((value) => value.name), <String>[
      'exactMatch',
      'normalizedMatch',
      'probableMatch',
      'ambiguous',
      'noMatch',
    ]);
    expect(EntityUnderstanding.values.length, 4);
  });

  test('matches the shared Flutter and Node contract fixtures', () {
    final cases = jsonDecode(
      File('test/fixtures/nlu_contract_cases.json').readAsStringSync(),
    ) as List<dynamic>;
    for (final rawCase in cases) {
      final item = Map<String, dynamic>.from(rawCase as Map);
      final result = normalizer.normalize(item['raw'] as String);
      expect(result.normalizedText, item['normalized'], reason: item['raw']);
      expect(
        result.preservedAmbiguities,
        List<String>.from(item['ambiguities'] as List),
        reason: item['raw'],
      );
    }
  });
}
