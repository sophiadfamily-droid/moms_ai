import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../models/life_context/life_context_projection.dart';
import '../../models/priority/priority_models.dart';
import '../../models/priority/priority_suggestion_models.dart';
import '../../models/priority/proactive_priority_models.dart';

final class ProactiveSuggestionPolicy {
  static const currentSchemaVersion = 1;
  static const maximumVisibleSuggestions = 1;

  const ProactiveSuggestionPolicy();

  ProactiveSuggestionDecision evaluate({
    required PrioritySuggestionResult suggestions,
    required PriorityRanking ranking,
    required LifeContextProjection projection,
    required List<String> presentationMessages,
    required List<ProactiveSuggestionReceipt> history,
    required DateTime localNow,
    required bool dashboardReady,
    required bool interactionActive,
    required bool onboardingActive,
    required bool alreadyPresentedThisSession,
    bool presentationReserved = false,
    bool historyPersistenceBlocked = false,
  }) {
    final inputSuggestionCount = suggestions.suggestions.length;
    if (interactionActive) {
      return ProactiveSuggestionDecision.noSuggestion(
        'active_continuation',
        inputSuggestionCount: inputSuggestionCount,
      );
    }
    if (!dashboardReady) {
      return ProactiveSuggestionDecision.noSuggestion(
        'dashboard_not_ready',
        inputSuggestionCount: inputSuggestionCount,
      );
    }
    if (onboardingActive) {
      return ProactiveSuggestionDecision.noSuggestion(
        'onboarding_active',
        inputSuggestionCount: inputSuggestionCount,
      );
    }
    if (projection.state != LifeContextProjectionState.complete) {
      return ProactiveSuggestionDecision.noSuggestion(
        'context_blocked',
        inputSuggestionCount: inputSuggestionCount,
      );
    }
    if (historyPersistenceBlocked) {
      return ProactiveSuggestionDecision.noSuggestion(
        'history_persistence_blocked',
        inputSuggestionCount: inputSuggestionCount,
      );
    }
    if (alreadyPresentedThisSession) {
      return ProactiveSuggestionDecision.noSuggestion(
        'session_quota_consumed',
        inputSuggestionCount: inputSuggestionCount,
      );
    }
    if (presentationReserved) {
      return ProactiveSuggestionDecision.noSuggestion(
        'presentation_reserved',
        inputSuggestionCount: inputSuggestionCount,
      );
    }
    if (suggestions.warnings
            .contains(PrioritySuggestionWarning.invalidEvidence) ||
        suggestions.warnings
            .contains(PrioritySuggestionWarning.incoherentRanking)) {
      return ProactiveSuggestionDecision.noSuggestion(
        'evidence_blocked',
        inputSuggestionCount: inputSuggestionCount,
      );
    }
    var evaluatedCandidateCount = 0;
    var skippedShownCount = 0;
    var skippedDismissedCount = 0;
    var skippedCompletedCount = 0;
    var skippedIneligibleCount = 0;
    for (var rank = 0; rank < suggestions.suggestions.length; rank++) {
      evaluatedCandidateCount++;
      final source = suggestions.suggestions[rank];
      if (rank >= presentationMessages.length ||
          source.expiresAt.toLocal().isBefore(localNow) ||
          source.confidenceLevel == PrioritySuggestionConfidence.limited ||
          source.proposedNextStep == PrioritySuggestionNextStep.none) {
        skippedIneligibleCount++;
        continue;
      }
      final ranked = ranking.items
          .where((item) => item.candidate.id == source.primaryCandidateId)
          .firstOrNull;
      if (ranked == null ||
          ranked.candidate.status != PriorityCandidateStatus.active ||
          ranked.candidate.confirmation.name == 'rejected') {
        skippedIneligibleCount++;
        continue;
      }
      final references = [
        source.primaryCandidateId,
        ...source.supportingCandidateIds,
      ]..sort();
      final canonicalKey = _hash([
        source.suggestionType.name,
        ...references,
      ].join('|'));
      final sourceRevision =
          '${ranked.candidate.sourceRevision ?? 0}:${source.calculationVersion}';
      final materialFingerprint = _hash([
        canonicalKey,
        source.suggestionId,
        source.horizon.name,
        source.severity.name,
        source.reasonCodes.map((value) => value.name).join(','),
        sourceRevision,
      ].join('|'));
      final duplicateReceipt = history
          .where(
            (receipt) =>
                receipt.materialFingerprint == materialFingerprint &&
                    _sameCivilDay(receipt.lastShownAt.toLocal(), localNow) ||
                receipt.canonicalSuggestionKey == canonicalKey &&
                    receipt.materialFingerprint == materialFingerprint &&
                    {
                      ProactiveSuggestionHistoryState.dismissed,
                      ProactiveSuggestionHistoryState.completed,
                      ProactiveSuggestionHistoryState.expired,
                    }.contains(receipt.state),
          )
          .firstOrNull;
      if (duplicateReceipt != null) {
        switch (duplicateReceipt.state) {
          case ProactiveSuggestionHistoryState.shown:
            skippedShownCount++;
          case ProactiveSuggestionHistoryState.dismissed:
            skippedDismissedCount++;
          case ProactiveSuggestionHistoryState.completed ||
                ProactiveSuggestionHistoryState.actedOn ||
                ProactiveSuggestionHistoryState.expired:
            skippedCompletedCount++;
          case ProactiveSuggestionHistoryState.eligible ||
                ProactiveSuggestionHistoryState.superseded:
            skippedShownCount++;
        }
        continue;
      }
      final cta = _callToAction(source, ranked.candidate.sourceDomain);
      if (cta == null) {
        skippedIneligibleCount++;
        continue;
      }
      return ProactiveSuggestionDecision.showSuggestion(
        ProactiveSuggestion(
          suggestionId: 'proactive-${_hash(materialFingerprint)}',
          canonicalSuggestionKey: canonicalKey,
          materialFingerprint: materialFingerprint,
          suggestionType: source.suggestionType,
          message: presentationMessages[rank],
          reasonCodes: source.reasonCodes,
          sourceEntityReferences: references,
          generatedAt: localNow,
          expiresAt: source.expiresAt.toLocal(),
          validityState: ProactiveSuggestionValidityState.valid,
          callToAction: cta,
          requiresConfirmation: source.confirmationRequired,
          priorityRank: rank,
          sourceRevision: sourceRevision,
        ),
        inputSuggestionCount: inputSuggestionCount,
        evaluatedCandidateCount: evaluatedCandidateCount,
        skippedShownCount: skippedShownCount,
        skippedDismissedCount: skippedDismissedCount,
        skippedCompletedCount: skippedCompletedCount,
        skippedIneligibleCount: skippedIneligibleCount,
        selectedCandidateRank: rank + 1,
      );
    }
    final skippedCount =
        skippedShownCount + skippedDismissedCount + skippedCompletedCount;
    final terminalCode = inputSuggestionCount == 0
        ? 'no_candidates'
        : suggestions.candidateWindowExhausted
            ? 'candidate_window_exhausted'
            : skippedCount == inputSuggestionCount
                ? 'all_candidates_deduplicated'
                : 'all_candidates_ineligible';
    return ProactiveSuggestionDecision.noSuggestion(
      terminalCode,
      inputSuggestionCount: inputSuggestionCount,
      evaluatedCandidateCount: evaluatedCandidateCount,
      skippedShownCount: skippedShownCount,
      skippedDismissedCount: skippedDismissedCount,
      skippedCompletedCount: skippedCompletedCount,
      skippedIneligibleCount: skippedIneligibleCount,
    );
  }

  ProactiveSuggestionCallToActionType? _callToAction(
    PrioritySuggestion suggestion,
    PrioritySourceDomain domain,
  ) =>
      switch (suggestion.proposedNextStep) {
        PrioritySuggestionNextStep.openItem
            when domain == PrioritySourceDomain.task =>
          ProactiveSuggestionCallToActionType.openTask,
        PrioritySuggestionNextStep.openItem
            when domain == PrioritySourceDomain.event =>
          ProactiveSuggestionCallToActionType.openEvent,
        PrioritySuggestionNextStep.reviewSchedule ||
        PrioritySuggestionNextStep.askZeliaForOptions =>
          ProactiveSuggestionCallToActionType.reviewSchedule,
        PrioritySuggestionNextStep.provideDuration ||
        PrioritySuggestionNextStep.provideDeadline =>
          ProactiveSuggestionCallToActionType.completeInformation,
        PrioritySuggestionNextStep.prepareForCommitment
            when domain == PrioritySourceDomain.event =>
          ProactiveSuggestionCallToActionType.openEvent,
        _ => null,
      };

  bool _sameCivilDay(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;

  String _hash(String value) =>
      sha256.convert(utf8.encode(value)).toString().substring(0, 24);
}
