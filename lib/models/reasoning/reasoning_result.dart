import 'reasoning_assessment.dart';
import 'reasoning_input.dart';
import 'reasoning_observation.dart';

final class ReasoningResultException implements Exception {
  const ReasoningResultException(this.code);

  final String code;
}

/// Coherent RE.4 bundle. It remains read-only and non-executable.
final class ReasoningResult {
  static const int currentSchemaVersion = 1;

  ReasoningResult({
    this.schemaVersion = currentSchemaVersion,
    required this.input,
    required this.observations,
    required this.assessment,
  }) {
    if (schemaVersion != currentSchemaVersion ||
        observations.inputId != input.inputId ||
        assessment.inputId != input.inputId ||
        observations.accountScopeId != input.accountScopeId ||
        assessment.accountScopeId != input.accountScopeId ||
        observations.generatedAt != input.generatedAt ||
        assessment.generatedAt != input.generatedAt ||
        assessment.purpose != input.purpose) {
      throw const ReasoningResultException('invalid_reasoning_result');
    }
  }

  final int schemaVersion;
  final ReasoningInput input;
  final ReasoningObservationSet observations;
  final ReasoningAssessment assessment;

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'input': input.toJson(),
        'observations': observations.toJson(),
        'assessment': assessment.toJson(),
      };
}
