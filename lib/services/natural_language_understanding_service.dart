import '../models/natural_language_models.dart';
import 'natural_date_service.dart';
import 'natural_duration_service.dart';
import 'natural_language_normalizer.dart';
import 'natural_time_service.dart';

class NaturalLanguageUnderstandingResult {
  final String originalText;
  final String dateIso;
  final String time;
  final int durationMinutes;
  final bool hasDate;
  final bool hasTime;
  final bool hasDuration;
  final bool expressesUncertainty;
  final double confidence;
  final NaturalLanguageNormalization normalization;
  final UnderstandingLevel understandingLevel;
  final List<NaturalLanguageEntity> entities;

  const NaturalLanguageUnderstandingResult({
    required this.originalText,
    required this.dateIso,
    required this.time,
    required this.durationMinutes,
    required this.hasDate,
    required this.hasTime,
    required this.hasDuration,
    required this.expressesUncertainty,
    required this.confidence,
    required this.normalization,
    required this.understandingLevel,
    required this.entities,
  });

  Map<String, dynamic> toJson() {
    return {
      "originalText": originalText,
      "dateIso": dateIso,
      "time": time,
      "durationMinutes": durationMinutes,
      "hasDate": hasDate,
      "hasTime": hasTime,
      "hasDuration": hasDuration,
      "expressesUncertainty": expressesUncertainty,
      "confidence": confidence,
      "normalizedText": normalization.normalizedText,
      "normalizationCodes": normalization.normalizationCodes,
      "preservedAmbiguities": normalization.preservedAmbiguities,
      "understandingLevel": understandingLevel.name,
    };
  }
}

class NaturalLanguageUnderstandingService {
  static NaturalLanguageUnderstandingResult parse(
    String text, {
    String fallbackIsoDate = "",
    DateTime? now,
  }) {
    final normalization = const NaturalLanguageNormalizer().normalize(text);
    final normalized = normalization.normalizedText;

    final dateIso = NaturalDateService.resolveDateFromText(
      text,
      fallbackIsoDate: fallbackIsoDate,
      now: now,
    );

    final time = NaturalTimeService.parseTime(text);
    final durationMinutes = NaturalDurationService.parseMinutes(text);
    final uncertainty = expressesUncertainty(text);

    final hasDate = dateIso.trim().isNotEmpty;
    final hasTime = time.trim().isNotEmpty;
    final hasDuration = durationMinutes > 0;

    final confidence = _computeConfidence(
      normalizedText: normalized,
      hasDate: hasDate,
      hasTime: hasTime,
      hasDuration: hasDuration,
      expressesUncertainty: uncertainty,
    );
    final entities = <NaturalLanguageEntity>[
      if (hasDate)
        NaturalLanguageEntity(
          type: 'date',
          originalText: text,
          normalizedValue: dateIso,
          understanding: normalization.normalizationCodes.isEmpty
              ? EntityUnderstanding.exactMatch
              : EntityUnderstanding.normalizedMatch,
          provenance: 'deterministic_date_parser',
        ),
      if (hasTime)
        NaturalLanguageEntity(
          type: 'time',
          originalText: text,
          normalizedValue: time,
          understanding: normalization.normalizationCodes.isEmpty
              ? EntityUnderstanding.exactMatch
              : EntityUnderstanding.normalizedMatch,
          provenance: 'deterministic_time_parser',
        ),
      if (hasDuration)
        NaturalLanguageEntity(
          type: 'duration',
          originalText: text,
          normalizedValue: durationMinutes.toString(),
          understanding: EntityUnderstanding.exactMatch,
          provenance: 'deterministic_duration_parser',
        ),
    ];
    final understandingLevel = normalization.preservedAmbiguities.isNotEmpty
        ? UnderstandingLevel.ambiguous
        : entities.isEmpty
            ? UnderstandingLevel.noMatch
            : normalization.normalizationCodes.isEmpty
                ? UnderstandingLevel.exactMatch
                : UnderstandingLevel.normalizedMatch;

    return NaturalLanguageUnderstandingResult(
      originalText: text,
      dateIso: dateIso,
      time: time,
      durationMinutes: durationMinutes,
      hasDate: hasDate,
      hasTime: hasTime,
      hasDuration: hasDuration,
      expressesUncertainty: uncertainty,
      confidence: confidence,
      normalization: normalization,
      understandingLevel: understandingLevel,
      entities: List.unmodifiable(entities),
    );
  }

  static bool expressesUncertainty(String text) {
    final lower = _normalize(text);

    return _containsAny(lower, [
      "je sais pas",
      "je ne sais pas",
      "jsp",
      "aucune idee",
      "pas sure",
      "pas sur",
      "comme tu veux",
      "a toi de voir",
      "quand tu veux",
      "quand tu peux",
      "n'importe quand",
      "peu importe",
      "je connais pas",
      "je ne connais pas",
    ]);
  }

  static double _computeConfidence({
    required String normalizedText,
    required bool hasDate,
    required bool hasTime,
    required bool hasDuration,
    required bool expressesUncertainty,
  }) {
    var score = 0.0;

    if (hasDate) score += 0.35;
    if (hasTime) score += 0.30;
    if (hasDuration) score += 0.25;

    if (expressesUncertainty) score += 0.10;

    if (normalizedText.trim().isEmpty) return 0.0;

    if (score <= 0.0) return 0.0;
    if (score > 1.0) return 1.0;

    return double.parse(score.toStringAsFixed(2));
  }

  static bool _containsAny(String text, List<String> values) {
    return values.any(text.contains);
  }

  static String _normalize(String text) {
    return const NaturalLanguageNormalizer().normalize(text).normalizedText;
  }
}
