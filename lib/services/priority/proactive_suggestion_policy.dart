import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../models/life_context/life_context_domains.dart';
import '../../models/life_context/life_context_graph.dart';
import '../../models/life_context/life_context_projection.dart';
import '../../models/priority/priority_models.dart';
import '../../models/priority/priority_suggestion_models.dart';
import '../../models/priority/proactive_priority_models.dart';
import '../../models/reasoning/reasoning_assessment.dart';
import 'proactive_reasoning_gate.dart';

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
    ReasoningAssessment? reasoningAssessment,
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
    if (projection.state != LifeContextProjectionState.complete &&
        !_hasTrustedLocalSuggestionEvidence(
          suggestions: suggestions,
          ranking: ranking,
          projection: projection,
        )) {
      return ProactiveSuggestionDecision.noSuggestion(
        'context_blocked',
        inputSuggestionCount: inputSuggestionCount,
      );
    }
    if (reasoningAssessment != null) {
      final gate = const ProactiveReasoningGate().evaluate(
        reasoningAssessment,
        requiresCrossDomainContext: false,
      );
      if (!gate.allowed) {
        return ProactiveSuggestionDecision.noSuggestion(
          gate.code,
          inputSuggestionCount: inputSuggestionCount,
        );
      }
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
    final latestResolvedAt = history
        .expand<DateTime>(
          (receipt) => [
            receipt.dismissedAt,
            receipt.actedOnAt,
            receipt.completedAt,
          ].whereType<DateTime>(),
        )
        .fold<DateTime?>(
          null,
          (latest, value) =>
              latest == null || value.isAfter(latest) ? value : latest,
        );
    for (var rank = 0; rank < suggestions.suggestions.length; rank++) {
      evaluatedCandidateCount++;
      final source = suggestions.suggestions[rank];
      if (reasoningAssessment != null &&
          source.supportingCandidateIds.isNotEmpty) {
        final gate = const ProactiveReasoningGate().evaluate(
          reasoningAssessment,
          requiresCrossDomainContext: true,
        );
        if (!gate.allowed) {
          skippedIneligibleCount++;
          continue;
        }
      }
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
                receipt.state == ProactiveSuggestionHistoryState.shown &&
                    receipt.materialFingerprint == materialFingerprint &&
                    _sameCivilDay(receipt.lastShownAt.toLocal(), localNow) &&
                    (latestResolvedAt == null ||
                        !latestResolvedAt.isAfter(receipt.lastShownAt)) ||
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

  bool _hasTrustedLocalSuggestionEvidence({
    required PrioritySuggestionResult suggestions,
    required PriorityRanking ranking,
    required LifeContextProjection projection,
  }) {
    if (suggestions.suggestions.isEmpty) return false;
    for (final suggestion in suggestions.suggestions) {
      final ranked = ranking.items
          .where(
            (item) => item.candidate.id == suggestion.primaryCandidateId,
          )
          .firstOrNull;
      if (ranked == null) continue;
      final sectionType = switch (ranked.candidate.sourceDomain) {
        PrioritySourceDomain.task => LifeContextProjectionSectionType.task,
        PrioritySourceDomain.event => LifeContextProjectionSectionType.event,
        PrioritySourceDomain.routine =>
          LifeContextProjectionSectionType.routine,
        PrioritySourceDomain.constraint =>
          LifeContextProjectionSectionType.memory,
      };
      final section = projection.sections
          .where((value) => value.type == sectionType)
          .firstOrNull;
      if (section == null ||
          !section.accountScopeMatch ||
          section.freshness != LifeContextFreshness.current ||
          {
            LifeContextAvailability.unavailable,
            LifeContextAvailability.corrupted,
            LifeContextAvailability.unsupported,
            LifeContextAvailability.accountMismatch,
          }.contains(section.availability)) {
        continue;
      }
      final sourceItemId = ranked.candidate.provenance.sourceItemId;
      if (section.items.any(
        (item) =>
            item.id == sourceItemId &&
            item.confirmation == LifeContextConfirmation.confirmed &&
            item.freshness == LifeContextFreshness.current,
      )) {
        return true;
      }
    }
    return false;
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
