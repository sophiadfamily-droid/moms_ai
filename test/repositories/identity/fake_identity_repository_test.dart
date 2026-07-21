import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_alias.dart';
import 'package:moms_ai/core/identity/entity_types.dart';
import 'package:moms_ai/core/identity/life_entity.dart';
import 'package:moms_ai/repositories/identity/fake_identity_repository.dart';
import 'package:moms_ai/repositories/identity/identity_repository.dart';
import 'package:moms_ai/repositories/identity/identity_repository_query.dart';
import 'package:moms_ai/repositories/identity/identity_repository_result.dart';

import 'identity_repository_contract_test.dart';

void main() {
  group('IdentityAccountScope', () {
    test('trims valid account identifiers and compares by value', () {
      expect(IdentityAccountScope(' account-a ').accountId, 'account-a');
      expect(
          IdentityAccountScope('account-a'), IdentityAccountScope('account-a'));
      expect(IdentityAccountScope('account-a'),
          isNot(IdentityAccountScope('account-b')));
    });

    test('rejects empty and whitespace-only scopes', () {
      expect(() => IdentityAccountScope(''),
          throwsA(repositoryError('invalid_account_scope')));
      expect(() => IdentityAccountScope('   '),
          throwsA(repositoryError('invalid_account_scope')));
    });
  });

  group('IdentityRepositoryQuery', () {
    test('normalizes keys and defensively freezes ID and relation lists', () {
      final ids = ['entity-1'];
      final relations = ['Work Place'];
      final byIds = IdentityRepositoryQuery.byIds(entityIds: ids);
      final byRelations =
          IdentityRepositoryQuery.forRelations(relationKeys: relations);
      ids.add('entity-2');
      relations.clear();

      expect(byIds.entityIds, ['entity-1']);
      expect(byRelations.relationKeys, ['work place']);
      expect(() => byIds.entityIds.add('entity-3'), throwsUnsupportedError);
    });

    test('rejects unbounded, empty and duplicate query inputs', () {
      expect(
        () => IdentityRepositoryQuery.byComparisonKey(
            comparisonKey: 'value', candidateLimit: 21),
        throwsA(repositoryError('candidate_limit_exceeded')),
      );
      expect(
        () => IdentityRepositoryQuery.byComparisonKey(comparisonKey: '...'),
        throwsA(repositoryError('invalid_comparison_key')),
      );
      expect(
        () =>
            IdentityRepositoryQuery.byIds(entityIds: ['entity-1', 'entity-1']),
        throwsA(repositoryError('duplicate_entity_id')),
      );
      expect(
        () => IdentityRepositoryQuery.forRelations(relationKeys: ['...']),
        throwsA(repositoryError('invalid_relation_key')),
      );
    });
  });

  group('IdentityRepositoryQueryResult', () {
    test('defensively freezes results and enforces limits and unique IDs', () {
      final values = [_entity()];
      final result = IdentityRepositoryQueryResult(
        entities: values,
        limitReached: false,
        requestedLimit: 1,
      );
      values.clear();

      expect(result.entities, hasLength(1));
      expect(() => result.entities.clear(), throwsUnsupportedError);
      expect(
        () => IdentityRepositoryQueryResult(
          entities: [_entity(), _entity()],
          limitReached: false,
          requestedLimit: 2,
        ),
        throwsA(repositoryError('duplicate_entity_id')),
      );
      expect(
        () => IdentityRepositoryQueryResult(
          entities: [_entity(), _entity(id: 'entity-2')],
          limitReached: true,
          requestedLimit: 1,
        ),
        throwsA(repositoryError('invalid_query_result')),
      );
    });
  });

  group('FakeIdentityRepository queries', () {
    late FakeIdentityRepository repository;
    late IdentityAccountScope accountA;
    late IdentityAccountScope accountB;

    setUp(() {
      repository = FakeIdentityRepository();
      accountA = IdentityAccountScope('account-a');
      accountB = IdentityAccountScope('account-b');
    });

    test('matches canonical labels and aliases without choosing a winner',
        () async {
      await repository.saveAll(scope: accountA, entities: [
        _entity(id: 'entity-2', label: 'Shared'),
        _entity(id: 'entity-1', aliases: [_alias('Shared')]),
      ]);

      final result = await repository.queryCandidates(
        scope: accountA,
        query: IdentityRepositoryQuery.byComparisonKey(comparisonKey: 'shared'),
      );
      expect(result.entities.map((item) => item.id), ['entity-1', 'entity-2']);
    });

    test('filters types and statuses only when explicitly requested', () async {
      await repository.saveAll(scope: accountA, entities: [
        _entity(id: 'active'),
        _entity(id: 'inactive', status: EntityStatus.inactive),
        _entity(id: 'deleted', status: EntityStatus.deleted),
        _entity(
          id: 'merged',
          status: EntityStatus.merged,
          mergedIntoEntityId: 'active',
        ),
        _entity(id: 'place', type: EntityType.place),
      ]);
      final defaultResult = await repository.queryCandidates(
        scope: accountA,
        query: IdentityRepositoryQuery.byComparisonKey(
          comparisonKey: 'Person A',
          expectedType: EntityType.person,
        ),
      );
      final allStatuses = await repository.queryCandidates(
        scope: accountA,
        query: IdentityRepositoryQuery.byComparisonKey(
          comparisonKey: 'Person A',
          expectedType: EntityType.person,
          includeInactive: true,
          includeMerged: true,
          includeDeleted: true,
        ),
      );

      expect(defaultResult.entities.map((item) => item.id), ['active']);
      expect(allStatuses.entities, hasLength(4));
    });

    test('uses referenceDate only to safely prefilter temporal aliases',
        () async {
      await repository.save(
        scope: accountA,
        entity: _entity(aliases: [
          _alias(
            'Temporary',
            kind: EntityAliasKind.temporary,
            validUntil: date.subtract(const Duration(days: 1)),
          ),
        ]),
      );
      final withoutDate = await repository.queryCandidates(
        scope: accountA,
        query:
            IdentityRepositoryQuery.byComparisonKey(comparisonKey: 'Temporary'),
      );
      final withDate = await repository.queryCandidates(
        scope: accountA,
        query: IdentityRepositoryQuery.byComparisonKey(
          comparisonKey: 'Temporary',
          referenceDate: date,
        ),
      );

      expect(withoutDate.entities, hasLength(1));
      expect(withDate.entities, isEmpty);
    });

    test('keeps alias and relation indexes isolated by account', () async {
      await repository.save(scope: accountA, entity: _entity());
      await repository.save(
        scope: accountB,
        entity: _entity(aliases: const []),
      );
      repository.indexRelation(
          scope: accountA, relationKey: 'workplace', entityId: 'entity-1');

      final aliasB = await repository.queryCandidates(
        scope: accountB,
        query:
            IdentityRepositoryQuery.byComparisonKey(comparisonKey: 'Alias A'),
      );
      final relationA = await repository.queryCandidates(
        scope: accountA,
        query:
            IdentityRepositoryQuery.forRelations(relationKeys: ['workplace']),
      );
      final relationB = await repository.queryCandidates(
        scope: accountB,
        query:
            IdentityRepositoryQuery.forRelations(relationKeys: ['workplace']),
      );

      expect(aliasB.entities, isEmpty);
      expect(relationA.entities.single.id, 'entity-1');
      expect(relationB.entities, isEmpty);
    });

    test('returns a deterministic type, label and ID order', () async {
      await repository.saveAll(scope: accountA, entities: [
        _entity(id: 'place-b', label: 'Place B', type: EntityType.place),
        _entity(id: 'person-b', label: 'Person B'),
        _entity(id: 'person-a-2', label: 'Person A'),
        _entity(id: 'person-a-1', label: 'Person A'),
      ]);
      final result = await repository.findByIds(
        scope: accountA,
        entityIds: ['place-b', 'person-b', 'person-a-2', 'person-a-1'],
      );

      expect(result.map((item) => item.id),
          ['person-a-1', 'person-a-2', 'person-b', 'place-b']);
    });

    test('query-by-IDs remains scoped and does not resolve candidates',
        () async {
      await repository.saveAll(scope: accountA, entities: [
        _entity(id: 'entity-2'),
        _entity(id: 'entity-1'),
      ]);
      await repository.save(scope: accountB, entity: _entity(id: 'entity-3'));

      final result = await repository.queryCandidates(
        scope: accountA,
        query: IdentityRepositoryQuery.byIds(
          entityIds: ['entity-3', 'entity-2', 'entity-1'],
        ),
      );
      expect(result.entities.map((item) => item.id), ['entity-1', 'entity-2']);
    });
  });
}

const _source = EntitySource(type: EntitySourceType.user);

LifeEntity _entity({
  String id = 'entity-1',
  String label = 'Person A',
  EntityType type = EntityType.person,
  List<EntityAlias>? aliases,
  EntityStatus status = EntityStatus.active,
  String? mergedIntoEntityId,
}) =>
    LifeEntity.fromLabel(
      id: id,
      type: type,
      canonicalLabel: label,
      aliases: aliases ?? [_alias('Alias A')],
      status: status,
      source: _source,
      createdAt: date.subtract(const Duration(days: 10)),
      updatedAt: date,
      mergedIntoEntityId: mergedIntoEntityId,
    );

EntityAlias _alias(
  String value, {
  EntityAliasKind kind = EntityAliasKind.explicit,
  DateTime? validUntil,
}) =>
    EntityAlias.fromValue(
      value: value,
      kind: kind,
      source: _source,
      createdAt: date.subtract(const Duration(days: 10)),
      validUntil: validUntil,
    );
