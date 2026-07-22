import 'dart:collection';

import '../../core/identity/entity_normalizer.dart';
import '../../core/identity/entity_types.dart';
import '../../core/identity/life_entity.dart';
import 'identity_repository.dart';
import 'identity_repository_query.dart';
import 'identity_repository_result.dart';

final class FakeIdentityRepository implements IdentityRepository {
  final Map<IdentityAccountScope, Map<String, LifeEntity>> _entities = {};
  final Map<IdentityAccountScope, Map<String, int>> _revisions = {};
  final Map<IdentityAccountScope, Map<String, Set<String>>> _relations = {};

  @override
  Future<LifeEntity?> findById({
    required IdentityAccountScope scope,
    required String entityId,
  }) async {
    validateRepositoryEntityId(entityId);
    return _entities[scope]?[entityId];
  }

  @override
  Future<List<LifeEntity>> findByIds({
    required IdentityAccountScope scope,
    required List<String> entityIds,
  }) async {
    _validateIds(entityIds);
    final accountEntities = _entities[scope] ?? const {};
    final result = entityIds
        .map((id) => accountEntities[id])
        .whereType<LifeEntity>()
        .toList(growable: false)
      ..sort(compareIdentityEntities);
    return UnmodifiableListView(result);
  }

  @override
  Future<IdentityRepositoryQueryResult> queryCandidates({
    required IdentityAccountScope scope,
    required IdentityRepositoryQuery query,
  }) async {
    final relationIds = _relationEntityIds(scope, query.relationKeys);
    final candidates = (_entities[scope]?.values ?? const <LifeEntity>[])
        .where((entity) => _matchesQuery(entity, query, relationIds))
        .toList(growable: false)
      ..sort(compareIdentityEntities);
    final limitReached = candidates.length > query.candidateLimit;
    return IdentityRepositoryQueryResult(
      entities: candidates.take(query.candidateLimit).toList(growable: false),
      limitReached: limitReached,
      requestedLimit: query.candidateLimit,
    );
  }

  @override
  Future<RevisionedIdentity> create({
    required IdentityAccountScope scope,
    required LifeEntity entity,
  }) async {
    IdentityWriteValidator.validateCreate(entity);
    if (_entities[scope]?[entity.id] != null) {
      throw const IdentityRepositoryException('identity_already_exists');
    }
    final next = Map<String, LifeEntity>.of(_entities[scope] ?? const {});
    next[entity.id] = entity;
    _entities[scope] = next;
    final revisions = Map<String, int>.of(_revisions[scope] ?? const {});
    revisions[entity.id] = 1;
    _revisions[scope] = revisions;
    return RevisionedIdentity(entity: entity, revision: 1);
  }

  @override
  Future<RevisionedIdentity> update({
    required IdentityAccountScope scope,
    required LifeEntity entity,
    required int expectedRevision,
  }) async {
    final current = _entities[scope]?[entity.id];
    if (current == null) {
      throw const IdentityRepositoryException('identity_not_found');
    }
    final revision = _revisions[scope]?[entity.id];
    if (revision != expectedRevision) {
      throw const IdentityRepositoryException('revision_conflict');
    }
    IdentityWriteValidator.validateUpdate(
      current: current,
      next: entity,
      expectedRevision: expectedRevision,
    );
    final next = Map<String, LifeEntity>.of(_entities[scope] ?? const {});
    next[entity.id] = entity;
    _entities[scope] = next;
    final revisions = Map<String, int>.of(_revisions[scope] ?? const {});
    revisions[entity.id] = revision! + 1;
    _revisions[scope] = revisions;
    return RevisionedIdentity(entity: entity, revision: revision + 1);
  }

  @override
  Future<RevisionedIdentity> softDelete({
    required IdentityAccountScope scope,
    required String entityId,
    required int expectedRevision,
    required DateTime updatedAt,
  }) async {
    final current = _entities[scope]?[entityId];
    if (current == null) {
      throw const IdentityRepositoryException('identity_not_found');
    }
    final revision = _revisions[scope]?[entityId];
    if (revision != expectedRevision) {
      throw const IdentityRepositoryException('revision_conflict');
    }
    final deleted = IdentityWriteValidator.deletedEntity(
      current: current,
      updatedAt: updatedAt,
    );
    final next = Map<String, LifeEntity>.of(_entities[scope] ?? const {});
    next[entityId] = deleted;
    _entities[scope] = next;
    final revisions = Map<String, int>.of(_revisions[scope] ?? const {});
    revisions[entityId] = revision! + 1;
    _revisions[scope] = revisions;
    return RevisionedIdentity(entity: deleted, revision: revision + 1);
  }

  Future<void> seedAll({
    required IdentityAccountScope scope,
    required List<LifeEntity> entities,
  }) async {
    final ids = <String>{};
    if (entities.any((entity) => !ids.add(entity.id))) {
      throw const IdentityRepositoryException('duplicate_entity_id');
    }
    final next = Map<String, LifeEntity>.of(_entities[scope] ?? const {});
    final revisions = Map<String, int>.of(_revisions[scope] ?? const {});
    for (final entity in entities) {
      next[entity.id] = entity;
      revisions[entity.id] = 1;
    }
    _entities[scope] = next;
    _revisions[scope] = revisions;
  }

  void indexRelation({
    required IdentityAccountScope scope,
    required String relationKey,
    required String entityId,
  }) {
    validateRepositoryEntityId(entityId);
    if (_entities[scope]?[entityId] == null) {
      throw const IdentityRepositoryException('relation_entity_not_found');
    }
    final normalizedKey = EntityNormalizer.comparisonKey(relationKey);
    if (normalizedKey.isEmpty) {
      throw const IdentityRepositoryException('invalid_relation_key');
    }
    final accountRelations = _relations.putIfAbsent(scope, () => {});
    accountRelations.putIfAbsent(normalizedKey, () => <String>{}).add(entityId);
  }

  bool _matchesQuery(
    LifeEntity entity,
    IdentityRepositoryQuery query,
    Set<String>? relationIds,
  ) {
    if (query.expectedType != null && entity.type != query.expectedType) {
      return false;
    }
    if (!_statusIncluded(entity.status, query)) return false;
    if (query.entityIds.isNotEmpty && !query.entityIds.contains(entity.id)) {
      return false;
    }
    if (relationIds != null && !relationIds.contains(entity.id)) return false;
    final key = query.comparisonKey;
    if (key != null) {
      final labelMatches = entity.comparisonKey == key;
      final aliasMatches = entity.aliases.any((alias) {
        if (alias.comparisonKey != key) return false;
        final date = query.referenceDate;
        return date == null || alias.isActiveAt(date);
      });
      if (!labelMatches && !aliasMatches) return false;
    }
    return true;
  }

  Set<String>? _relationEntityIds(
      IdentityAccountScope scope, List<String> keys) {
    if (keys.isEmpty) return null;
    final result = <String>{};
    final accountRelations = _relations[scope];
    if (accountRelations == null) return result;
    for (final key in keys) {
      result.addAll(accountRelations[key] ?? const {});
    }
    return result;
  }

  bool _statusIncluded(EntityStatus status, IdentityRepositoryQuery query) {
    return switch (status) {
      EntityStatus.active => true,
      EntityStatus.inactive => query.includeInactive,
      EntityStatus.merged => query.includeMerged,
      EntityStatus.deleted => query.includeDeleted,
    };
  }

  void _validateIds(List<String> entityIds) {
    if (entityIds.length > IdentityRepositoryQuery.maximumCandidateLimit) {
      throw const IdentityRepositoryException('candidate_limit_exceeded',
          field: 'entityIds');
    }
    final unique = <String>{};
    for (final id in entityIds) {
      validateRepositoryEntityId(id, field: 'entityIds');
      if (!unique.add(id)) {
        throw const IdentityRepositoryException('duplicate_entity_id',
            field: 'entityIds');
      }
    }
  }
}
