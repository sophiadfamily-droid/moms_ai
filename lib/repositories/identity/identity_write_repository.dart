import '../../core/identity/entity_types.dart';
import '../../core/identity/life_entity.dart';
import 'identity_read_repository.dart';

final class RevisionedIdentity {
  final LifeEntity entity;
  final int revision;

  RevisionedIdentity({required this.entity, required this.revision}) {
    if (revision < 1) {
      throw const IdentityRepositoryException('invalid_revision');
    }
  }
}

abstract interface class IdentityWriteRepository {
  Future<RevisionedIdentity> create({
    required IdentityAccountScope scope,
    required LifeEntity entity,
  });

  Future<RevisionedIdentity> update({
    required IdentityAccountScope scope,
    required LifeEntity entity,
    required int expectedRevision,
  });

  Future<RevisionedIdentity> softDelete({
    required IdentityAccountScope scope,
    required String entityId,
    required int expectedRevision,
    required DateTime updatedAt,
  });
}

abstract final class IdentityWriteValidator {
  static void validateCreate(LifeEntity entity) {
    if (entity.status == EntityStatus.merged ||
        entity.status == EntityStatus.deleted ||
        entity.mergedIntoEntityId != null) {
      throw const IdentityRepositoryException('invalid_status_transition');
    }
  }

  static void validateUpdate({
    required LifeEntity current,
    required LifeEntity next,
    required int expectedRevision,
  }) {
    if (expectedRevision < 1) {
      throw const IdentityRepositoryException('invalid_revision');
    }
    if (current.id != next.id ||
        current.createdAt != next.createdAt ||
        current.type != next.type ||
        current.schemaVersion != next.schemaVersion) {
      throw const IdentityRepositoryException('immutable_field_changed');
    }
    if (!next.updatedAt.isAfter(current.updatedAt)) {
      throw const IdentityRepositoryException('invalid_status_transition');
    }
    if (current.status == EntityStatus.deleted ||
        current.status == EntityStatus.merged ||
        next.status == EntityStatus.merged ||
        next.mergedIntoEntityId != null) {
      throw const IdentityRepositoryException('invalid_status_transition');
    }
  }

  static LifeEntity deletedEntity({
    required LifeEntity current,
    required DateTime updatedAt,
  }) {
    if (current.status == EntityStatus.deleted ||
        current.status == EntityStatus.merged ||
        !updatedAt.isAfter(current.updatedAt)) {
      throw const IdentityRepositoryException('invalid_status_transition');
    }
    return LifeEntity(
      id: current.id,
      type: current.type,
      canonicalLabel: current.canonicalLabel,
      normalizedLabel: current.normalizedLabel,
      aliases: current.aliases,
      status: EntityStatus.deleted,
      source: current.source,
      createdAt: current.createdAt,
      updatedAt: updatedAt.toUtc(),
      metadata: current.metadata,
      schemaVersion: current.schemaVersion,
    );
  }
}
