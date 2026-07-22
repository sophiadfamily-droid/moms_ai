import '../../core/identity/entity_identity.dart';
import '../../core/identity/life_entity.dart';
import 'identity_read_repository.dart';
import 'identity_serialization.dart';

abstract final class FirestoreIdentitySerialization {
  static const int maximumDocumentIdLength = 128;
  static const int maximumAliasCount = 20;

  static Map<String, Object?> toDocument({
    required LifeEntity entity,
    required int revision,
  }) {
    if (revision < 1) {
      throw const IdentityRepositoryException('invalid_revision');
    }
    if (entity.aliases.length > maximumAliasCount) {
      throw const IdentityRepositoryException(
        'corrupt_identity_document',
        field: 'aliases',
      );
    }
    final aliasKeys = entity.aliases
        .map((alias) => alias.comparisonKey)
        .toSet()
        .toList(growable: false)
      ..sort();
    return {
      ...IdentitySerialization.toMap(entity),
      'aliasComparisonKeys': aliasKeys,
      'revision': revision,
    };
  }

  static LifeEntity fromDocument({
    required String documentId,
    required Map<String, Object?> data,
  }) {
    _validateDocumentId(documentId);
    final storedId = data['id'];
    if (storedId is! String || storedId != documentId) {
      throw const IdentityRepositoryException('document_id_mismatch');
    }

    final revision = data['revision'];
    if (revision != null && (revision is! int || revision < 1)) {
      throw const IdentityRepositoryException(
        'corrupt_identity_document',
        field: 'revision',
      );
    }
    final schemaVersion = data['schemaVersion'];
    if (schemaVersion is int &&
        schemaVersion > LifeEntity.currentSchemaVersion) {
      throw const IdentityRepositoryException('unsupported_schema_version');
    }

    try {
      final entity = IdentitySerialization.fromMap(data);
      if (entity.aliases.length > maximumAliasCount) {
        throw const IdentityRepositoryException(
          'corrupt_identity_document',
          field: 'aliases',
        );
      }
      _validateAliasComparisonKeys(data['aliasComparisonKeys'], entity);
      return entity;
    } on IdentityRepositoryException {
      rethrow;
    } on IdentitySerializationException catch (error) {
      final code =
          error.code == 'invalid_enum_value' && error.field == 'schemaVersion'
              ? 'unsupported_schema_version'
              : 'corrupt_identity_document';
      throw IdentityRepositoryException(code, causeCode: error.code);
    }
  }

  static void validateDocumentId(String value, {String field = 'entityId'}) {
    try {
      _validateDocumentId(value);
    } on IdentityRepositoryException catch (error) {
      throw IdentityRepositoryException(error.code, field: field);
    }
  }

  static void _validateDocumentId(String value) {
    if (!EntityIdentity.isValid(value) ||
        value != value.trim() ||
        value.length > maximumDocumentIdLength ||
        value.contains('/') ||
        value == '.' ||
        value == '..') {
      throw const IdentityRepositoryException('invalid_entity_id');
    }
  }

  static void _validateAliasComparisonKeys(
    Object? rawKeys,
    LifeEntity entity,
  ) {
    final expected = entity.aliases.map((alias) => alias.comparisonKey).toSet();
    if (rawKeys == null) {
      if (expected.isEmpty) return;
      throw const IdentityRepositoryException(
        'corrupt_identity_document',
        field: 'aliasComparisonKeys',
      );
    }
    if (rawKeys is! List || rawKeys.length > maximumAliasCount) {
      throw const IdentityRepositoryException(
        'corrupt_identity_document',
        field: 'aliasComparisonKeys',
      );
    }
    final actual = <String>{};
    for (final value in rawKeys) {
      if (value is! String || value.isEmpty || !actual.add(value)) {
        throw const IdentityRepositoryException(
          'corrupt_identity_document',
          field: 'aliasComparisonKeys',
        );
      }
    }
    if (actual.length != expected.length || !actual.containsAll(expected)) {
      throw const IdentityRepositoryException(
        'corrupt_identity_document',
        field: 'aliasComparisonKeys',
      );
    }
  }
}
