import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_types.dart';
import 'package:moms_ai/core/identity/persisted_identity_link.dart';
import 'package:moms_ai/repositories/identity/persisted_identity_link_serialization.dart';

void main() {
  group('PersistedIdentityLinkSerialization writes', () {
    test('writes exactly the deterministic version-one contract', () {
      final map = PersistedIdentityLinkSerialization.toMap(_link());

      expect(map.keys.toList(), ['entityId', 'entityType', 'schemaVersion']);
      expect(map, {
        'entityId': 'entity-1',
        'entityType': 'person',
        'schemaVersion': 1,
      });
      expect(map, isNot(contains('label')));
      expect(map, isNot(contains('scope')));
      expect(map, isNot(contains('metadata')));
    });

    test('round trips a valid link', () {
      final original = _link(entityType: EntityType.organization);
      final result = PersistedIdentityLinkSerialization.fromMap(
        PersistedIdentityLinkSerialization.toMap(original),
      );

      expect(result.status, PersistedIdentityLinkReadStatus.valid);
      expect(result.link, original);
      expect(result.diagnosticCodes, isEmpty);
    });
  });

  group('PersistedIdentityLinkSerialization defensive reads', () {
    test('treats an absent or null value as absent', () {
      for (final value in <Object?>[null]) {
        final result = PersistedIdentityLinkSerialization.fromMap(value);
        expect(result.status, PersistedIdentityLinkReadStatus.absent);
        expect(result.link, isNull);
        expect(result.diagnosticCodes, isEmpty);
      }
    });

    test('rejects empty maps and primitive values without throwing', () {
      for (final value in <Object?>[{}, 'value', 1, true, const []]) {
        final result = PersistedIdentityLinkSerialization.fromMap(value);
        expect(result.status, PersistedIdentityLinkReadStatus.invalid);
        expect(result.link, isNull);
        expect(
          result.diagnosticCodes,
          contains('persisted_identity_link_invalid'),
        );
      }
    });

    test('rejects missing, empty, invalid-type entity IDs', () {
      for (final map in <Map<String, Object?>>[
        _validMap()..remove('entityId'),
        {..._validMap(), 'entityId': ''},
        {..._validMap(), 'entityId': '   '},
        {..._validMap(), 'entityId': 1},
      ]) {
        final result = PersistedIdentityLinkSerialization.fromMap(map);
        expect(result.status, PersistedIdentityLinkReadStatus.invalid);
        expect(
          result.diagnosticCodes,
          contains('persisted_identity_link_invalid_entity_id'),
        );
      }
    });

    test('rejects missing, unknown, and invalid-type entity types', () {
      for (final map in <Map<String, Object?>>[
        _validMap()..remove('entityType'),
        {..._validMap(), 'entityType': 'futureType'},
        {..._validMap(), 'entityType': 'unknown'},
        {..._validMap(), 'entityType': 1},
      ]) {
        final result = PersistedIdentityLinkSerialization.fromMap(map);
        expect(result.status, PersistedIdentityLinkReadStatus.invalid);
        expect(
          result.diagnosticCodes,
          contains('persisted_identity_link_invalid_entity_type'),
        );
      }
    });

    test('defaults a missing schema version to V1 with a diagnostic', () {
      final map = _validMap()..remove('schemaVersion');
      final result = PersistedIdentityLinkSerialization.fromMap(map);

      expect(result.status, PersistedIdentityLinkReadStatus.valid);
      expect(result.link?.schemaVersion, 1);
      expect(
        result.diagnosticCodes,
        ['persisted_identity_link_version_defaulted'],
      );
    });

    test('rejects invalid schema versions without throwing', () {
      for (final version in <Object?>[null, 0, -1, '1', 1.0]) {
        final result = PersistedIdentityLinkSerialization.fromMap({
          ..._validMap(),
          'schemaVersion': version,
        });
        expect(result.status, PersistedIdentityLinkReadStatus.invalid);
        expect(
          result.diagnosticCodes,
          contains('persisted_identity_link_invalid_schema_version'),
        );
      }
    });

    test('reports future versions without interpreting their content', () {
      final result = PersistedIdentityLinkSerialization.fromMap({
        ..._validMap(),
        'schemaVersion': 2,
      });

      expect(
        result.status,
        PersistedIdentityLinkReadStatus.unsupportedVersion,
      );
      expect(result.link, isNull);
      expect(
        result.diagnosticCodes,
        ['persisted_identity_link_unsupported_version'],
      );
    });

    test('ignores unknown additive fields without preserving them', () {
      final result = PersistedIdentityLinkSerialization.fromMap({
        ..._validMap(),
        'futureField': {'value': true},
      });

      expect(result.status, PersistedIdentityLinkReadStatus.valid);
      expect(
        PersistedIdentityLinkSerialization.toMap(result.link!),
        isNot(contains('futureField')),
      );
    });

    test('freezes diagnostics defensively', () {
      final result = PersistedIdentityLinkSerialization.fromMap({});

      expect(
        () => result.diagnosticCodes.add('changed'),
        throwsUnsupportedError,
      );
    });

    test('diagnostics never expose persisted values', () {
      final result = PersistedIdentityLinkSerialization.fromMap({
        ..._validMap(),
        'entityId': 'sensitive-entity-id',
        'entityType': 'futureType',
      });
      final diagnostics = result.diagnosticCodes.join(' ');

      expect(diagnostics, isNot(contains('sensitive-entity-id')));
      expect(diagnostics, isNot(contains('futureType')));
    });

    test('never throws for malformed persisted values', () {
      final malformed = <Object?>[
        null,
        const [],
        <Object?, Object?>{1: 'value'},
        {'entityId': Object()},
        {'entityId': 'entity-1', 'entityType': Object()},
      ];

      for (final value in malformed) {
        expect(
          () => PersistedIdentityLinkSerialization.fromMap(value),
          returnsNormally,
        );
      }
    });
  });
}

PersistedIdentityLink _link({
  EntityType entityType = EntityType.person,
}) {
  return PersistedIdentityLink(
    entityId: 'entity-1',
    entityType: entityType,
  );
}

Map<String, Object?> _validMap() => {
      'entityId': 'entity-1',
      'entityType': 'person',
      'schemaVersion': 1,
    };
