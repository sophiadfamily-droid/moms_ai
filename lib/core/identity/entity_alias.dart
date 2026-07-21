import 'entity_normalizer.dart';
import 'entity_types.dart';

final class EntityAlias {
  final String value;
  final String normalizedValue;
  final EntityAliasKind kind;
  final EntitySource source;
  final DateTime createdAt;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final DateTime? removedAt;

  EntityAlias({
    required this.value,
    required this.normalizedValue,
    required this.kind,
    required this.source,
    required this.createdAt,
    this.validFrom,
    this.validUntil,
    this.removedAt,
  }) {
    final normalized = EntityNormalizer.normalize(value);
    if (normalized.displayValue.isEmpty) {
      throw const EntityDomainException('empty_alias_value');
    }
    if (normalizedValue != normalized.normalizedLabel) {
      throw const EntityDomainException('incoherent_alias_normalization');
    }
    if (validFrom != null &&
        validUntil != null &&
        validUntil!.isBefore(validFrom!)) {
      throw const EntityDomainException('invalid_alias_validity_range');
    }
    if (removedAt != null && removedAt!.isBefore(createdAt)) {
      throw const EntityDomainException('invalid_alias_removal_date');
    }
    if (kind == EntityAliasKind.temporary && validUntil == null) {
      throw const EntityDomainException('temporary_alias_requires_end_date');
    }
  }

  factory EntityAlias.fromValue({
    required String value,
    required EntityAliasKind kind,
    required EntitySource source,
    required DateTime createdAt,
    DateTime? validFrom,
    DateTime? validUntil,
    DateTime? removedAt,
  }) {
    final normalized = EntityNormalizer.normalize(value);
    return EntityAlias(
      value: normalized.displayValue,
      normalizedValue: normalized.normalizedLabel,
      kind: kind,
      source: source,
      createdAt: createdAt,
      validFrom: validFrom,
      validUntil: validUntil,
      removedAt: removedAt,
    );
  }

  String get comparisonKey => EntityNormalizer.comparisonKey(normalizedValue);

  bool isActiveAt(DateTime referenceDate) {
    if (removedAt != null && !referenceDate.isBefore(removedAt!)) return false;
    if (validFrom != null && referenceDate.isBefore(validFrom!)) return false;
    if (validUntil != null && referenceDate.isAfter(validUntil!)) return false;
    return true;
  }
}
