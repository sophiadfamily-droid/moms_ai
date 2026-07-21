import 'dart:collection';

import '../../core/identity/entity_identity.dart';
import '../../core/identity/entity_normalizer.dart';
import '../../core/identity/entity_types.dart';
import 'identity_repository.dart';

final class IdentityRepositoryQuery {
  static const int maximumCandidateLimit = 20;

  final String? comparisonKey;
  final EntityType? expectedType;
  final int candidateLimit;
  final bool includeInactive;
  final bool includeMerged;
  final bool includeDeleted;
  final List<String> _entityIds;
  final List<String> _relationKeys;
  final DateTime? referenceDate;

  IdentityRepositoryQuery._({
    this.comparisonKey,
    this.expectedType,
    required this.candidateLimit,
    required this.includeInactive,
    required this.includeMerged,
    required this.includeDeleted,
    required List<String> entityIds,
    required List<String> relationKeys,
    this.referenceDate,
  })  : _entityIds = List.unmodifiable(entityIds),
        _relationKeys = List.unmodifiable(relationKeys) {
    if (candidateLimit < 1 || candidateLimit > maximumCandidateLimit) {
      throw const IdentityRepositoryException('candidate_limit_exceeded',
          field: 'candidateLimit');
    }
    if (_entityIds.length > maximumCandidateLimit) {
      throw const IdentityRepositoryException('candidate_limit_exceeded',
          field: 'entityIds');
    }
    if (_entityIds.any((id) => !EntityIdentity.isValid(id))) {
      throw const IdentityRepositoryException('invalid_entity_id',
          field: 'entityIds');
    }
    if (_entityIds.toSet().length != _entityIds.length) {
      throw const IdentityRepositoryException('duplicate_entity_id',
          field: 'entityIds');
    }
    if (_relationKeys.any((key) => key.isEmpty)) {
      throw const IdentityRepositoryException('invalid_relation_key',
          field: 'relationKeys');
    }
    if (comparisonKey == null && _entityIds.isEmpty && _relationKeys.isEmpty) {
      throw const IdentityRepositoryException('invalid_repository_query');
    }
  }

  factory IdentityRepositoryQuery.byComparisonKey({
    required String comparisonKey,
    EntityType? expectedType,
    int candidateLimit = maximumCandidateLimit,
    bool includeInactive = false,
    bool includeMerged = false,
    bool includeDeleted = false,
    DateTime? referenceDate,
  }) {
    final normalizedKey = EntityNormalizer.comparisonKey(comparisonKey);
    if (normalizedKey.isEmpty) {
      throw const IdentityRepositoryException('invalid_comparison_key',
          field: 'comparisonKey');
    }
    return IdentityRepositoryQuery._(
      comparisonKey: normalizedKey,
      expectedType: expectedType,
      candidateLimit: candidateLimit,
      includeInactive: includeInactive,
      includeMerged: includeMerged,
      includeDeleted: includeDeleted,
      entityIds: const [],
      relationKeys: const [],
      referenceDate: referenceDate?.toUtc(),
    );
  }

  factory IdentityRepositoryQuery.byIds({
    required List<String> entityIds,
    EntityType? expectedType,
    int candidateLimit = maximumCandidateLimit,
    bool includeInactive = false,
    bool includeMerged = true,
    bool includeDeleted = false,
  }) =>
      IdentityRepositoryQuery._(
        expectedType: expectedType,
        candidateLimit: candidateLimit,
        includeInactive: includeInactive,
        includeMerged: includeMerged,
        includeDeleted: includeDeleted,
        entityIds: List<String>.of(entityIds),
        relationKeys: const [],
      );

  factory IdentityRepositoryQuery.forRelations({
    required List<String> relationKeys,
    EntityType? expectedType,
    int candidateLimit = maximumCandidateLimit,
    bool includeInactive = false,
    bool includeMerged = false,
    bool includeDeleted = false,
  }) {
    final normalized = relationKeys
        .map(EntityNormalizer.comparisonKey)
        .toList(growable: false);
    return IdentityRepositoryQuery._(
      expectedType: expectedType,
      candidateLimit: candidateLimit,
      includeInactive: includeInactive,
      includeMerged: includeMerged,
      includeDeleted: includeDeleted,
      entityIds: const [],
      relationKeys: normalized,
    );
  }

  List<String> get entityIds => UnmodifiableListView(_entityIds);
  List<String> get relationKeys => UnmodifiableListView(_relationKeys);
}
