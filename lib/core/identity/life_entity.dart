import 'dart:collection';

import 'entity_alias.dart';
import 'entity_identity.dart';
import 'entity_normalizer.dart';
import 'entity_types.dart';

final class LifeEntity {
  static const int currentSchemaVersion = 1;

  final String id;
  final EntityType type;
  final String canonicalLabel;
  final String normalizedLabel;
  final List<EntityAlias> _aliases;
  final EntityStatus status;
  final EntitySource source;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, Object?> _metadata;
  final String? mergedIntoEntityId;
  final int schemaVersion;

  LifeEntity({
    required this.id,
    required this.type,
    required this.canonicalLabel,
    required this.normalizedLabel,
    List<EntityAlias> aliases = const [],
    required this.status,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    Map<String, Object?> metadata = const {},
    this.mergedIntoEntityId,
    this.schemaVersion = currentSchemaVersion,
  })  : _aliases = List.unmodifiable(aliases),
        _metadata = _freezeMap(metadata) {
    if (!EntityIdentity.isValid(id)) {
      throw const EntityDomainException('invalid_entity_id');
    }
    final normalized = EntityNormalizer.normalize(canonicalLabel);
    if (normalized.displayValue.isEmpty) {
      throw const EntityDomainException('empty_canonical_label');
    }
    if (normalizedLabel != normalized.normalizedLabel) {
      throw const EntityDomainException('incoherent_entity_normalization');
    }
    if (updatedAt.isBefore(createdAt)) {
      throw const EntityDomainException('invalid_entity_dates');
    }
    if (schemaVersion <= 0) {
      throw const EntityDomainException('invalid_entity_schema_version');
    }
    if (mergedIntoEntityId != null &&
        !EntityIdentity.isValid(mergedIntoEntityId)) {
      throw const EntityDomainException('invalid_merge_target_id');
    }
    if (mergedIntoEntityId == id) {
      throw const EntityDomainException('entity_cannot_merge_into_itself');
    }
    if (status == EntityStatus.merged && mergedIntoEntityId == null) {
      throw const EntityDomainException('merged_entity_requires_target');
    }
    if (status != EntityStatus.merged && mergedIntoEntityId != null) {
      throw const EntityDomainException('merge_target_requires_merged_status');
    }
    final activeKeys = <String>{};
    for (final alias in _aliases) {
      if (!alias.isActiveAt(updatedAt)) continue;
      if (!activeKeys.add(alias.comparisonKey)) {
        throw const EntityDomainException('duplicate_active_alias');
      }
    }
  }

  factory LifeEntity.fromLabel({
    required String id,
    required EntityType type,
    required String canonicalLabel,
    List<EntityAlias> aliases = const [],
    EntityStatus status = EntityStatus.active,
    required EntitySource source,
    required DateTime createdAt,
    required DateTime updatedAt,
    Map<String, Object?> metadata = const {},
    String? mergedIntoEntityId,
    int schemaVersion = currentSchemaVersion,
  }) {
    final normalized = EntityNormalizer.normalize(canonicalLabel);
    return LifeEntity(
      id: id,
      type: type,
      canonicalLabel: normalized.displayValue,
      normalizedLabel: normalized.normalizedLabel,
      aliases: aliases,
      status: status,
      source: source,
      createdAt: createdAt,
      updatedAt: updatedAt,
      metadata: metadata,
      mergedIntoEntityId: mergedIntoEntityId,
      schemaVersion: schemaVersion,
    );
  }

  List<EntityAlias> get aliases => UnmodifiableListView(_aliases);
  Map<String, Object?> get metadata => UnmodifiableMapView(_metadata);
  String get comparisonKey => EntityNormalizer.comparisonKey(normalizedLabel);
  bool get isNormallyResolvable => status == EntityStatus.active;
}

Map<String, Object?> _freezeMap(Map<String, Object?> source) =>
    Map.unmodifiable(
      source.map((key, value) => MapEntry(key, _freeze(value))),
    );

Object? _freeze(Object? value) {
  if (value is Map) {
    return Map.unmodifiable(
      value.map((key, child) => MapEntry(key.toString(), _freeze(child))),
    );
  }
  if (value is List) return List.unmodifiable(value.map(_freeze));
  if (value is Set) return Set.unmodifiable(value.map(_freeze));
  return value;
}
