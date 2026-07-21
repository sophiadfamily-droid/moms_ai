import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_types.dart';
import 'package:moms_ai/core/identity/life_entity.dart';
import 'package:moms_ai/repositories/identity/fake_identity_repository.dart';
import 'package:moms_ai/repositories/identity/identity_repository.dart';
import 'package:moms_ai/repositories/identity/identity_repository_query.dart';

typedef IdentityRepositoryFactory = IdentityRepository Function();

void main() {
  runIdentityRepositoryContract(
    'FakeIdentityRepository',
    FakeIdentityRepository.new,
  );
}

void runIdentityRepositoryContract(
  String implementationName,
  IdentityRepositoryFactory createRepository,
) {
  group('$implementationName contract', () {
    late IdentityRepository repository;
    late IdentityAccountScope accountA;
    late IdentityAccountScope accountB;

    setUp(() {
      repository = createRepository();
      accountA = IdentityAccountScope('account-a');
      accountB = IdentityAccountScope('account-b');
    });

    test('saves, reads and replaces one logical entity by ID', () async {
      await repository.save(scope: accountA, entity: entity());
      await repository.save(
        scope: accountA,
        entity: entity(label: 'Person Updated'),
      );

      expect(
          (await repository.findById(scope: accountA, entityId: 'entity-1'))
              ?.canonicalLabel,
          'Person Updated');
      expect(await repository.findById(scope: accountA, entityId: 'missing'),
          isNull);
    });

    test('strictly separates accounts for identical IDs', () async {
      await repository.save(scope: accountA, entity: entity(label: 'Person A'));
      await repository.save(scope: accountB, entity: entity(label: 'Person B'));

      expect(
          (await repository.findById(scope: accountA, entityId: 'entity-1'))
              ?.canonicalLabel,
          'Person A');
      expect(
          (await repository.findById(scope: accountB, entityId: 'entity-1'))
              ?.canonicalLabel,
          'Person B');
    });

    test('saveAll writes all validated entities', () async {
      await repository.saveAll(
        scope: accountA,
        entities: [entity(), entity(id: 'entity-2', label: 'Person B')],
      );

      final result = await repository.findByIds(
        scope: accountA,
        entityIds: ['entity-2', 'missing', 'entity-1'],
      );
      expect(result.map((item) => item.id), ['entity-1', 'entity-2']);
      expect(() => result.add(entity(id: 'entity-3')), throwsUnsupportedError);
    });

    test('saveAll rejects duplicates atomically', () async {
      await repository.save(scope: accountA, entity: entity(id: 'existing'));

      await expectLater(
        repository.saveAll(
          scope: accountA,
          entities: [entity(id: 'new'), entity(id: 'new', label: 'Other')],
        ),
        throwsA(repositoryError('atomic_write_rejected')),
      );
      expect(
          await repository.findById(scope: accountA, entityId: 'new'), isNull);
      expect(await repository.findById(scope: accountA, entityId: 'existing'),
          isNotNull);
    });

    test('findByIds validates limits, IDs and duplicates', () async {
      await expectLater(
        repository.findByIds(
          scope: accountA,
          entityIds: List.generate(21, (index) => 'entity-$index'),
        ),
        throwsA(repositoryError('candidate_limit_exceeded')),
      );
      await expectLater(
        repository.findByIds(scope: accountA, entityIds: [' ']),
        throwsA(repositoryError('invalid_entity_id')),
      );
      await expectLater(
        repository
            .findByIds(scope: accountA, entityIds: ['entity-1', 'entity-1']),
        throwsA(repositoryError('duplicate_entity_id')),
      );
    });

    test('candidate queries are bounded, stable and retain ambiguity',
        () async {
      await repository.saveAll(scope: accountA, entities: [
        entity(id: 'entity-2', label: 'Shared'),
        entity(id: 'entity-1', label: 'Shared'),
        entity(id: 'entity-3', label: 'Other'),
      ]);
      final query = IdentityRepositoryQuery.byComparisonKey(
        comparisonKey: 'shared',
        candidateLimit: 1,
      );

      final result = await repository.queryCandidates(
        scope: accountA,
        query: query,
      );
      expect(result.entities.single.id, 'entity-1');
      expect(result.limitReached, isTrue);
      expect(result.requestedLimit, 1);
      expect(() => result.entities.clear(), throwsUnsupportedError);
    });

    test('does not mutate source lists', () async {
      final entities = [entity()];
      await repository.saveAll(scope: accountA, entities: entities);
      entities.clear();

      expect(await repository.findById(scope: accountA, entityId: 'entity-1'),
          isNotNull);
    });
  });
}

final date = DateTime.utc(2026, 1, 10);
const source = EntitySource(type: EntitySourceType.user);

LifeEntity entity({
  String id = 'entity-1',
  String label = 'Person A',
  EntityType type = EntityType.person,
  EntityStatus status = EntityStatus.active,
  String? mergedIntoEntityId,
}) =>
    LifeEntity.fromLabel(
      id: id,
      type: type,
      canonicalLabel: label,
      status: status,
      source: source,
      createdAt: date,
      updatedAt: date,
      mergedIntoEntityId: mergedIntoEntityId,
    );

Matcher repositoryError(String code) => isA<IdentityRepositoryException>()
    .having((error) => error.code, 'code', code);
