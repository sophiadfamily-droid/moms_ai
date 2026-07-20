import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_matcher.dart';

void main() {
  group('EntityMatcher', () {
    test('matches identical valid IDs without calling the legacy fallback', () {
      var legacyCallCount = 0;
      final matcher = EntityMatcher<_FakeEntity>(
        idOf: (entity) => entity.id,
        legacyEquals: (first, second) {
          legacyCallCount++;
          return false;
        },
      );

      expect(
        matcher.matches(
          const _FakeEntity(id: 'entity-1', legacyValue: 'first'),
          const _FakeEntity(id: 'entity-1', legacyValue: 'second'),
        ),
        isTrue,
      );
      expect(legacyCallCount, 0);
    });

    test('different valid IDs override an equal legacy identity', () {
      var legacyCallCount = 0;
      final matcher = EntityMatcher<_FakeEntity>(
        idOf: (entity) => entity.id,
        legacyEquals: (first, second) {
          legacyCallCount++;
          return first.legacyValue == second.legacyValue;
        },
      );

      expect(
        matcher.matches(
          const _FakeEntity(id: 'entity-1', legacyValue: 'same'),
          const _FakeEntity(id: 'entity-2', legacyValue: 'same'),
        ),
        isFalse,
      );
      expect(legacyCallCount, 0);
    });

    test('uses legacy fallback when only the first ID is valid', () {
      expect(
        _matcher.matches(
          const _FakeEntity(id: 'entity-1', legacyValue: 'same'),
          const _FakeEntity(legacyValue: 'same'),
        ),
        isTrue,
      );
    });

    test('uses legacy fallback when only the second ID is valid', () {
      expect(
        _matcher.matches(
          const _FakeEntity(legacyValue: 'same'),
          const _FakeEntity(id: 'entity-1', legacyValue: 'same'),
        ),
        isTrue,
      );
    });

    test('uses legacy fallback when both IDs are absent', () {
      expect(
        _matcher.matches(
          const _FakeEntity(legacyValue: 'same'),
          const _FakeEntity(legacyValue: 'same'),
        ),
        isTrue,
      );
    });

    test('treats empty and whitespace IDs as invalid', () {
      expect(
        _matcher.matches(
          const _FakeEntity(id: '', legacyValue: 'same'),
          const _FakeEntity(id: ' \t\n', legacyValue: 'same'),
        ),
        isTrue,
      );
    });
  });
}

final EntityMatcher<_FakeEntity> _matcher = EntityMatcher(
  idOf: (entity) => entity.id,
  legacyEquals: (first, second) => first.legacyValue == second.legacyValue,
);

final class _FakeEntity {
  final String? id;
  final String legacyValue;

  const _FakeEntity({this.id, required this.legacyValue});
}
