import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_normalizer.dart';

void main() {
  group('EntityNormalizer', () {
    test('normalizes case, spacing, non-breaking spaces and punctuation', () {
      final value = EntityNormalizer.normalize('  « Primary\u00a0  Place! »  ');

      expect(value.displayValue, 'Primary Place');
      expect(value.normalizedLabel, 'primary place');
      expect(value.comparisonKey, 'primary place');
    });

    test('normalizes apostrophe, dash and invisible variants', () {
      final first = EntityNormalizer.normalize('L’École\u200b–Centre');
      final second = EntityNormalizer.normalize("l'école-centre");

      expect(first.normalizedLabel, "l'école-centre");
      expect(first.comparisonKey, second.comparisonKey);
    });

    test('uses an accent-insensitive comparison key', () {
      expect(
        EntityNormalizer.comparisonKey('École'),
        EntityNormalizer.comparisonKey('ecole'),
      );
      expect(
        EntityNormalizer.comparisonKey('e\u0301cole'),
        EntityNormalizer.comparisonKey('école'),
      );
    });

    test('is idempotent and deterministic', () {
      final first = EntityNormalizer.normalize('  Activity A  ');
      final second = EntityNormalizer.normalize(first.normalizedLabel);

      expect(second.normalizedLabel, first.normalizedLabel);
      expect(second.comparisonKey, first.comparisonKey);
      expect(EntityNormalizer.normalize('Activity A').comparisonKey,
          EntityNormalizer.normalize('Activity A').comparisonKey);
    });

    test('does not translate or remove relational terms', () {
      expect(EntityNormalizer.normalize('mon médecin').normalizedLabel,
          'mon médecin');
      expect(
          EntityNormalizer.normalize('my doctor').normalizedLabel, 'my doctor');
    });

    test('supports an empty value without inventing content', () {
      final value = EntityNormalizer.normalize('  ...  ');

      expect(value.displayValue, isEmpty);
      expect(value.normalizedLabel, isEmpty);
      expect(value.comparisonKey, isEmpty);
    });
  });
}
