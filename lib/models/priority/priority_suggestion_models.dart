import 'dart:collection';

import 'priority_models.dart';

enum PrioritySuggestionType {
  actSoon,
  prepare,
  clarifyMissingInformation,
  reviewConflict,
  protectFixedCommitment,
  reviewOverdueItem,
  monitorDeadline,
}

enum PrioritySuggestionHorizon {
  now,
  nextTwoHours,
  today,
  nextTwentyFourHours,
  nextThreeDays,
  later,
}

enum PrioritySuggestionSeverity { information, attention, important }

enum PrioritySuggestionNextStep {
  openItem,
  provideDuration,
  provideDeadline,
  reviewSchedule,
  prepareForCommitment,
  askZeliaForOptions,
  none,
}

enum PrioritySuggestionConfidence { certain, strong, limited }

enum PrioritySuggestionReason {
  startsSoon,
  dueToday,
  dueWithin24Hours,
  dueWithinThreeDays,
  overdue,
  fixedCommitment,
  structuredConsequence,
  missingDeadlineBlocksAssessment,
  missingDurationBlocksAssessment,
  canonicalConflict,
  structuredOutboundTravel,
}

enum PrioritySuggestionWarning {
  staleRanking,
  futureRanking,
  accountMismatch,
  incoherentRanking,
  invalidEvidence,
  noEligibleSuggestion,
}

final class PrioritySuggestion {
  static const currentSchemaVersion = 1;
  static const maximumSupportingCandidates = 3;
  static const maximumReasons = 6;

  PrioritySuggestion({
    this.schemaVersion = currentSchemaVersion,
    required this.suggestionId,
    required this.accountScopeId,
    required this.suggestionType,
    required this.primaryCandidateId,
    List<String> supportingCandidateIds = const [],
    required this.horizon,
    required this.severity,
    required List<PrioritySuggestionReason> reasonCodes,
    required List<PriorityMissingData> missingInformationCodes,
    required this.proposedNextStep,
    required this.confirmationRequired,
    required this.confidenceLevel,
    required this.calculatedAt,
    required this.expiresAt,
    required this.calculationVersion,
  })  : supportingCandidateIds = UnmodifiableListView(
          List<String>.of(supportingCandidateIds)..sort(),
        ),
        reasonCodes = UnmodifiableListView(
          List<PrioritySuggestionReason>.of(reasonCodes)
            ..sort((a, b) => a.name.compareTo(b.name)),
        ),
        missingInformationCodes = UnmodifiableListView(
          List<PriorityMissingData>.of(missingInformationCodes)
            ..sort((a, b) => a.name.compareTo(b.name)),
        ) {
    if (schemaVersion != currentSchemaVersion ||
        suggestionId.trim().isEmpty ||
        accountScopeId.trim().isEmpty ||
        primaryCandidateId.trim().isEmpty ||
        supportingCandidateIds.length > maximumSupportingCandidates ||
        supportingCandidateIds.contains(primaryCandidateId) ||
        supportingCandidateIds.toSet().length !=
            supportingCandidateIds.length ||
        reasonCodes.isEmpty ||
        reasonCodes.length > maximumReasons ||
        reasonCodes.toSet().length != reasonCodes.length ||
        missingInformationCodes.toSet().length !=
            missingInformationCodes.length ||
        calculationVersion < 1 ||
        !expiresAt.isAfter(calculatedAt)) {
      throw const PriorityException('invalid_priority_suggestion');
    }
  }

  final int schemaVersion;
  final String suggestionId;
  final String accountScopeId;
  final PrioritySuggestionType suggestionType;
  final String primaryCandidateId;
  final List<String> supportingCandidateIds;
  final PrioritySuggestionHorizon horizon;
  final PrioritySuggestionSeverity severity;
  final List<PrioritySuggestionReason> reasonCodes;
  final List<PriorityMissingData> missingInformationCodes;
  final PrioritySuggestionNextStep proposedNextStep;
  final bool confirmationRequired;
  final PrioritySuggestionConfidence confidenceLevel;
  final DateTime calculatedAt;
  final DateTime expiresAt;
  final int calculationVersion;

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'suggestionId': suggestionId,
        'suggestionType': suggestionType.name,
        'primaryCandidateId': primaryCandidateId,
        'supportingCandidateIds': supportingCandidateIds,
        'horizon': horizon.name,
        'severity': severity.name,
        'reasonCodes': reasonCodes.map((item) => item.name).toList(),
        'missingInformationCodes':
            missingInformationCodes.map((item) => item.name).toList(),
        'proposedNextStep': proposedNextStep.name,
        'confirmationRequired': confirmationRequired,
        'confidenceLevel': confidenceLevel.name,
        'calculatedAt': calculatedAt.toUtc().toIso8601String(),
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'calculationVersion': calculationVersion,
      };
}

abstract final class PrioritySuggestionLimits {
  static const int chatConsultation = 3;
  static const int proactiveEvaluation = 20;
  static const int maximumBoundedWindow = proactiveEvaluation;
}

final class PrioritySuggestionResult {
  static const currentSchemaVersion = 1;
  static const maximumSuggestions = PrioritySuggestionLimits.chatConsultation;

  PrioritySuggestionResult({
    this.schemaVersion = currentSchemaVersion,
    required this.accountScopeId,
    required this.calculationVersion,
    required this.referenceDate,
    required this.expiresAt,
    required List<PrioritySuggestion> suggestions,
    Set<PrioritySuggestionWarning> warnings = const {},
    this.appliedLimit = PrioritySuggestionLimits.chatConsultation,
    int? sourceCandidateCount,
  })  : suggestions = UnmodifiableListView(suggestions),
        warnings = UnmodifiableSetView(warnings),
        sourceCandidateCount = sourceCandidateCount ?? suggestions.length {
    if (schemaVersion != currentSchemaVersion ||
        accountScopeId.trim().isEmpty ||
        calculationVersion < 1 ||
        !expiresAt.isAfter(referenceDate) ||
        appliedLimit < 1 ||
        appliedLimit > PrioritySuggestionLimits.maximumBoundedWindow ||
        suggestions.length > appliedLimit ||
        this.sourceCandidateCount < suggestions.length ||
        suggestions.map((item) => item.suggestionId).toSet().length !=
            suggestions.length ||
        suggestions.any((item) => item.accountScopeId != accountScopeId)) {
      throw const PriorityException('invalid_priority_suggestion_result');
    }
  }

  final int schemaVersion;
  final String accountScopeId;
  final int calculationVersion;
  final DateTime referenceDate;
  final DateTime expiresAt;
  final List<PrioritySuggestion> suggestions;
  final Set<PrioritySuggestionWarning> warnings;
  final int appliedLimit;
  final int sourceCandidateCount;
  bool get candidateWindowExhausted =>
      suggestions.length == appliedLimit &&
      sourceCandidateCount > suggestions.length;
}
