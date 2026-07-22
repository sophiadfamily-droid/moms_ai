import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_alias.dart';
import 'package:moms_ai/core/identity/entity_types.dart';
import 'package:moms_ai/core/identity/life_entity.dart';
import 'package:moms_ai/repositories/identity/firestore_identity_serialization.dart';
import 'package:moms_ai/repositories/identity/identity_read_repository.dart';
import 'package:moms_ai/repositories/identity/identity_serialization.dart';

void main() {
  final createdAt = DateTime.utc(2026, 1, 1);

  LifeEntity entity({
    String id = 'entity-1',
    EntityStatus status = EntityStatus.active,
    List<EntityAlias> aliases = const [],
    String? mergedIntoEntityId,
  }) =>
      LifeEntity.fromLabel(
        id: id,
        type: EntityType.person,
        canonicalLabel: 'Person A',
        aliases: aliases,
        status: status,
        source: const EntitySource(type: EntitySourceType.user),
        createdAt: createdAt,
        updatedAt: createdAt,
        mergedIntoEntityId: mergedIntoEntityId,
      );

  Map<String, Object?> document(LifeEntity value) => {
        ...IdentitySerialization.toMap(value),
        'aliasComparisonKeys': value.aliases
            .map((alias) => alias.comparisonKey)
            .toList(growable: false),
        'revision': 1,
      };

  test('reads a valid document and optional revision', () {
    final value = entity();
    final decoded = FirestoreIdentitySerialization.fromDocument(
      documentId: value.id,
      data: document(value),
    );
    expect(decoded.id, value.id);
    expect(decoded.status, EntityStatus.active);
  });

  test('writes the canonical document with deterministic derived fields', () {
    final alias = EntityAlias.fromValue(
      value: 'Person Alias',
      kind: EntityAliasKind.explicit,
      source: const EntitySource(type: EntitySourceType.user),
      createdAt: createdAt,
    );
    final value = entity(aliases: [alias]);
    final data = FirestoreIdentitySerialization.toDocument(
      entity: value,
      revision: 1,
    );

    expect(data['revision'], 1);
    expect(data['aliasComparisonKeys'], [alias.comparisonKey]);
    expect(data['createdAt'], '2026-01-01T00:00:00.000Z');
    expect(data['updatedAt'], '2026-01-01T00:00:00.000Z');
  });

  test('write serialization rejects invalid revisions', () {
    expect(
      () => FirestoreIdentitySerialization.toDocument(
        entity: entity(),
        revision: 0,
      ),
      throwsRepositoryCode('invalid_revision'),
    );
  });

  test('accepts a historical document without revision', () {
    final value = entity();
    final data = document(value)..remove('revision');
    expect(
      FirestoreIdentitySerialization.fromDocument(
        documentId: value.id,
        data: data,
      ).id,
      value.id,
    );
  });

  test('accepts missing derived keys only when there are no aliases', () {
    final value = entity();
    final data = document(value)..remove('aliasComparisonKeys');
    expect(
      FirestoreIdentitySerialization.fromDocument(
        documentId: value.id,
        data: data,
      ).id,
      value.id,
    );
  });

  test('validates derived alias comparison keys', () {
    final alias = EntityAlias.fromValue(
      value: 'Person Alias',
      kind: EntityAliasKind.explicit,
      source: const EntitySource(type: EntitySourceType.user),
      createdAt: createdAt,
    );
    final value = entity(aliases: [alias]);
    final valid = document(value);
    expect(
      FirestoreIdentitySerialization.fromDocument(
        documentId: value.id,
        data: valid,
      ).aliases,
      hasLength(1),
    );

    for (final invalid in <Object?>[
      null,
      ['wrong'],
      [alias.comparisonKey, alias.comparisonKey],
      'not-a-list',
    ]) {
      final data = document(value);
      if (invalid == null) {
        data.remove('aliasComparisonKeys');
      } else {
        data['aliasComparisonKeys'] = invalid;
      }
      expect(
        () => FirestoreIdentitySerialization.fromDocument(
          documentId: value.id,
          data: data,
        ),
        throwsRepositoryCode('corrupt_identity_document'),
      );
    }
  });

  test('rejects document ID mismatch without exposing values', () {
    final value = entity();
    expect(
      () => FirestoreIdentitySerialization.fromDocument(
        documentId: 'entity-2',
        data: document(value),
      ),
      throwsRepositoryCode('document_id_mismatch'),
    );
  });

  test('rejects invalid Firestore-safe IDs', () {
    for (final id in ['', ' ', '.', '..', 'folder/entity']) {
      expect(
        () => FirestoreIdentitySerialization.validateDocumentId(id),
        throwsRepositoryCode('invalid_entity_id'),
      );
    }
  });

  test('rejects corrupt and unsupported documents defensively', () {
    final value = entity();
    final corrupt = document(value)..['revision'] = 0;
    final future = document(value)..['schemaVersion'] = 2;

    expect(
      () => FirestoreIdentitySerialization.fromDocument(
        documentId: value.id,
        data: corrupt,
      ),
      throwsRepositoryCode('corrupt_identity_document'),
    );
    expect(
      () => FirestoreIdentitySerialization.fromDocument(
        documentId: value.id,
        data: future,
      ),
      throwsRepositoryCode('unsupported_schema_version'),
    );
  });

  test('diagnostics never include document values', () {
    const rawId = 'private-entity-value';
    try {
      FirestoreIdentitySerialization.fromDocument(
        documentId: 'entity-1',
        data: const {'id': rawId},
      );
      fail('Expected an exception');
    } on IdentityRepositoryException catch (error) {
      expect(error.toString(), isNot(contains(rawId)));
    }
  });
}

Matcher throwsRepositoryCode(String code) => throwsA(
      isA<IdentityRepositoryException>()
          .having((error) => error.code, 'code', code),
    );
