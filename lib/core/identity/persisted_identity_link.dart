import 'entity_identity.dart';
import 'entity_types.dart';

final class PersistedIdentityLink {
  static const int currentSchemaVersion = 1;

  final String entityId;
  final EntityType entityType;
  final int schemaVersion;

  PersistedIdentityLink({
    required this.entityId,
    required this.entityType,
    this.schemaVersion = currentSchemaVersion,
  }) {
    if (!EntityIdentity.isValid(entityId)) {
      throw const EntityDomainException(
        'invalid_persisted_identity_link_entity_id',
      );
    }
    if (entityType == EntityType.unknown) {
      throw const EntityDomainException(
        'invalid_persisted_identity_link_entity_type',
      );
    }
    if (schemaVersion < 1 || schemaVersion > currentSchemaVersion) {
      throw const EntityDomainException(
        'invalid_persisted_identity_link_schema_version',
      );
    }
  }

  PersistedIdentityLink copyWith({
    String? entityId,
    EntityType? entityType,
    int? schemaVersion,
  }) {
    return PersistedIdentityLink(
      entityId: entityId ?? this.entityId,
      entityType: entityType ?? this.entityType,
      schemaVersion: schemaVersion ?? this.schemaVersion,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PersistedIdentityLink &&
            other.entityId == entityId &&
            other.entityType == entityType &&
            other.schemaVersion == schemaVersion;
  }

  @override
  int get hashCode => Object.hash(entityId, entityType, schemaVersion);

  @override
  String toString() => 'PersistedIdentityLink(type: ${entityType.name}, '
      'schemaVersion: $schemaVersion)';
}
