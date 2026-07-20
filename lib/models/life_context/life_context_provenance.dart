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

final class LifeContextFact<T> {
  final T value;
  final LifeContextProvenance provenance;

  const LifeContextFact({
    required this.value,
    required this.provenance,
  });

  Map<String, dynamic> toJson([Object? Function(T value)? encode]) => {
        'value': encode == null ? value : encode(value),
        'provenance': provenance.toJson(),
      };
}

final class LifeContextStringListFact {
  final List<String> value;
  final LifeContextProvenance provenance;

  LifeContextStringListFact({
    required List<String> value,
    required this.provenance,
  }) : value = List.unmodifiable(value);

  Map<String, dynamic> toJson() => {
        'value': value,
        'provenance': provenance.toJson(),
      };
}
