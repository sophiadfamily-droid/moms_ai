import 'dart:collection';

import 'life_context_provenance.dart';
import '../memory_lifecycle_state.dart';
import '../memory_semantic_identity.dart';

enum LifeMemorySemanticType {
  fact,
  preference,
  routine,
  constraint,
  goal,
  decision,
  temporary,
  relationship,
  unknown,
}

enum MemoryConfirmationStatus {
  unconfirmed,
  confirmed,
  inferred,
  rejected,
  obsolete,
}

enum MemoryConsumptionTrust {
  legacyTrusted,
  modernValid,
  legacyQuarantined,
  invalidModern,
}

final class LifeMemoryFact {
  final String id;
  final String text;
  final String normalizedText;
  final LifeMemorySemanticType semanticType;
  final String category;
  final int importance;
  final LifeContextSourceType sourceType;
  final String? sourceId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final int schemaVersion;
  final MemoryConsumptionTrust consumptionTrust;
  final bool hasInvalidExpiration;
  final bool hasRestrictedSecret;
  final MemoryConfirmationStatus confirmationStatus;
  final MemoryLifecycleState lifecycleState;
  final bool lifecycleStateIsExplicit;
  final double? confidence;
  final LifeContextSensitivity sensitivity;
  final LifeContextEvidenceType evidenceType;
  final bool isExplicitHealth;
  final DateTime? lastConfirmedAt;
  final String? structuredDomain;
  final String? structuredReferenceId;
  final MemorySemanticIdentityReadResult semanticIdentityRead;
  final Map<String, Object?> _legacyData;

  LifeMemoryFact({
    required this.id,
    required this.text,
    required this.normalizedText,
    required this.semanticType,
    required this.category,
    required this.importance,
    required this.sourceType,
    required this.confirmationStatus,
    required this.sensitivity,
    required this.evidenceType,
    this.sourceId,
    this.createdAt,
    this.updatedAt,
    this.validFrom,
    this.validUntil,
    this.schemaVersion = 0,
    this.consumptionTrust = MemoryConsumptionTrust.legacyQuarantined,
    this.hasInvalidExpiration = false,
    this.hasRestrictedSecret = false,
    this.confidence,
    this.lifecycleState = MemoryLifecycleState.proposed,
    this.lifecycleStateIsExplicit = false,
    this.isExplicitHealth = false,
    this.lastConfirmedAt,
    this.structuredDomain,
    this.structuredReferenceId,
    this.semanticIdentityRead = MemorySemanticIdentityReadResult.absent,
    Map<String, Object?> legacyData = const {},
  }) : _legacyData = _freezeMap(legacyData);

  Map<String, Object?> get legacyData => UnmodifiableMapView(_legacyData);

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'normalizedText': normalizedText,
        'semanticType': semanticType.name,
        'category': category,
        'importance': importance,
        'sourceType': sourceType.name,
        'sourceId': sourceId,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'validFrom': validFrom?.toIso8601String(),
        'validUntil': validUntil?.toIso8601String(),
        'schemaVersion': schemaVersion,
        'consumptionTrust': consumptionTrust.name,
        'hasInvalidExpiration': hasInvalidExpiration,
        'hasRestrictedSecret': hasRestrictedSecret,
        'confirmationStatus': confirmationStatus.name,
        'lifecycleState': lifecycleState.name,
        'lifecycleStateIsExplicit': lifecycleStateIsExplicit,
        'confidence': confidence,
        'sensitivity': sensitivity.name,
        'evidenceType': evidenceType.name,
        'isExplicitHealth': isExplicitHealth,
        if (lastConfirmedAt != null)
          'lastConfirmedAt': lastConfirmedAt!.toIso8601String(),
        if (structuredDomain != null) 'structuredDomain': structuredDomain,
        if (structuredReferenceId != null)
          'structuredReferenceId': structuredReferenceId,
        'semanticIdentityStatus': semanticIdentityRead.status.name,
        if (semanticIdentityRead.identity != null)
          'semanticIdentity': semanticIdentityRead.identity!.toJson(),
        if (_legacyData.isNotEmpty) 'legacyData': _copyMap(_legacyData),
      };

  static Map<String, Object?> _freezeMap(Map<String, Object?> source) {
    return Map.unmodifiable(
      source.map((key, value) => MapEntry(key, _freeze(value))),
    );
  }

  static Object? _freeze(Object? value) {
    if (value is Map) {
      return Map.unmodifiable(
        value.map((key, child) => MapEntry(key.toString(), _freeze(child))),
      );
    }
    if (value is List) return List.unmodifiable(value.map(_freeze));
    if (value is Set) return Set.unmodifiable(value.map(_freeze));
    return value;
  }

  static Map<String, Object?> _copyMap(Map<String, Object?> source) {
    return source.map((key, value) => MapEntry(key, _copy(value)));
  }

  static Object? _copy(Object? value) {
    if (value is Map) {
      return value.map((key, child) => MapEntry(key.toString(), _copy(child)));
    }
    if (value is Iterable) return value.map(_copy).toList();
    return value;
  }
}

final class MemoryContext {
  static const int currentSchemaVersion = 1;

  final List<LifeMemoryFact> memories;
  final int schemaVersion;

  const MemoryContext._(this.memories, this.schemaVersion);

  static const empty = MemoryContext._([], currentSchemaVersion);

  factory MemoryContext({
    List<LifeMemoryFact> memories = const [],
    int schemaVersion = currentSchemaVersion,
  }) {
    if (schemaVersion != currentSchemaVersion) {
      throw const FormatException('unsupported_memory_context_version');
    }
    return MemoryContext._(List.unmodifiable(memories), schemaVersion);
  }

  bool get isEmpty => memories.isEmpty;

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'memories': memories.map((memory) => memory.toJson()).toList(),
      };
}
