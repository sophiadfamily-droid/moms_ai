import 'dart:collection';

import 'life_context_provenance.dart';

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
  final MemoryConfirmationStatus confirmationStatus;
  final double? confidence;
  final LifeContextSensitivity sensitivity;
  final LifeContextEvidenceType evidenceType;
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
    this.confidence,
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
        'confirmationStatus': confirmationStatus.name,
        'confidence': confidence,
        'sensitivity': sensitivity.name,
        'evidenceType': evidenceType.name,
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
  final List<LifeMemoryFact> memories;

  const MemoryContext._(this.memories);

  static const empty = MemoryContext._([]);

  factory MemoryContext({List<LifeMemoryFact> memories = const []}) {
    return MemoryContext._(List.unmodifiable(memories));
  }

  bool get isEmpty => memories.isEmpty;

  Map<String, dynamic> toJson() => {
        'memories': memories.map((memory) => memory.toJson()).toList(),
      };
}
