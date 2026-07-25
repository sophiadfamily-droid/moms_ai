import 'dart:collection';

enum MemoryEvidenceClassification {
  directExplicit,
  ambiguous,
  hypothetical,
  conditional,
  quoted,
  thirdParty,
  pastState,
  temporary,
  correction,
  question,
  negated,
  unknown,
}

enum MemoryEvidenceSubjectType {
  user,
  structuredEntity,
  unresolvedThirdParty,
  unknown,
}

enum MemoryEvidenceRisk {
  ambiguity,
  hypothesis,
  conditional,
  quotation,
  thirdPartyAttribution,
  pastOnly,
  temporaryOnly,
  question,
  negation,
  unknownSubject,
}

final class MemoryEvidenceQualification {
  MemoryEvidenceQualification({
    required this.classification,
    required this.subjectType,
    required this.canConfirmImmediately,
    required this.isCorrection,
    this.subjectEntityId,
    this.statementForMemory,
    Iterable<MemoryEvidenceRisk> risks = const [],
    Iterable<String> reasonCodes = const [],
  })  : risks = UnmodifiableSetView(Set.of(risks)),
        reasonCodes = UnmodifiableListView(List.of(reasonCodes));

  final MemoryEvidenceClassification classification;
  final MemoryEvidenceSubjectType subjectType;
  final String? subjectEntityId;
  final String? statementForMemory;
  final Set<MemoryEvidenceRisk> risks;
  final bool canConfirmImmediately;
  final bool isCorrection;
  final List<String> reasonCodes;

  bool get hasAttributableSubject =>
      subjectType == MemoryEvidenceSubjectType.user ||
      subjectType == MemoryEvidenceSubjectType.structuredEntity;
}
