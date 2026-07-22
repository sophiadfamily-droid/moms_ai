import '../../core/identity/entity_identity.dart';
import '../../core/identity/life_entity.dart';
import 'identity_repository_query.dart';
import 'identity_repository_result.dart';

final class IdentityAccountScope {
  final String accountId;

  IdentityAccountScope(String accountId) : accountId = accountId.trim() {
    if (this.accountId.isEmpty) {
      throw const IdentityRepositoryException('invalid_account_scope');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is IdentityAccountScope && other.accountId == accountId;

  @override
  int get hashCode => accountId.hashCode;
}

final class IdentityRepositoryException implements Exception {
  final String code;
  final String? field;
  final String? causeCode;

  const IdentityRepositoryException(this.code, {this.field, this.causeCode});

  @override
  String toString() =>
      'IdentityRepositoryException($code${field == null ? '' : ':$field'})';
}

abstract interface class IdentityReadRepository {
  Future<LifeEntity?> findById({
    required IdentityAccountScope scope,
    required String entityId,
  });

  Future<List<LifeEntity>> findByIds({
    required IdentityAccountScope scope,
    required List<String> entityIds,
  });

  Future<IdentityRepositoryQueryResult> queryCandidates({
    required IdentityAccountScope scope,
    required IdentityRepositoryQuery query,
  });
}

void validateRepositoryEntityId(String entityId, {String field = 'entityId'}) {
  if (!EntityIdentity.isValid(entityId)) {
    throw IdentityRepositoryException('invalid_entity_id', field: field);
  }
}

int compareIdentityEntities(LifeEntity first, LifeEntity second) {
  final typeComparison = first.type.index.compareTo(second.type.index);
  if (typeComparison != 0) return typeComparison;
  final labelComparison = first.comparisonKey.compareTo(second.comparisonKey);
  if (labelComparison != 0) return labelComparison;
  return first.id.compareTo(second.id);
}
