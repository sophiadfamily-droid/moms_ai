import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_types.dart';
import 'package:moms_ai/core/identity/persisted_identity_link.dart';

void main() {
  group('PersistedIdentityLink construction', () {
    test('creates a minimal version-one link for every durable entity type',
        () {
      for (final type in EntityType.values.where(
        (value) => value != EntityType.unknown,
      )) {
        final link = PersistedIdentityLink(
          entityId: 'entity-${type.name}',
          entityType: type,
        );

        expect(link.entityType, type);
        expect(link.schemaVersion, 1);
      }
    });

    test('rejects empty and whitespace-only identifiers', () {
      for (final id in ['', '  ', '\t\n']) {
        expect(
          () => _link(entityId: id),
          throwsA(_domain('invalid_persisted_identity_link_entity_id')),
        );
      }
    });

    test('rejects the unknown entity type', () {
      expect(
        () => _link(entityType: EntityType.unknown),
        throwsA(_domain('invalid_persisted_identity_link_entity_type')),
      );
    });

    test('rejects zero, negative, and future schema versions', () {
      for (final version in [0, -1, 2]) {
        expect(
          () => _link(schemaVersion: version),
          throwsA(_domain('invalid_persisted_identity_link_schema_version')),
        );
      }
    });

    test('contains no label, scope, alias, or metadata properties', () {
      final link = _link();
      final source = link.toString();

      expect(source, isNot(contains('label')));
      expect(source, isNot(contains('scope')));
      expect(source, isNot(contains('alias')));
      expect(source, isNot(contains('metadata')));
    });
  });

  group('PersistedIdentityLink value semantics', () {
    test('uses structural equality and a coherent hash code', () {
      final first = _link();
      final equivalent = _link();

      expect(first, equivalent);
      expect(first, same(first));
      expect(first.hashCode, equivalent.hashCode);
    });

    test('distinguishes entity ID and type', () {
      final base = _link();

      expect(base, isNot(_link(entityId: 'entity-2')));
      expect(base, isNot(_link(entityType: EntityType.place)));
    });

    test('copyWith preserves values and validates replacements', () {
      final link = _link();

      expect(link.copyWith(), link);
      expect(link.copyWith(entityId: 'entity-2').entityId, 'entity-2');
      expect(link.copyWith(entityType: EntityType.place).entityType,
          EntityType.place);
      expect(
        () => link.copyWith(schemaVersion: 2),
        throwsA(_domain('invalid_persisted_identity_link_schema_version')),
      );
    });

    test('safe debug representation never exposes the entity ID', () {
      final link = _link(entityId: 'sensitive-entity-id');

      expect(
        link.toString(),
        'PersistedIdentityLink(type: person, schemaVersion: 1)',
      );
      expect(link.toString(), isNot(contains('sensitive-entity-id')));
    });
  });
}

PersistedIdentityLink _link({
  String entityId = 'entity-1',
  EntityType entityType = EntityType.person,
  int schemaVersion = 1,
}) {
  return PersistedIdentityLink(
    entityId: entityId,
    entityType: entityType,
    schemaVersion: schemaVersion,
  );
}

Matcher _domain(String code) =>
    isA<EntityDomainException>().having((error) => error.code, 'code', code);
