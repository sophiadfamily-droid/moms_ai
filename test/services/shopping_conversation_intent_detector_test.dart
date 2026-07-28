import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/services/shopping_conversation_intent_detector.dart';

void main() {
  const detector = ShoppingConversationIntentDetector();

  group('ShoppingConversationIntentDetector positives', () {
    final cases = <String, List<String>>{
      'J’ai plus de bananes': ['bananes'],
      'je n’ai plus de lait': ['lait'],
      'y a plus d’œufs': ['œufs'],
      'il y a plus de lait': ['lait'],
      'on a plus de lait': ['lait'],
      'on n’a plus de lait': ['lait'],
      'on a pu de couches': ['couches'],
      'ya pu de lait': ['lait'],
      'il manque du riz': ['riz'],
      'manque du lait': ['lait'],
      'j’ai fini le lait': ['lait'],
      'on a fini les couches': ['couches'],
      'ajoute du lait aux courses': ['lait'],
      'mets des bananes dans la liste de courses': ['bananes'],
      'jai plus de banane': ['banane'],
      'ya plu de lait': ['lait'],
      'on na plu doeuf': ['œuf'],
      'met du lait dans les course': ['lait'],
    };

    for (final entry in cases.entries) {
      test(entry.key, () {
        expect(
          detector.detect(entry.key)?.items.map((item) => item.title),
          entry.value,
        );
      });
    }
  });

  test('extracts several items once and preserves an explicit quantity', () {
    expect(
      detector
          .detect('Il manque du lait et des œufs')
          ?.items
          .map((item) => item.title),
      ['lait', 'œufs'],
    );
    expect(
      detector
          .detect('J’ai plus de lait ni de bananes')
          ?.items
          .map((item) => item.title),
      ['lait', 'bananes'],
    );
    expect(
      detector
          .detect('Ajoute deux bouteilles de lait aux courses')
          ?.items
          .single
          .title,
      'deux bouteilles de lait',
    );
  });

  group('ShoppingConversationIntentDetector ambiguities', () {
    for (final entry in const {
      'je veux plus de bananes': 'bananes',
      'je veux plus de lait': 'lait',
      'on veut plus de couches': 'couches',
      'il veut plus de pommes': 'pommes',
      'je veu plus de banane': 'banane',
      'jveu plus de lait': 'lait',
    }.entries) {
      test(entry.key, () {
        final classification = detector.classify(entry.key);
        expect(
          classification.kind,
          ShoppingConversationIntentKind.ambiguousMoreOrNoMore,
        );
        expect(classification.items.single.title, entry.value);
        expect(detector.detect(entry.key), isNull);
      });
    }
  });

  group('ShoppingConversationIntentDetector negatives', () {
    for (final input in const [
      'j’ai plus de bananes que toi',
      'je veux plus de bananes',
      'ajoute plus de bananes',
      'achète-en plus',
      'j’ai acheté plus de bananes',
      'explique-moi les bananes',
      'modifie la tâche acheter des bananes',
      'déplace le rendez-vous courses',
      'j’ai acheté des bananes',
      'j’aime les bananes',
      'est-ce que les bananes sont bonnes pour la santé ?',
      'j’ai plus de temps',
      'je n’en veux plus',
      'je ne veux plus de bananes',
    ]) {
      test(input, () => expect(detector.detect(input), isNull));
    }
  });
}
