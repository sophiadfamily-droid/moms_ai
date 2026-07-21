import 'entity_identity.dart';
import 'entity_normalizer.dart';
import 'entity_types.dart';

final class EntityReference {
  final String? rawValue;
  final String? normalizedValue;
  final EntityReferenceKind kind;
  final EntityType? expectedType;
  final String? explicitEntityId;
  final String? relationKey;
  final String? conversationTargetEntityId;
  final EntitySource source;

  EntityReference({
    this.rawValue,
    this.normalizedValue,
    required this.kind,
    this.expectedType,
    this.explicitEntityId,
    this.relationKey,
    this.conversationTargetEntityId,
    required this.source,
  }) {
    if (kind == EntityReferenceKind.explicitId) {
      if (!EntityIdentity.isValid(explicitEntityId)) {
        throw const EntityDomainException('explicit_reference_requires_id');
      }
    } else {
      final normalized = EntityNormalizer.normalize(rawValue ?? '');
      if (normalized.displayValue.isEmpty) {
        throw const EntityDomainException('text_reference_requires_value');
      }
      if (normalizedValue != normalized.normalizedLabel) {
        throw const EntityDomainException('incoherent_reference_normalization');
      }
    }
    if (conversationTargetEntityId != null &&
        !EntityIdentity.isValid(conversationTargetEntityId)) {
      throw const EntityDomainException('invalid_conversation_target_id');
    }
    if (kind == EntityReferenceKind.relationalExpression &&
        (relationKey == null || relationKey!.trim().isEmpty)) {
      throw const EntityDomainException('relational_reference_requires_key');
    }
  }

  factory EntityReference.byId({
    required String entityId,
    EntityType? expectedType,
    required EntitySource source,
  }) {
    return EntityReference(
      kind: EntityReferenceKind.explicitId,
      expectedType: expectedType,
      explicitEntityId: entityId,
      source: source,
    );
  }

  factory EntityReference.text({
    required String value,
    required EntityReferenceKind kind,
    EntityType? expectedType,
    String? relationKey,
    String? conversationTargetEntityId,
    required EntitySource source,
  }) {
    final normalized = EntityNormalizer.normalize(value);
    return EntityReference(
      rawValue: normalized.displayValue,
      normalizedValue: normalized.normalizedLabel,
      kind: kind,
      expectedType: expectedType,
      relationKey: relationKey,
      conversationTargetEntityId: conversationTargetEntityId,
      source: source,
    );
  }

  String? get comparisonKey => normalizedValue == null
      ? null
      : EntityNormalizer.comparisonKey(normalizedValue!);
}
