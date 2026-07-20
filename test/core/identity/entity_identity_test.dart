import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_identity.dart';

void main() {
  group('EntityIdentity', () {
    test('rejects absent and blank IDs', () {
      expect(EntityIdentity.isValid(null), isFalse);
      expect(EntityIdentity.isValid(''), isFalse);
      expect(EntityIdentity.isValid('   '), isFalse);
      expect(EntityIdentity.isValid('\t\n\r'), isFalse);
    });

    test('accepts an ID containing a non-whitespace character', () {
      expect(EntityIdentity.isValid('entity-1'), isTrue);
      expect(EntityIdentity.isValid('  entity-1  '), isTrue);
    });

    test('does not transform the ID', () {
      const id = '  entity-1  ';

      expect(EntityIdentity.isValid(id), isTrue);
      expect(id, '  entity-1  ');
    });
  });
}
