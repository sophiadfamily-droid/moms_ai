import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_alias.dart';
import 'package:moms_ai/core/identity/entity_types.dart';
import 'package:moms_ai/core/identity/life_entity.dart';
import 'package:moms_ai/repositories/identity/identity_serialization.dart';

void main() {
  group('IdentitySerialization round trip', () {
    test('preserves a complete immutable entity using UTC ISO dates', () {
      final entity = _entity(
        aliases: [_alias('Alias A')],
        metadata: {
          'nested': <String, Object?>{
            'list': <Object?>['value'],
          },
        },
      );
      final map = IdentitySerialization.toMap(entity);
      final restored = IdentitySerialization.fromMap(map);

      expect(map['createdAt'], '2026-01-10T09:00:00.000Z');
      expect(restored.id, entity.id);
      expect(restored.type, entity.type);
      expect(restored.canonicalLabel, entity.canonicalLabel);
      expect(restored.normalizedLabel, entity.normalizedLabel);
      expect(restored.aliases.single.value, 'Alias A');
      expect(restored.source.type, EntitySourceType.profile);
      expect(restored.source.sourceId, 'source-1');
      expect(restored.schemaVersion, 2);
      expect(restored.metadata['nested'], entity.metadata['nested']);
      expect(
        () => (restored.metadata['nested'] as Map)['other'] = 1,
        throwsUnsupportedError,
      );
    });

    test('round trips every entity status including a merge', () {
      for (final status in [
        EntityStatus.active,
        EntityStatus.inactive,
        EntityStatus.deleted,
      ]) {
        expect(
          IdentitySerialization.fromMap(
                  IdentitySerialization.toMap(_entity(status: status)))
              .status,
          status,
        );
      }
      final merged = _entity(
        status: EntityStatus.merged,
        mergedIntoEntityId: 'entity-2',
      );
      final restored =
          IdentitySerialization.fromMap(IdentitySerialization.toMap(merged));
      expect(restored.status, EntityStatus.merged);
      expect(restored.mergedIntoEntityId, 'entity-2');
    });
  });

  group('IdentitySerialization historical compatibility', () {
    test('applies only documented safe defaults', () {
      final restored = IdentitySerialization.fromMap({
        'id': 'entity-1',
        'canonicalLabel': 'Primary Place',
        'createdAt': '2026-01-10T10:00:00+01:00',
      });

      expect(restored.type, EntityType.unknown);
      expect(restored.normalizedLabel, 'primary place');
      expect(restored.aliases, isEmpty);
      expect(restored.metadata, isEmpty);
      expect(restored.status, EntityStatus.active);
      expect(restored.source.type, EntitySourceType.historical);
      expect(restored.updatedAt, restored.createdAt);
      expect(restored.createdAt, DateTime.utc(2026, 1, 10, 9));
      expect(restored.schemaVersion, 1);
    });

    test('ignores unknown additive fields without claiming preservation', () {
      final map = _minimalMap()..['futureField'] = {'value': true};

      final serialized =
          IdentitySerialization.toMap(IdentitySerialization.fromMap(map));
      expect(serialized.containsKey('futureField'), isFalse);
    });

    test('defaults historical alias normalization and source safely', () {
      final map = _minimalMap()
        ..['aliases'] = [
          {
            'value': 'Legacy Alias',
            'kind': 'explicit',
            'createdAt': '2026-01-10T09:00:00.000Z',
          },
        ];

      final alias = IdentitySerialization.fromMap(map).aliases.single;
      expect(alias.normalizedValue, 'legacy alias');
      expect(alias.source.type, EntitySourceType.historical);
    });
  });

  group('IdentitySerialization invalid data', () {
    test('rejects missing or invalid identity fields', () {
      expectSerializationError(
          {..._minimalMap()}..remove('id'), 'invalid_field_type');
      expectSerializationError(
          {..._minimalMap(), 'id': ' '}, 'invalid_serialized_entity');
      expectSerializationError(
          {..._minimalMap()}..remove('canonicalLabel'), 'invalid_field_type');
      expectSerializationError({..._minimalMap(), 'canonicalLabel': '...'},
          'invalid_serialized_entity');
    });

    test('rejects unknown enums, invalid dates and primitive types', () {
      expectSerializationError(
          {..._minimalMap(), 'type': 'futureType'}, 'invalid_enum_value');
      expectSerializationError(
          {..._minimalMap(), 'createdAt': 'invalid'}, 'invalid_date_value');
      expectSerializationError(
          {..._minimalMap(), 'schemaVersion': '1'}, 'invalid_field_type');
      expectSerializationError(
          {..._minimalMap(), 'status': 1}, 'invalid_field_type');
    });

    test('rejects malformed aliases and metadata', () {
      expectSerializationError(
          {..._minimalMap(), 'aliases': {}}, 'invalid_field_type');
      expectSerializationError({
        ..._minimalMap(),
        'aliases': [1]
      }, 'invalid_field_type');
      expectSerializationError(
          {..._minimalMap(), 'metadata': []}, 'invalid_field_type');
      expectSerializationError(
        {
          ..._minimalMap(),
          'aliases': [
            {
              'value': '',
              'kind': 'explicit',
              'createdAt': '2026-01-10T09:00:00.000Z',
            },
          ],
        },
        'invalid_serialized_entity',
      );
    });

    test('wraps invalid versions and merge contradictions safely', () {
      for (final version in <Object?>[null, 0, -1]) {
        expectSerializationError(
          {..._minimalMap(), 'schemaVersion': version},
          version == null ? 'invalid_field_type' : 'invalid_serialized_entity',
        );
      }
      expectSerializationError(
        {
          ..._minimalMap(),
          'status': 'merged',
          'mergedIntoEntityId': 'entity-1',
        },
        'invalid_serialized_entity',
      );
    });
  });
}

final _createdAt = DateTime(2026, 1, 10, 10);
final _updatedAt = DateTime(2026, 1, 11, 10);
const _source =
    EntitySource(type: EntitySourceType.profile, sourceId: 'source-1');

LifeEntity _entity({
  List<EntityAlias> aliases = const [],
  Map<String, Object?> metadata = const {},
  EntityStatus status = EntityStatus.active,
  String? mergedIntoEntityId,
}) =>
    LifeEntity.fromLabel(
      id: 'entity-1',
      type: EntityType.person,
      canonicalLabel: 'Person A',
      aliases: aliases,
      status: status,
      source: _source,
      createdAt: _createdAt,
      updatedAt: _updatedAt,
      metadata: metadata,
      mergedIntoEntityId: mergedIntoEntityId,
      schemaVersion: 2,
    );

EntityAlias _alias(String value) => EntityAlias.fromValue(
      value: value,
      kind: EntityAliasKind.explicit,
      source: _source,
      createdAt: _createdAt,
      validFrom: _createdAt,
      validUntil: _updatedAt.add(const Duration(days: 1)),
    );

Map<String, Object?> _minimalMap() => {
      'id': 'entity-1',
      'canonicalLabel': 'Person A',
      'createdAt': '2026-01-10T09:00:00.000Z',
    };

void expectSerializationError(Map<String, Object?> map, String code) {
  expect(
    () => IdentitySerialization.fromMap(map),
    throwsA(isA<IdentitySerializationException>()
        .having((error) => error.code, 'code', code)),
  );
}
