import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_id_generator.dart';
import 'package:moms_ai/core/identity/uuid_v7_entity_id_generator.dart';

import '../../fakes/fake_entity_id_generator.dart';

void main() {
  group('UuidV7EntityIdGenerator', () {
    const uuidV7Pattern =
        r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$';

    test('generates distinct non-empty Firestore-compatible UUID v7 IDs', () {
      const EntityIdGenerator generator = UuidV7EntityIdGenerator();

      final first = generator.generate();
      final second = generator.generate();

      expect(first, isNotEmpty);
      expect(second, isNot(equals(first)));
      expect(first, isNot(contains('/')));
      expect(second, isNot(contains('/')));
      expect(first, matches(RegExp(uuidV7Pattern)));
      expect(second, matches(RegExp(uuidV7Pattern)));
    });
  });

  group('FakeEntityIdGenerator', () {
    test('returns configured IDs in order and exposes its call count', () {
      final generator = FakeEntityIdGenerator(['entity-1', 'entity-2']);

      expect(generator.generate(), 'entity-1');
      expect(generator.callCount, 1);
      expect(generator.generate(), 'entity-2');
      expect(generator.callCount, 2);
    });

    test('can provide a repeated value for collision scenarios', () {
      final generator = FakeEntityIdGenerator(['same-id', 'same-id']);

      expect(generator.generate(), 'same-id');
      expect(generator.generate(), 'same-id');
      expect(generator.callCount, 2);
    });
  });
}
