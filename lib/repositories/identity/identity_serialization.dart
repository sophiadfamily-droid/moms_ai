import '../../core/identity/entity_alias.dart';
import '../../core/identity/entity_normalizer.dart';
import '../../core/identity/entity_types.dart';
import '../../core/identity/life_entity.dart';

final class IdentitySerializationException implements Exception {
  final String code;
  final String? field;
  final String? causeCode;

  const IdentitySerializationException(this.code, {this.field, this.causeCode});

  @override
  String toString() =>
      'IdentitySerializationException($code${field == null ? '' : ':$field'})';
}

abstract final class IdentitySerialization {
  static Map<String, Object?> toMap(LifeEntity entity) => {
        'id': entity.id,
        'type': entity.type.name,
        'canonicalLabel': entity.canonicalLabel,
        'normalizedLabel': entity.normalizedLabel,
        'aliases': entity.aliases.map(_aliasToMap).toList(growable: false),
        'status': entity.status.name,
        'source': _sourceToMap(entity.source),
        'createdAt': _dateToString(entity.createdAt),
        'updatedAt': _dateToString(entity.updatedAt),
        'metadata': _copyMap(entity.metadata),
        if (entity.mergedIntoEntityId != null)
          'mergedIntoEntityId': entity.mergedIntoEntityId,
        'schemaVersion': entity.schemaVersion,
      };

  static LifeEntity fromMap(Map<String, Object?> map) {
    try {
      final id = _requiredString(map, 'id');
      final canonicalLabel = _requiredString(map, 'canonicalLabel');
      final createdAt = _requiredDate(map, 'createdAt');
      final normalizedLabel = map.containsKey('normalizedLabel')
          ? _requiredString(map, 'normalizedLabel')
          : EntityNormalizer.normalize(canonicalLabel).normalizedLabel;
      final updatedAt = map.containsKey('updatedAt')
          ? _requiredDate(map, 'updatedAt')
          : createdAt;
      final aliases = map.containsKey('aliases')
          ? _aliasesFrom(map['aliases'])
          : const <EntityAlias>[];
      final metadata = map.containsKey('metadata')
          ? _metadataFrom(map['metadata'])
          : const <String, Object?>{};
      final schemaVersion = map.containsKey('schemaVersion')
          ? _requiredInt(map, 'schemaVersion')
          : 1;
      final mergedIntoEntityId = map.containsKey('mergedIntoEntityId')
          ? _nullableString(map, 'mergedIntoEntityId')
          : null;

      return LifeEntity(
        id: id,
        type: map.containsKey('type')
            ? _enumValue(EntityType.values, map['type'], 'type')
            : EntityType.unknown,
        canonicalLabel: canonicalLabel,
        normalizedLabel: normalizedLabel,
        aliases: aliases,
        status: map.containsKey('status')
            ? _enumValue(EntityStatus.values, map['status'], 'status')
            : EntityStatus.active,
        source: map.containsKey('source')
            ? _sourceFrom(map['source'])
            : const EntitySource(type: EntitySourceType.historical),
        createdAt: createdAt,
        updatedAt: updatedAt,
        metadata: metadata,
        mergedIntoEntityId: mergedIntoEntityId,
        schemaVersion: schemaVersion,
      );
    } on IdentitySerializationException {
      rethrow;
    } on EntityDomainException catch (error) {
      throw IdentitySerializationException('invalid_serialized_entity',
          causeCode: error.code);
    }
  }

  static Map<String, Object?> _aliasToMap(EntityAlias alias) => {
        'value': alias.value,
        'normalizedValue': alias.normalizedValue,
        'kind': alias.kind.name,
        'source': _sourceToMap(alias.source),
        'createdAt': _dateToString(alias.createdAt),
        if (alias.validFrom != null)
          'validFrom': _dateToString(alias.validFrom!),
        if (alias.validUntil != null)
          'validUntil': _dateToString(alias.validUntil!),
        if (alias.removedAt != null)
          'removedAt': _dateToString(alias.removedAt!),
      };

  static EntityAlias _aliasFrom(Object? value, int index) {
    final map = _stringMap(value, 'aliases[$index]');
    try {
      final original = _requiredString(map, 'value', prefix: 'aliases[$index]');
      return EntityAlias(
        value: original,
        normalizedValue: map.containsKey('normalizedValue')
            ? _requiredString(map, 'normalizedValue', prefix: 'aliases[$index]')
            : EntityNormalizer.normalize(original).normalizedLabel,
        kind: _enumValue(
            EntityAliasKind.values, map['kind'], 'aliases[$index].kind'),
        source: map.containsKey('source')
            ? _sourceFrom(map['source'], prefix: 'aliases[$index].source')
            : const EntitySource(type: EntitySourceType.historical),
        createdAt: _requiredDate(map, 'createdAt', prefix: 'aliases[$index]'),
        validFrom: _optionalDate(map, 'validFrom', prefix: 'aliases[$index]'),
        validUntil: _optionalDate(map, 'validUntil', prefix: 'aliases[$index]'),
        removedAt: _optionalDate(map, 'removedAt', prefix: 'aliases[$index]'),
      );
    } on EntityDomainException catch (error) {
      throw IdentitySerializationException('invalid_serialized_alias',
          field: 'aliases[$index]', causeCode: error.code);
    }
  }

  static List<EntityAlias> _aliasesFrom(Object? value) {
    if (value is! List) {
      throw const IdentitySerializationException('invalid_field_type',
          field: 'aliases');
    }
    return List.unmodifiable([
      for (var index = 0; index < value.length; index++)
        _aliasFrom(value[index], index),
    ]);
  }

  static Map<String, Object?> _sourceToMap(EntitySource source) => {
        'type': source.type.name,
        if (source.sourceId != null) 'reference': source.sourceId,
      };

  static EntitySource _sourceFrom(Object? value, {String prefix = 'source'}) {
    final map = _stringMap(value, prefix);
    return EntitySource(
      type: _enumValue(EntitySourceType.values, map['type'], '$prefix.type'),
      sourceId: map.containsKey('reference')
          ? _nullableString(map, 'reference', prefix: prefix)
          : null,
    );
  }

  static T _enumValue<T extends Enum>(
      List<T> values, Object? value, String field) {
    if (value is! String) {
      throw IdentitySerializationException('invalid_field_type', field: field);
    }
    for (final candidate in values) {
      if (candidate.name == value) return candidate;
    }
    throw IdentitySerializationException('invalid_enum_value', field: field);
  }

  static String _requiredString(Map<String, Object?> map, String field,
      {String? prefix}) {
    final value = map[field];
    if (value is! String) {
      throw IdentitySerializationException('invalid_field_type',
          field: _field(prefix, field));
    }
    if (value.trim().isEmpty) {
      throw IdentitySerializationException('invalid_serialized_entity',
          field: _field(prefix, field));
    }
    return value;
  }

  static String? _nullableString(Map<String, Object?> map, String field,
      {String? prefix}) {
    final value = map[field];
    if (value == null) return null;
    if (value is! String) {
      throw IdentitySerializationException('invalid_field_type',
          field: _field(prefix, field));
    }
    return value;
  }

  static int _requiredInt(Map<String, Object?> map, String field) {
    final value = map[field];
    if (value is! int) {
      throw IdentitySerializationException('invalid_field_type', field: field);
    }
    return value;
  }

  static DateTime _requiredDate(Map<String, Object?> map, String field,
      {String? prefix}) {
    final value = map[field];
    if (value is! String) {
      throw IdentitySerializationException('invalid_field_type',
          field: _field(prefix, field));
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw IdentitySerializationException('invalid_date_value',
          field: _field(prefix, field));
    }
    return parsed.toUtc();
  }

  static DateTime? _optionalDate(Map<String, Object?> map, String field,
      {String? prefix}) {
    if (!map.containsKey(field) || map[field] == null) return null;
    return _requiredDate(map, field, prefix: prefix);
  }

  static Map<String, Object?> _metadataFrom(Object? value) =>
      _copyMap(_stringMap(value, 'metadata'));

  static Map<String, Object?> _stringMap(Object? value, String field) {
    if (value is! Map) {
      throw IdentitySerializationException('invalid_field_type', field: field);
    }
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw IdentitySerializationException('invalid_field_type',
            field: field);
      }
      result[entry.key as String] = entry.value;
    }
    return result;
  }

  static String _dateToString(DateTime date) => date.toUtc().toIso8601String();
  static String _field(String? prefix, String field) =>
      prefix == null ? field : '$prefix.$field';
}

Map<String, Object?> _copyMap(Map<String, Object?> source) => Map.unmodifiable(
      source.map((key, value) => MapEntry(key, _copyValue(value))),
    );

Object? _copyValue(Object? value) {
  if (value is Map) {
    return Map.unmodifiable(value.map(
      (key, child) => MapEntry(key.toString(), _copyValue(child)),
    ));
  }
  if (value is List) return List.unmodifiable(value.map(_copyValue));
  if (value is Set) return Set.unmodifiable(value.map(_copyValue));
  return value;
}
