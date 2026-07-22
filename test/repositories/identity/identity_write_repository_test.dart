import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_types.dart';
import 'package:moms_ai/core/identity/life_entity.dart';
import 'package:moms_ai/repositories/identity/fake_identity_repository.dart';
import 'package:moms_ai/repositories/identity/identity_repository.dart';

void main() {
  final scope = IdentityAccountScope('account-a');
  final createdAt = DateTime.utc(2026, 1, 1);

  LifeEntity entity({
    String id = 'entity-1',
    String label = 'Person A',
    EntityType type = EntityType.person,
    EntityStatus status = EntityStatus.active,
    DateTime? updatedAt,
    int schemaVersion = 1,
    String? mergedIntoEntityId,
  }) =>
      LifeEntity.fromLabel(
        id: id,
        type: type,
        canonicalLabel: label,
        status: status,
        source: const EntitySource(type: EntitySourceType.user),
        createdAt: createdAt,
        updatedAt: updatedAt ?? createdAt,
        schemaVersion: schemaVersion,
        mergedIntoEntityId: mergedIntoEntityId,
      );

  test('complete repository satisfies separate read and write contracts', () {
    final IdentityRepository complete = FakeIdentityRepository();
    expect(complete, isA<IdentityReadRepository>());
    expect(complete, isA<IdentityWriteRepository>());
  });

  test('revisioned result rejects a non-positive revision at runtime', () {
    expect(
      () => RevisionedIdentity(entity: entity(), revision: 0),
      throwsCode('invalid_revision'),
    );
  });

  test('create is create-only and starts at revision one', () async {
    final repository = FakeIdentityRepository();
    final created = await repository.create(scope: scope, entity: entity());

    expect(created.revision, 1);
    expect(created.entity.id, 'entity-1');
    await expectLater(
      repository.create(
        scope: scope,
        entity: entity(label: 'Replacement'),
      ),
      throwsCode('identity_already_exists'),
    );
    expect(
      (await repository.findById(scope: scope, entityId: 'entity-1'))
          ?.canonicalLabel,
      'Person A',
    );
  });

  test('create rejects merged and deleted states', () async {
    final repository = FakeIdentityRepository();
    await expectLater(
      repository.create(
        scope: scope,
        entity: entity(
          status: EntityStatus.merged,
          mergedIntoEntityId: 'entity-2',
        ),
      ),
      throwsCode('invalid_status_transition'),
    );
    await expectLater(
      repository.create(
        scope: scope,
        entity: entity(status: EntityStatus.deleted),
      ),
      throwsCode('invalid_status_transition'),
    );
  });

  test('update increments revision and preserves immutable fields', () async {
    final repository = FakeIdentityRepository();
    await repository.create(scope: scope, entity: entity());
    final updated = await repository.update(
      scope: scope,
      entity: entity(
        label: 'Person B',
        updatedAt: createdAt.add(const Duration(minutes: 1)),
      ),
      expectedRevision: 1,
    );

    expect(updated.revision, 2);
    expect(updated.entity.createdAt, createdAt);
    expect(updated.entity.canonicalLabel, 'Person B');
  });

  test('update rejects revision conflicts and missing documents', () async {
    final repository = FakeIdentityRepository();
    await repository.create(scope: scope, entity: entity());
    final next = entity(
      label: 'Person B',
      updatedAt: createdAt.add(const Duration(minutes: 1)),
    );
    await expectLater(
      repository.update(scope: scope, entity: next, expectedRevision: 2),
      throwsCode('revision_conflict'),
    );
    await expectLater(
      repository.update(
        scope: scope,
        entity: entity(
          id: 'missing',
          updatedAt: createdAt.add(const Duration(minutes: 1)),
        ),
        expectedRevision: 1,
      ),
      throwsCode('identity_not_found'),
    );
  });

  test('update rejects immutable changes and merge transitions', () async {
    final repository = FakeIdentityRepository();
    await repository.create(scope: scope, entity: entity());
    final updatedAt = createdAt.add(const Duration(minutes: 1));
    for (final invalid in [
      entity(type: EntityType.place, updatedAt: updatedAt),
      entity(schemaVersion: 2, updatedAt: updatedAt),
      entity(
        status: EntityStatus.merged,
        mergedIntoEntityId: 'entity-2',
        updatedAt: updatedAt,
      ),
    ]) {
      await expectLater(
        repository.update(
          scope: scope,
          entity: invalid,
          expectedRevision: 1,
        ),
        throwsA(isA<IdentityRepositoryException>()),
      );
    }
  });

  test('soft delete preserves the document and increments revision', () async {
    final repository = FakeIdentityRepository();
    await repository.create(scope: scope, entity: entity());
    final deleted = await repository.softDelete(
      scope: scope,
      entityId: 'entity-1',
      expectedRevision: 1,
      updatedAt: createdAt.add(const Duration(minutes: 1)),
    );

    expect(deleted.revision, 2);
    expect(deleted.entity.status, EntityStatus.deleted);
    expect(
      (await repository.findById(scope: scope, entityId: 'entity-1'))?.status,
      EntityStatus.deleted,
    );
    await expectLater(
      repository.softDelete(
        scope: scope,
        entityId: 'entity-1',
        expectedRevision: 2,
        updatedAt: createdAt.add(const Duration(minutes: 2)),
      ),
      throwsCode('invalid_status_transition'),
    );
  });

  test('concurrent updates with one expected revision allow one winner',
      () async {
    final repository = FakeIdentityRepository();
    await repository.create(scope: scope, entity: entity());
    final results = await Future.wait(
      ['Person B', 'Person C'].map((label) async {
        try {
          return await repository.update(
            scope: scope,
            entity: entity(
              label: label,
              updatedAt: createdAt.add(const Duration(minutes: 1)),
            ),
            expectedRevision: 1,
          );
        } on IdentityRepositoryException catch (error) {
          return error;
        }
      }),
    );

    expect(results.whereType<RevisionedIdentity>(), hasLength(1));
    expect(
      results.whereType<IdentityRepositoryException>().single.code,
      'revision_conflict',
    );
  });
}

Matcher throwsCode(String code) => throwsA(
      isA<IdentityRepositoryException>()
          .having((error) => error.code, 'code', code),
    );
