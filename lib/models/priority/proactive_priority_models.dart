import 'dart:collection';

import 'priority_suggestion_models.dart';
import '../task_model.dart';

enum ProactiveSuggestionDecisionType { noSuggestion, showSuggestion }

enum ProactiveSuggestionValidityState { valid, expired, superseded }

enum ProactiveSuggestionCallToActionType {
  openTask,
  openEvent,
  reviewSchedule,
  completeInformation,
}

enum ProactiveSuggestionHistoryState {
  eligible,
  shown,
  dismissed,
  actedOn,
  completed,
  expired,
  superseded,
}

final class ProactiveEvaluationSnapshot {
  const ProactiveEvaluationSnapshot({
    required this.buildMarker,
    required this.evaluatedAt,
    required this.candidateCount,
    required this.decision,
    required this.reasonCodes,
    required this.interactionActive,
    required this.tabActive,
    required this.historyState,
    required this.sessionQuotaConsumed,
    required this.sourceRevision,
    required this.evaluationGeneration,
    required this.projectionState,
    required this.relationAvailability,
    required this.presentationReserved,
    required this.presentationConfirmed,
    required this.registryInstanceIdentifier,
    required this.activeInteractionSources,
    required this.activeInteractionCount,
    required this.lastInteractionTransition,
    required this.interactionGeneration,
    required this.inputSuggestionCount,
    required this.evaluatedCandidateCount,
    required this.skippedShownCount,
    required this.skippedDismissedCount,
    required this.skippedCompletedCount,
    required this.skippedIneligibleCount,
    required this.selectedCandidateRank,
    required this.terminalReasonCode,
    required this.blockingSections,
    required this.sectionAvailabilityCodes,
    required this.projectionStateReasonCodes,
    required this.evaluationDecision,
    required this.renderedState,
    required this.visibleSuggestionPresent,
  });

  final String buildMarker;
  final DateTime evaluatedAt;
  final int candidateCount;
  final String decision;
  final List<String> reasonCodes;
  final bool interactionActive;
  final bool tabActive;
  final String historyState;
  final bool sessionQuotaConsumed;
  final String sourceRevision;
  final int evaluationGeneration;
  final String projectionState;
  final String relationAvailability;
  final bool presentationReserved;
  final bool presentationConfirmed;
  final String registryInstanceIdentifier;
  final List<String> activeInteractionSources;
  final int activeInteractionCount;
  final String lastInteractionTransition;
  final int interactionGeneration;
  final int inputSuggestionCount;
  final int evaluatedCandidateCount;
  final int skippedShownCount;
  final int skippedDismissedCount;
  final int skippedCompletedCount;
  final int skippedIneligibleCount;
  final int? selectedCandidateRank;
  final String terminalReasonCode;
  final List<String> blockingSections;
  final List<String> sectionAvailabilityCodes;
  final List<String> projectionStateReasonCodes;
  final String evaluationDecision;
  final String renderedState;
  final bool visibleSuggestionPresent;

  ProactiveEvaluationSnapshot copyWith({
    bool? presentationReserved,
    bool? presentationConfirmed,
    bool? sessionQuotaConsumed,
    String? historyState,
    String? evaluationDecision,
    String? renderedState,
    bool? visibleSuggestionPresent,
  }) =>
      ProactiveEvaluationSnapshot(
        buildMarker: buildMarker,
        evaluatedAt: evaluatedAt,
        candidateCount: candidateCount,
        decision: decision,
        reasonCodes: reasonCodes,
        interactionActive: interactionActive,
        tabActive: tabActive,
        historyState: historyState ?? this.historyState,
        sessionQuotaConsumed: sessionQuotaConsumed ?? this.sessionQuotaConsumed,
        sourceRevision: sourceRevision,
        evaluationGeneration: evaluationGeneration,
        projectionState: projectionState,
        relationAvailability: relationAvailability,
        presentationReserved: presentationReserved ?? this.presentationReserved,
        presentationConfirmed:
            presentationConfirmed ?? this.presentationConfirmed,
        registryInstanceIdentifier: registryInstanceIdentifier,
        activeInteractionSources: activeInteractionSources,
        activeInteractionCount: activeInteractionCount,
        lastInteractionTransition: lastInteractionTransition,
        interactionGeneration: interactionGeneration,
        inputSuggestionCount: inputSuggestionCount,
        evaluatedCandidateCount: evaluatedCandidateCount,
        skippedShownCount: skippedShownCount,
        skippedDismissedCount: skippedDismissedCount,
        skippedCompletedCount: skippedCompletedCount,
        skippedIneligibleCount: skippedIneligibleCount,
        selectedCandidateRank: selectedCandidateRank,
        terminalReasonCode: terminalReasonCode,
        blockingSections: blockingSections,
        sectionAvailabilityCodes: sectionAvailabilityCodes,
        projectionStateReasonCodes: projectionStateReasonCodes,
        evaluationDecision: evaluationDecision ?? this.evaluationDecision,
        renderedState: renderedState ?? this.renderedState,
        visibleSuggestionPresent:
            visibleSuggestionPresent ?? this.visibleSuggestionPresent,
      );

  String toClosedDiagnosticText() => [
        'buildMarker=$buildMarker',
        'evaluationGeneration=$evaluationGeneration',
        'evaluatedAt=${evaluatedAt.toUtc().toIso8601String()}',
        'tabActive=$tabActive',
        'interactionActive=$interactionActive',
        'projectionState=$projectionState',
        'relationAvailability=$relationAvailability',
        'candidateCount=$candidateCount',
        'decision=$decision',
        'reasonCodes=${reasonCodes.join(',')}',
        'historyState=$historyState',
        'sessionQuotaConsumed=$sessionQuotaConsumed',
        'sourceRevision=$sourceRevision',
        'presentationReserved=$presentationReserved',
        'presentationConfirmed=$presentationConfirmed',
        'registryInstanceIdentifier=$registryInstanceIdentifier',
        'activeInteractionSources=${activeInteractionSources.join(",")}',
        'activeInteractionCount=$activeInteractionCount',
        'lastInteractionTransition=$lastInteractionTransition',
        'interactionGeneration=$interactionGeneration',
        'inputSuggestionCount=$inputSuggestionCount',
        'evaluatedCandidateCount=$evaluatedCandidateCount',
        'skippedShownCount=$skippedShownCount',
        'skippedDismissedCount=$skippedDismissedCount',
        'skippedCompletedCount=$skippedCompletedCount',
        'skippedIneligibleCount=$skippedIneligibleCount',
        'selectedCandidateRank=${selectedCandidateRank ?? "none"}',
        'terminalReasonCode=$terminalReasonCode',
        'blockingSections=${blockingSections.join(',')}',
        'sectionAvailabilityCodes=${sectionAvailabilityCodes.join(',')}',
        'projectionStateReasonCodes=${projectionStateReasonCodes.join(',')}',
        'evaluationDecision=$evaluationDecision',
        'renderedState=$renderedState',
        'visibleSuggestionPresent=$visibleSuggestionPresent',
      ].join('\n');
}

final class ProactiveSuggestion {
  static const currentSchemaVersion = 1;

  ProactiveSuggestion({
    this.schemaVersion = currentSchemaVersion,
    required this.suggestionId,
    required this.canonicalSuggestionKey,
    required this.materialFingerprint,
    required this.suggestionType,
    required this.message,
    required List<PrioritySuggestionReason> reasonCodes,
    required List<String> sourceEntityReferences,
    required this.generatedAt,
    required this.expiresAt,
    required this.validityState,
    required this.callToAction,
    required this.requiresConfirmation,
    required this.priorityRank,
    required this.sourceRevision,
  })  : reasonCodes = UnmodifiableListView(reasonCodes),
        sourceEntityReferences = UnmodifiableListView(sourceEntityReferences) {
    if (schemaVersion != currentSchemaVersion ||
        suggestionId.trim().isEmpty ||
        canonicalSuggestionKey.trim().isEmpty ||
        materialFingerprint.trim().isEmpty ||
        message.trim().isEmpty ||
        reasonCodes.isEmpty ||
        sourceEntityReferences.isEmpty ||
        priorityRank < 0 ||
        !expiresAt.isAfter(generatedAt)) {
      throw const FormatException('invalid_proactive_priority_suggestion');
    }
  }

  final int schemaVersion;
  final String suggestionId;
  final String canonicalSuggestionKey;
  final String materialFingerprint;
  final PrioritySuggestionType suggestionType;
  final String message;
  final List<PrioritySuggestionReason> reasonCodes;
  final List<String> sourceEntityReferences;
  final DateTime generatedAt;
  final DateTime expiresAt;
  final ProactiveSuggestionValidityState validityState;
  final ProactiveSuggestionCallToActionType callToAction;
  final bool requiresConfirmation;
  final int priorityRank;
  final String sourceRevision;
}

final class ProactiveTaskDurationHandoff {
  ProactiveTaskDurationHandoff({
    required this.taskId,
    required this.logicalRequestId,
    required this.sourceSuggestionId,
    required this.sourceEntityReference,
    required this.taskTitle,
    required this.question,
    required this.createdAt,
    required this.task,
  }) {
    if (taskId.trim().isEmpty ||
        logicalRequestId.trim().isEmpty ||
        sourceSuggestionId.trim().isEmpty ||
        sourceEntityReference.trim().isEmpty ||
        taskTitle.trim().isEmpty ||
        question.trim().isEmpty ||
        task.id != taskId ||
        task.title != taskTitle) {
      throw const FormatException('invalid_proactive_duration_handoff');
    }
  }

  final String taskId;
  final String logicalRequestId;
  final String sourceSuggestionId;
  final String sourceEntityReference;
  final String taskTitle;
  final String question;
  final DateTime createdAt;
  final TaskModel task;
}

final class ProactiveSuggestionDecision {
  const ProactiveSuggestionDecision._(
    this.type,
    this.suggestion,
    this.code, {
    this.inputSuggestionCount = 0,
    this.evaluatedCandidateCount = 0,
    this.skippedShownCount = 0,
    this.skippedDismissedCount = 0,
    this.skippedCompletedCount = 0,
    this.skippedIneligibleCount = 0,
    this.selectedCandidateRank,
  });

  const ProactiveSuggestionDecision.noSuggestion(
    String code, {
    int inputSuggestionCount = 0,
    int evaluatedCandidateCount = 0,
    int skippedShownCount = 0,
    int skippedDismissedCount = 0,
    int skippedCompletedCount = 0,
    int skippedIneligibleCount = 0,
  }) : this._(
          ProactiveSuggestionDecisionType.noSuggestion,
          null,
          code,
          inputSuggestionCount: inputSuggestionCount,
          evaluatedCandidateCount: evaluatedCandidateCount,
          skippedShownCount: skippedShownCount,
          skippedDismissedCount: skippedDismissedCount,
          skippedCompletedCount: skippedCompletedCount,
          skippedIneligibleCount: skippedIneligibleCount,
        );

  const ProactiveSuggestionDecision.showSuggestion(
    ProactiveSuggestion suggestion, {
    int inputSuggestionCount = 0,
    int evaluatedCandidateCount = 0,
    int skippedShownCount = 0,
    int skippedDismissedCount = 0,
    int skippedCompletedCount = 0,
    int skippedIneligibleCount = 0,
    int? selectedCandidateRank,
  }) : this._(
          ProactiveSuggestionDecisionType.showSuggestion,
          suggestion,
          'suggestion_selected',
          inputSuggestionCount: inputSuggestionCount,
          evaluatedCandidateCount: evaluatedCandidateCount,
          skippedShownCount: skippedShownCount,
          skippedDismissedCount: skippedDismissedCount,
          skippedCompletedCount: skippedCompletedCount,
          skippedIneligibleCount: skippedIneligibleCount,
          selectedCandidateRank: selectedCandidateRank,
        );

  final ProactiveSuggestionDecisionType type;
  final ProactiveSuggestion? suggestion;
  final String code;
  final int inputSuggestionCount;
  final int evaluatedCandidateCount;
  final int skippedShownCount;
  final int skippedDismissedCount;
  final int skippedCompletedCount;
  final int skippedIneligibleCount;
  final int? selectedCandidateRank;
}

final class ProactiveSuggestionReceipt {
  const ProactiveSuggestionReceipt({
    required this.suggestionId,
    required this.canonicalSuggestionKey,
    required this.materialFingerprint,
    required this.firstShownAt,
    required this.lastShownAt,
    required this.state,
    required this.sourceRevision,
    this.dismissedAt,
    this.actedOnAt,
    this.completedAt,
  });

  final String suggestionId;
  final String canonicalSuggestionKey;
  final String materialFingerprint;
  final DateTime firstShownAt;
  final DateTime lastShownAt;
  final DateTime? dismissedAt;
  final DateTime? actedOnAt;
  final DateTime? completedAt;
  final ProactiveSuggestionHistoryState state;
  final String sourceRevision;

  Map<String, Object?> toJson() => {
        'suggestionId': suggestionId,
        'canonicalSuggestionKey': canonicalSuggestionKey,
        'materialFingerprint': materialFingerprint,
        'firstShownAt': firstShownAt.toUtc().toIso8601String(),
        'lastShownAt': lastShownAt.toUtc().toIso8601String(),
        if (dismissedAt != null)
          'dismissedAt': dismissedAt!.toUtc().toIso8601String(),
        if (actedOnAt != null)
          'actedOnAt': actedOnAt!.toUtc().toIso8601String(),
        if (completedAt != null)
          'completedAt': completedAt!.toUtc().toIso8601String(),
        'state': state.name,
        'sourceRevision': sourceRevision,
      };

  factory ProactiveSuggestionReceipt.fromJson(Map<String, Object?> json) =>
      ProactiveSuggestionReceipt(
        suggestionId: json['suggestionId'] as String,
        canonicalSuggestionKey: json['canonicalSuggestionKey'] as String,
        materialFingerprint: json['materialFingerprint'] as String,
        firstShownAt: DateTime.parse(json['firstShownAt'] as String).toUtc(),
        lastShownAt: DateTime.parse(json['lastShownAt'] as String).toUtc(),
        dismissedAt: json['dismissedAt'] == null
            ? null
            : DateTime.parse(json['dismissedAt'] as String).toUtc(),
        actedOnAt: json['actedOnAt'] == null
            ? null
            : DateTime.parse(json['actedOnAt'] as String).toUtc(),
        completedAt: json['completedAt'] == null
            ? null
            : DateTime.parse(json['completedAt'] as String).toUtc(),
        state: ProactiveSuggestionHistoryState.values
            .where((value) => value.name == json['state'])
            .single,
        sourceRevision: json['sourceRevision'] as String,
      );
}
