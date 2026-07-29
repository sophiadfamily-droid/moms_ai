enum UnderstandingLevel {
  exactMatch,
  normalizedMatch,
  probableMatch,
  ambiguous,
  noMatch,
}

enum NaturalLanguageIntent {
  task,
  event,
  shopping,
  routine,
  memory,
  priority,
  general,
  unknown,
}

enum EntityUnderstanding {
  exactMatch,
  normalizedMatch,
  probableMatch,
  ambiguous,
}

final class NaturalLanguageEntity {
  const NaturalLanguageEntity({
    required this.type,
    required this.originalText,
    required this.normalizedValue,
    required this.understanding,
    required this.provenance,
    this.ambiguityCode,
  });

  final String type;
  final String originalText;
  final String normalizedValue;
  final EntityUnderstanding understanding;
  final String provenance;
  final String? ambiguityCode;
}

final class NaturalLanguageNormalization {
  const NaturalLanguageNormalization({
    required this.originalText,
    required this.normalizedText,
    required this.tokens,
    required this.detectedLanguage,
    required this.normalizationCodes,
    required this.preservedAmbiguities,
  });

  final String originalText;
  final String normalizedText;
  final List<String> tokens;
  final String detectedLanguage;
  final List<String> normalizationCodes;
  final List<String> preservedAmbiguities;
}

final class NaturalLanguageDetection {
  const NaturalLanguageDetection({
    required this.normalization,
    required this.primaryIntent,
    required this.candidateIntents,
    required this.understandingLevel,
    required this.entities,
    required this.actionAllowed,
    required this.intentCode,
    this.ambiguityType,
  });

  final NaturalLanguageNormalization normalization;
  final NaturalLanguageIntent primaryIntent;
  final List<NaturalLanguageIntent> candidateIntents;
  final UnderstandingLevel understandingLevel;
  final List<NaturalLanguageEntity> entities;
  final bool actionAllowed;
  final String intentCode;
  final String? ambiguityType;
}

final class NaturalLanguageClarification {
  const NaturalLanguageClarification({
    required this.ambiguityType,
    required this.candidateIntents,
    required this.extractedEntities,
    required this.missingFields,
    required this.questionText,
    required this.logicalRequestId,
    required this.attempts,
    required this.expiresAt,
    required this.accountScopeId,
  }) : assert(attempts >= 1 && attempts <= maximumAttempts);

  static const int maximumAttempts = 3;

  final String ambiguityType;
  final List<NaturalLanguageIntent> candidateIntents;
  final List<NaturalLanguageEntity> extractedEntities;
  final List<String> missingFields;
  final String questionText;
  final String logicalRequestId;
  final int attempts;
  final DateTime expiresAt;
  final String accountScopeId;
}
