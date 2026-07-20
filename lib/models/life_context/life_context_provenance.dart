enum LifeContextSourceType {
  profile,
  memory,
  event,
  routine,
  currentInstruction,
  derived,
}

enum LifeContextEvidenceType {
  explicit,
  historical,
  derived,
}

final class LifeContextProvenance {
  final LifeContextSourceType sourceType;
  final String? sourceId;
  final DateTime? updatedAt;
  final LifeContextEvidenceType evidenceType;

  const LifeContextProvenance({
    required this.sourceType,
    required this.evidenceType,
    this.sourceId,
    this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'sourceType': sourceType.name,
        'sourceId': sourceId,
        'updatedAt': updatedAt?.toIso8601String(),
        'evidenceType': evidenceType.name,
      };
}

enum LifeContextSensitivity {
  standard,
  sensitive,
}

final class LifeContextFact<T> {
  final T value;
  final LifeContextProvenance provenance;
  final LifeContextSensitivity sensitivity;
  final double? confidence;

  const LifeContextFact({
    required this.value,
    required this.provenance,
    this.sensitivity = LifeContextSensitivity.standard,
    this.confidence,
  });

  Map<String, dynamic> toJson([Object? Function(T value)? encode]) => {
        'value': encode == null ? value : encode(value),
        'provenance': provenance.toJson(),
        'sensitivity': sensitivity.name,
        'confidence': confidence,
      };
}

final class LifeContextStringListFact {
  final List<String> value;
  final LifeContextProvenance provenance;
  final LifeContextSensitivity sensitivity;
  final double? confidence;

  LifeContextStringListFact({
    required List<String> value,
    required this.provenance,
    this.sensitivity = LifeContextSensitivity.standard,
    this.confidence,
  }) : value = List.unmodifiable(value);

  Map<String, dynamic> toJson() => {
        'value': value,
        'provenance': provenance.toJson(),
        'sensitivity': sensitivity.name,
        'confidence': confidence,
      };
}
