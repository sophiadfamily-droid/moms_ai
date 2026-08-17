import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/memory_evidence.dart';
import 'package:moms_ai/services/memory_evidence_classifier.dart';

void main() {
  const classifier = MemoryEvidenceClassifier();

  group('direct evidence', () {
    for (final message in const [
      'Je préfère mes rendez-vous le matin.',
      'Souviens-toi que j’aime préparer mes affaires la veille.',
      'Je ne suis jamais disponible le mardi après 18 h.',
      'Tous les mercredis, je vais au sport de 9 h à 10 h.',
      'Mon bureau actuel est à Lyon.',
    ]) {
      test(message, () {
        final result = classifier.classify(message);

        expect(
            result.classification, MemoryEvidenceClassification.directExplicit);
        expect(result.subjectType, MemoryEvidenceSubjectType.user);
        expect(result.canConfirmImmediately, isTrue);
      });
    }
  });

  group('ambiguous evidence', () {
    for (final message in const [
      'Peut-être que je préfère le matin.',
      'Je crois que je préfère le matin.',
      'Il est possible que je préfère le matin.',
      'Je ne crois pas que je préfère le matin.',
      'Je pense que, peut-être, je préfère le matin.',
      'Normalement, je préfère le matin.',
      'Je préfère probablement le matin.',
      'Je ne sais pas si je préfère le matin.',
      'À mon avis je préfère le matin.',
      'J’ai l’impression que je préfère le matin.',
      'En principe je préfère le matin.',
      'Sans doute je préfère le matin.',
    ]) {
      test(message, () {
        final result = classifier.classify(message);

        expect(result.classification, MemoryEvidenceClassification.ambiguous);
        expect(result.canConfirmImmediately, isFalse);
      });
    }
  });

  group('conditional evidence', () {
    for (final message in const [
      'Si je devais choisir, je préférerais le matin.',
      'Je préférerais le matin.',
      'Je pourrais préférer le matin.',
    ]) {
      test(message, () {
        final result = classifier.classify(message);

        expect(result.classification, MemoryEvidenceClassification.conditional);
        expect(result.canConfirmImmediately, isFalse);
      });
    }
  });

  test('an explicit hypothesis remains non-confirmable', () {
    for (final message in const [
      'Imaginons que je préfère le matin.',
      'Il se peut que je préfère le matin.',
    ]) {
      final result = classifier.classify(message);

      expect(result.classification, MemoryEvidenceClassification.hypothetical);
      expect(result.canConfirmImmediately, isFalse);
    }
  });

  group('past and temporary evidence', () {
    final cases = {
      'Avant je préférais le matin.': MemoryEvidenceClassification.pastState,
      "Quand j'habitais ailleurs, je préférais le matin.":
          MemoryEvidenceClassification.pastState,
      'Pour cette semaine seulement, je préfère le matin.':
          MemoryEvidenceClassification.temporary,
      "Aujourd'hui exceptionnellement, je préfère le matin.":
          MemoryEvidenceClassification.temporary,
    };
    for (final entry in cases.entries) {
      test(entry.key, () {
        final result = classifier.classify(entry.key);

        expect(result.classification, entry.value);
        expect(result.canConfirmImmediately, isFalse);
      });
    }
  });

  group('quotations and subject attribution', () {
    test('quoted content is not attributed to the account', () {
      final result = classifier.classify(
        '« Je préfère le matin », c’est ce que j’avais écrit.',
      );

      expect(result.classification, MemoryEvidenceClassification.quoted);
      expect(result.canConfirmImmediately, isFalse);
    });

    for (final message in const [
      'Il dit que je préfère le matin.',
      'Ma sœur pense que je préfère le matin.',
      'Elle préfère le matin.',
      'Ma sœur préfère le matin.',
    ]) {
      test(message, () {
        final result = classifier.classify(message);

        expect(result.classification, MemoryEvidenceClassification.thirdParty);
        expect(result.canConfirmImmediately, isFalse);
      });
    }

    test('a resolved structured entity is attributable', () {
      final result = classifier.classify(
        'Ma sœur préfère le matin.',
        resolvedSubjectEntityId: 'person-42',
      );

      expect(
          result.classification, MemoryEvidenceClassification.directExplicit);
      expect(result.subjectType, MemoryEvidenceSubjectType.structuredEntity);
      expect(result.subjectEntityId, 'person-42');
      expect(result.canConfirmImmediately, isTrue);
    });
  });

  group('questions and negations', () {
    test('question is not immediately confirmable', () {
      final result = classifier.classify(
        'Est-ce que je préfère le matin ?',
      );

      expect(result.classification, MemoryEvidenceClassification.question);
      expect(result.canConfirmImmediately, isFalse);
    });

    for (final message in const [
      'À quel moment de ma journée je préfère faire mes activités',
      'Quelle activité est-ce que je préfère',
      'Quels sont mes rendez-vous habituels',
      'Combien de temps je préfère prévoir',
      'Peux-tu me dire ce que je préfère',
      'Dis-moi quand je préfère faire du sport',
    ]) {
      test('question française sans ponctuation: $message', () {
        final result = classifier.classify(message);

        expect(result.classification, MemoryEvidenceClassification.question);
        expect(result.canConfirmImmediately, isFalse);
      });
    }

    for (final message in const [
      'Je ne préfère pas le matin.',
      'Ce n’est pas vrai que je préfère le matin.',
    ]) {
      test(message, () {
        final result = classifier.classify(message);

        expect(result.classification, MemoryEvidenceClassification.negated);
        expect(result.canConfirmImmediately, isFalse);
      });
    }

    for (final message in const [
      'Je ne peux jamais le mardi après 18 h.',
      'Je ne suis jamais disponible le mardi après 18 h.',
      'Je suis indisponible tous les mardis après 18 h.',
    ]) {
      test('durable constraint: $message', () {
        final result = classifier.classify(message);

        expect(
            result.classification, MemoryEvidenceClassification.directExplicit);
        expect(result.risks, contains(MemoryEvidenceRisk.negation));
        expect(result.canConfirmImmediately, isTrue);
      });
    }
  });

  group('corrections', () {
    for (final message in const [
      'Finalement, je préfère l’après-midi.',
      'En fait, mon bureau actuel est à Lyon.',
      'Je me suis trompée, ce n’est plus mon adresse.',
      'Correction : l’anniversaire de ma mère est le 12 mars.',
    ]) {
      test(message, () {
        final result = classifier.classify(message);

        expect(result.classification, MemoryEvidenceClassification.correction);
        expect(result.isCorrection, isTrue);
        expect(result.canConfirmImmediately, isTrue);
      });
    }

    final composed = {
      'Avant je préférais le matin, mais maintenant je préfère l’après-midi.':
          'je préfère l’après-midi.',
      'Avant je travaillais le mercredi, mais désormais je ne travaille plus '
          'le mercredi.': 'je ne travaille plus le mercredi.',
      'Quand j’habitais ailleurs je préférais le soir, mais aujourd’hui je '
          'préfère le matin.': 'je préfère le matin.',
      'Je me suis trompée, maintenant je travaille le mercredi.':
          'je travaille le mercredi.',
      'Ce n’est plus vrai, je ne travaille plus le mercredi.':
          'je ne travaille plus le mercredi.',
    };
    for (final entry in composed.entries) {
      test('composed correction: ${entry.key}', () {
        final result = classifier.classify(entry.key);

        expect(result.classification, MemoryEvidenceClassification.correction);
        expect(result.isCorrection, isTrue);
        expect(result.canConfirmImmediately, isTrue);
        expect(result.statementForMemory?.toLowerCase(), entry.value);
      });
    }

    test('an uncertain current value remains a proposed correction', () {
      final result = classifier.classify(
        'Avant je préférais le matin, mais maintenant je crois que je préfère '
        'l’après-midi.',
      );

      expect(result.classification, MemoryEvidenceClassification.ambiguous);
      expect(result.isCorrection, isTrue);
      expect(result.canConfirmImmediately, isFalse);
    });
  });

  test('a family birthday is an attributable durable fact', () {
    final result = classifier.classify(
      'L’anniversaire de ma mère est le 12 mars.',
    );

    expect(result.classification, MemoryEvidenceClassification.directExplicit);
    expect(result.subjectType, MemoryEvidenceSubjectType.user);
    expect(result.canConfirmImmediately, isTrue);
  });

  group('fail-closed fallback', () {
    for (final message in const [
      'Je mange parfois tôt.',
      'Je raconte.',
      'Je',
      '',
    ]) {
      test(message.isEmpty ? 'empty statement' : message, () {
        final result = classifier.classify(message);

        expect(result.classification, MemoryEvidenceClassification.unknown);
        expect(result.canConfirmImmediately, isFalse);
      });
    }
  });

  test('assistant candidate is always non-confirmable without private data',
      () {
    final result = classifier.assistantCandidate();

    expect(result.classification, MemoryEvidenceClassification.unknown);
    expect(result.canConfirmImmediately, isFalse);
    expect(result.reasonCodes, ['assistant_candidate']);
    expect(result.reasonCodes.join(), isNot(contains('secret')));
  });
}
