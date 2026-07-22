import 'dart:collection';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/identity/entity_types.dart';
import '../../core/identity/life_entity.dart';
import 'firestore_identity_serialization.dart';
import 'identity_read_repository.dart';
import 'identity_repository_query.dart';
import 'identity_repository_result.dart';

final class FirestoreIdentityReadRepository implements IdentityReadRepository {
  final FirebaseFirestore _firestore;

  const FirestoreIdentityReadRepository({
    required FirebaseFirestore firestore,
  }) : _firestore = firestore;

  @override
  Future<LifeEntity?> findById({
    required IdentityAccountScope scope,
    required String entityId,
  }) async {
    FirestoreIdentitySerialization.validateDocumentId(entityId);
    try {
      final snapshot = await _collection(scope).doc(entityId).get();
      final data = snapshot.data();
      if (!snapshot.exists || data == null) return null;
      return FirestoreIdentitySerialization.fromDocument(
        documentId: snapshot.id,
        data: Map<String, Object?>.from(data),
      );
    } on IdentityRepositoryException {
      rethrow;
    } on FirebaseException catch (error) {
      throw _mapFirebaseError(error);
    }
  }

  @override
  Future<List<LifeEntity>> findByIds({
    required IdentityAccountScope scope,
    required List<String> entityIds,
  }) async {
    if (entityIds.length > IdentityRepositoryQuery.maximumCandidateLimit) {
      throw const IdentityRepositoryException(
        'candidate_limit_exceeded',
        field: 'entityIds',
      );
    }
    final uniqueIds = <String>[];
    final seen = <String>{};
    for (final id in entityIds) {
      FirestoreIdentitySerialization.validateDocumentId(
        id,
        field: 'entityIds',
      );
      if (seen.add(id)) uniqueIds.add(id);
    }
    if (uniqueIds.isEmpty) return const [];

    try {
      final snapshot = await _collection(scope)
          .where(FieldPath.documentId, whereIn: uniqueIds)
          .get();
      if (snapshot.metadata.isFromCache) {
        throw const IdentityRepositoryException('repository_unavailable');
      }
      final entities = snapshot.docs.map(_decode).toList(growable: false)
        ..sort(compareIdentityEntities);
      return UnmodifiableListView(entities);
    } on IdentityRepositoryException {
      rethrow;
    } on FirebaseException catch (error) {
      throw _mapFirebaseError(error);
    }
  }

  @override
  Future<IdentityRepositoryQueryResult> queryCandidates({
    required IdentityAccountScope scope,
    required IdentityRepositoryQuery query,
  }) async {
    if (query.relationKeys.isNotEmpty) {
      throw const IdentityRepositoryException('query_not_supported');
    }
    if (query.entityIds.isNotEmpty) {
      final entities =
          await findByIds(scope: scope, entityIds: query.entityIds);
      return _result(_filter(entities, query), query);
    }
    final key = query.comparisonKey;
    if (key == null) {
      throw const IdentityRepositoryException('query_not_supported');
    }

    try {
      final fetchLimit = query.candidateLimit + 1;
      final base = _collection(scope);
      final canonical = await _applyFilters(
        base.where('normalizedLabel', isEqualTo: key),
        query,
      ).limit(fetchLimit).get();
      final aliases = await _applyFilters(
        base.where('aliasComparisonKeys', arrayContains: key),
        query,
      ).limit(fetchLimit).get();
      if (canonical.metadata.isFromCache || aliases.metadata.isFromCache) {
        throw const IdentityRepositoryException('repository_unavailable');
      }

      final byId = <String, LifeEntity>{};
      for (final document in [...canonical.docs, ...aliases.docs]) {
        final entity = _decode(document);
        if (_matchesStatus(entity.status, query)) byId[entity.id] = entity;
      }
      return _result(byId.values.toList(growable: false), query);
    } on IdentityRepositoryException {
      rethrow;
    } on FirebaseException catch (error) {
      throw _mapFirebaseError(error);
    }
  }

  CollectionReference<Map<String, dynamic>> _collection(
    IdentityAccountScope scope,
  ) {
    FirestoreIdentitySerialization.validateDocumentId(
      scope.accountId,
      field: 'accountId',
    );
    return _firestore
        .collection('users')
        .doc(scope.accountId)
        .collection('identities');
  }

  Query<Map<String, dynamic>> _applyFilters(
    Query<Map<String, dynamic>> query,
    IdentityRepositoryQuery value,
  ) {
    var result = query;
    if (value.expectedType != null) {
      result = result.where('type', isEqualTo: value.expectedType!.name);
    }
    final statuses = <String>[
      EntityStatus.active.name,
      if (value.includeInactive) EntityStatus.inactive.name,
      if (value.includeMerged) EntityStatus.merged.name,
      if (value.includeDeleted) EntityStatus.deleted.name,
    ];
    return statuses.length == 1
        ? result.where('status', isEqualTo: statuses.single)
        : result.where('status', whereIn: statuses);
  }

  LifeEntity _decode(QueryDocumentSnapshot<Map<String, dynamic>> snapshot) =>
      FirestoreIdentitySerialization.fromDocument(
        documentId: snapshot.id,
        data: Map<String, Object?>.from(snapshot.data()),
      );

  List<LifeEntity> _filter(
    List<LifeEntity> entities,
    IdentityRepositoryQuery query,
  ) =>
      entities
          .where((entity) =>
              (query.expectedType == null ||
                  entity.type == query.expectedType) &&
              _matchesStatus(entity.status, query))
          .toList(growable: false);

  bool _matchesStatus(EntityStatus status, IdentityRepositoryQuery query) =>
      switch (status) {
        EntityStatus.active => true,
        EntityStatus.inactive => query.includeInactive,
        EntityStatus.merged => query.includeMerged,
        EntityStatus.deleted => query.includeDeleted,
      };

  IdentityRepositoryQueryResult _result(
    List<LifeEntity> entities,
    IdentityRepositoryQuery query,
  ) {
    entities.sort(compareIdentityEntities);
    final limitReached = entities.length > query.candidateLimit;
    return IdentityRepositoryQueryResult(
      entities: entities.take(query.candidateLimit).toList(growable: false),
      limitReached: limitReached,
      requestedLimit: query.candidateLimit,
    );
  }

  IdentityRepositoryException _mapFirebaseError(FirebaseException error) {
    final code = switch (error.code) {
      'permission-denied' => 'permission_denied',
      'deadline-exceeded' => 'repository_timeout',
      'unavailable' => 'repository_unavailable',
      'unauthenticated' => 'unauthenticated',
      _ => 'repository_unavailable',
    };
    return IdentityRepositoryException(code, causeCode: error.code);
  }
}
