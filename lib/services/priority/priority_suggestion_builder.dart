import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../models/life_context/life_context_domains.dart';
import '../../models/life_context/life_context_graph.dart';
import '../../models/priority/priority_models.dart';
import '../../models/priority/priority_suggestion_models.dart';
import '../../models/proactive_detection.dart';

final class PrioritySuggestionBuilder {
  static const calculationVersion = 1;
  static const rankingValidity = Duration(minutes: 15);
  static const suggestionValidity = Duration(minutes: 15);

  const PrioritySuggestionBuilder();

  PrioritySuggestionResult build({
    required PriorityRanking ranking,
    required String accountScopeId,
    required DateTime referenceDate,
    Iterable<ProactiveDetectionSignal> detectionSignals = const [],
    int limit = PrioritySuggestionResult.maximumSuggestions,
  }) {
    if (limit < 1 || limit > PrioritySuggestionLimits.maximumBoundedWindow) {
      throw const PriorityException('invalid_priority_suggestion_limit');
    }
    final now = referenceDate.toUtc();
    final rankingExpiresAt = ranking.evaluatedAt.toUtc().add(rankingValidity);
    final ownExpiry = now.add(suggestionValidity);
    final expiresAt =
        rankingExpiresAt.isBefore(ownExpiry) ? rankingExpiresAt : ownExpiry;
    final warning = _rankingWarning(ranking, accountScopeId, now);
    if (warning != null) {
      return PrioritySuggestionResult(
        accountScopeId: accountScopeId,
        calculationVersion: calculationVersion,
        referenceDate: now,
        expiresAt: ownExpiry,
        suggestions: const [],
        warnings: {warning},
        appliedLimit: limit,
        sourceCandidateCount: ranking.items.length,
      );
    }

    final rankedBySource = <String, PriorityRankedCandidate>{
      for (final item in ranking.items) item.candidate.sourceId: item,
    };
    final conflictResolution = _conflicts(
      detectionSignals,
      accountScopeId: accountScopeId,
      now: now,
      rankedBySource: rankedBySource,
    );
    final selected = <PrioritySuggestion>[];
    final seenCandidates = <String>{};
    final seenKeys = <String>{};
    for (final ranked in ranking.items) {
      if (!_eligible(ranked, accountScopeId)) continue;
      final proposal = _proposal(
        ranked,
        now,
        conflictResolution.bySource[ranked.candidate.sourceId],
        rankedBySource,
      );
      if (proposal == null) continue;
      final candidateId = proposal.ranked.candidate.id;
      final key = proposal.deduplicationKey ??
          '${proposal.type.name}:${proposal.nextStep.name}:$candidateId';
      if (!seenCandidates.add(candidateId) || !seenKeys.add(key)) continue;
      selected.add(_materialize(
        proposal,
        accountScopeId: accountScopeId,
        now: now,
        expiresAt: expiresAt,
        formulaVersion: ranking.formulaVersion,
      ));
      if (selected.length == limit) {
        break;
      }
    }
    return PrioritySuggestionResult(
      accountScopeId: accountScopeId,
      calculationVersion: calculationVersion,
      referenceDate: now,
      expiresAt: expiresAt,
      suggestions: selected,
      warnings: {
        if (conflictResolution.invalidEvidence)
          PrioritySuggestionWarning.invalidEvidence,
        if (selected.isEmpty) PrioritySuggestionWarning.noEligibleSuggestion,
      },
      appliedLimit: limit,
      sourceCandidateCount: ranking.items.length,
    );
  }

  PrioritySuggestionWarning? _rankingWarning(
    PriorityRanking ranking,
    String scope,
    DateTime now,
  ) {
    if (scope.trim().isEmpty ||
        ranking.items.any(
          (item) =>
              item.candidate.accountScopeId != scope ||
              item.score.candidateId != item.candidate.id,
        )) {
      return PrioritySuggestionWarning.accountMismatch;
    }
    final evaluatedAt = ranking.evaluatedAt.toUtc();
    if (evaluatedAt.isAfter(now)) {
      return PrioritySuggestionWarning.futureRanking;
    }
    if (!now.isBefore(evaluatedAt.add(rankingValidity))) {
      return PrioritySuggestionWarning.staleRanking;
    }
    if (ranking.items.asMap().entries.any(
          (entry) => entry.value.rank != entry.key + 1,
        )) {
      return PrioritySuggestionWarning.incoherentRanking;
    }
    return null;
  }

  bool _eligible(PriorityRankedCandidate item, String scope) =>
      item.candidate.accountScopeId == scope &&
      item.candidate.status == PriorityCandidateStatus.active &&
      item.candidate.freshness == PriorityFreshness.current &&
      item.candidate.confirmation == LifeContextConfirmation.confirmed &&
      {
        PriorityCalculationStatus.scored,
        PriorityCalculationStatus.partiallyScored,
      }.contains(item.score.status);

  _ConflictResolution _conflicts(
    Iterable<ProactiveDetectionSignal> signals, {
    required String accountScopeId,
    required DateTime now,
    required Map<String, PriorityRankedCandidate> rankedBySource,
  }) {
    final signalsByGroup = <String, List<ProactiveDetectionSignal>>{};
    var invalidEvidence = false;
    for (final signal in signals) {
      if (signal.reasonCode != ProactiveDetectionReason.structuredConflict) {
        continue;
      }
      if (signal.accountScopeId != accountScopeId ||
          signal.state != ProactiveDetectionState.eligible ||
          signal.confidenceLevel == DetectionConfidenceLevel.insufficient ||
          signal.evidenceLevel != DetectionEvidenceLevel.confirmedStructured ||
          signal.validFrom.toUtc().isAfter(now) ||
          !signal.validUntil.toUtc().isAfter(now) ||
          signal.evidence.any(
            (evidence) =>
                !evidence.confirmed ||
                evidence.freshness != LifeContextFreshness.current ||
                evidence.availability != LifeContextAvailability.available,
          )) {
        invalidEvidence = true;
        continue;
      }
      final participants = signal.sourceRevisions.keys.toList()..sort();
      final evidenceParticipants =
          signal.evidence.map((item) => item.sourceId).toSet();
      if (participants.length < 2 ||
          participants.toSet().length != participants.length ||
          participants
              .any((sourceId) => !rankedBySource.containsKey(sourceId)) ||
          participants.any(
            (sourceId) =>
                rankedBySource[sourceId]!.candidate.accountScopeId !=
                accountScopeId,
          ) ||
          evidenceParticipants.length != participants.length ||
          !evidenceParticipants.containsAll(participants)) {
        invalidEvidence = true;
        continue;
      }
      signalsByGroup.putIfAbsent(participants.join('|'), () => []).add(signal);
    }
    final validGroups = <String, ProactiveDetectionSignal>{};
    for (final entry in signalsByGroup.entries) {
      final signatures = entry.value.map(_conflictSignature).toSet();
      if (signatures.length != 1) {
        invalidEvidence = true;
        continue;
      }
      final ordered = entry.value.toList()
        ..sort((a, b) => a.detectionId.compareTo(b.detectionId));
      validGroups[entry.key] = ordered.first;
    }
    final groupsByParticipant = <String, Set<String>>{};
    for (final group in validGroups.keys) {
      for (final participant in group.split('|')) {
        groupsByParticipant.putIfAbsent(participant, () => {}).add(group);
      }
    }
    final ambiguousGroups = groupsByParticipant.values
        .where((groups) => groups.length > 1)
        .expand((groups) => groups)
        .toSet();
    if (ambiguousGroups.isNotEmpty) invalidEvidence = true;
    final result = <String, ProactiveDetectionSignal>{};
    for (final entry in validGroups.entries) {
      if (ambiguousGroups.contains(entry.key)) continue;
      for (final participant in entry.key.split('|')) {
        result[participant] = entry.value;
      }
    }
    return _ConflictResolution(
      bySource: result,
      invalidEvidence: invalidEvidence,
    );
  }

  String _conflictSignature(ProactiveDetectionSignal signal) {
    final revisions = signal.sourceRevisions.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final evidence = signal.evidence
        .map(
          (item) => [
            item.sourceId,
            item.revision,
            item.sourceType.name,
            item.intervalStart?.toUtc().toIso8601String() ?? '',
            item.intervalEnd?.toUtc().toIso8601String() ?? '',
          ].join(':'),
        )
        .toList()
      ..sort();
    return [
      signal.incidentFingerprint,
      revisions.map((item) => '${item.key}:${item.value}').join(','),
      evidence.join(','),
    ].join('|');
  }

  _SuggestionProposal? _proposal(
    PriorityRankedCandidate ranked,
    DateTime now,
    ProactiveDetectionSignal? conflict,
    Map<String, PriorityRankedCandidate> rankedBySource,
  ) {
    final candidate = ranked.candidate;
    final reasons = ranked.score.components
        .expand((component) => component.reasonCodes)
        .toSet();
    final start = candidate.temporalStart?.toUtc();
    final deadline = candidate.deadline?.toUtc();
    final isEvent = {
      PriorityCandidateType.eventCommitment,
      PriorityCandidateType.eventPreparation,
    }.contains(candidate.type);
    final futureStart = start != null && start.isAfter(now);
    final startsWithinTwoHours =
        futureStart && !start.isAfter(now.add(const Duration(hours: 2)));

    if (startsWithinTwoHours &&
        isEvent &&
        candidate.flexibility == PriorityFlexibility.fixed) {
      final hasOutboundTravel = candidate.travelGoMinutes != null;
      return _SuggestionProposal(
        ranked: ranked,
        type: hasOutboundTravel
            ? PrioritySuggestionType.prepare
            : PrioritySuggestionType.protectFixedCommitment,
        horizon: PrioritySuggestionHorizon.nextTwoHours,
        severity: PrioritySuggestionSeverity.important,
        reasons: [
          PrioritySuggestionReason.startsSoon,
          PrioritySuggestionReason.fixedCommitment,
          if (hasOutboundTravel)
            PrioritySuggestionReason.structuredOutboundTravel,
        ],
        missing: const [],
        nextStep: hasOutboundTravel
            ? PrioritySuggestionNextStep.prepareForCommitment
            : PrioritySuggestionNextStep.openItem,
        confirmationRequired: false,
        confidence: PrioritySuggestionConfidence.certain,
        supportingCandidateIds: const [],
      );
    }
    if (candidate.type == PriorityCandidateType.task &&
        reasons.contains('deadline_overdue')) {
      return _SuggestionProposal(
        ranked: ranked,
        type: PrioritySuggestionType.reviewOverdueItem,
        horizon: PrioritySuggestionHorizon.now,
        severity: PrioritySuggestionSeverity.important,
        reasons: const [
          PrioritySuggestionReason.overdue,
        ],
        missing: ranked.score.missingData,
        nextStep: PrioritySuggestionNextStep.openItem,
        confirmationRequired: false,
        confidence: PrioritySuggestionConfidence.certain,
        supportingCandidateIds: const [],
      );
    }
    if (conflict != null) {
      final supporting = conflict.sourceRevisions.keys
          .where((sourceId) => sourceId != candidate.sourceId)
          .map((sourceId) => rankedBySource[sourceId]?.candidate.id)
          .whereType<String>()
          .toSet()
          .toList()
        ..sort();
      return _SuggestionProposal(
        ranked: ranked,
        type: PrioritySuggestionType.reviewConflict,
        horizon: PrioritySuggestionHorizon.now,
        severity: PrioritySuggestionSeverity.important,
        reasons: const [PrioritySuggestionReason.canonicalConflict],
        missing: const [],
        nextStep: PrioritySuggestionNextStep.askZeliaForOptions,
        confirmationRequired: true,
        confidence: PrioritySuggestionConfidence.certain,
        supportingCandidateIds: supporting,
        deduplicationKey: 'conflict:${conflict.incidentFingerprint}',
      );
    }
    final urgent =
        candidate.explicitUrgency != null && candidate.explicitUrgency! >= .7 ||
            deadline != null &&
                !deadline.isAfter(now.add(const Duration(hours: 24)));
    if (candidate.type == PriorityCandidateType.task &&
        urgent &&
        ranked.score.missingData.contains(PriorityMissingData.deadline)) {
      return _SuggestionProposal(
        ranked: ranked,
        type: PrioritySuggestionType.clarifyMissingInformation,
        horizon: PrioritySuggestionHorizon.now,
        severity: PrioritySuggestionSeverity.attention,
        reasons: const [
          PrioritySuggestionReason.missingDeadlineBlocksAssessment,
        ],
        missing: const [PriorityMissingData.deadline],
        nextStep: PrioritySuggestionNextStep.provideDeadline,
        confirmationRequired: false,
        confidence: PrioritySuggestionConfidence.strong,
        supportingCandidateIds: const [],
      );
    }
    if (candidate.type == PriorityCandidateType.task &&
        urgent &&
        ranked.score.missingData.contains(PriorityMissingData.effort)) {
      return _SuggestionProposal(
        ranked: ranked,
        type: PrioritySuggestionType.clarifyMissingInformation,
        horizon: _horizon(deadline, now),
        severity: PrioritySuggestionSeverity.attention,
        reasons: const [
          PrioritySuggestionReason.missingDurationBlocksAssessment,
        ],
        missing: const [PriorityMissingData.effort],
        nextStep: PrioritySuggestionNextStep.provideDuration,
        confirmationRequired: false,
        confidence: PrioritySuggestionConfidence.strong,
        supportingCandidateIds: const [],
      );
    }
    if (deadline != null && deadline.isAfter(now)) {
      final difference = deadline.difference(now);
      if (difference <= const Duration(hours: 24)) {
        return _SuggestionProposal(
          ranked: ranked,
          type: PrioritySuggestionType.actSoon,
          horizon: _horizon(deadline, now),
          severity: PrioritySuggestionSeverity.attention,
          reasons: [
            _sameCivilDay(deadline, now)
                ? PrioritySuggestionReason.dueToday
                : PrioritySuggestionReason.dueWithin24Hours,
          ],
          missing: ranked.score.missingData,
          nextStep: PrioritySuggestionNextStep.openItem,
          confirmationRequired: false,
          confidence: PrioritySuggestionConfidence.strong,
          supportingCandidateIds: const [],
        );
      }
      if (difference <= const Duration(days: 3)) {
        return _SuggestionProposal(
          ranked: ranked,
          type: PrioritySuggestionType.monitorDeadline,
          horizon: PrioritySuggestionHorizon.nextThreeDays,
          severity: PrioritySuggestionSeverity.information,
          reasons: const [PrioritySuggestionReason.dueWithinThreeDays],
          missing: ranked.score.missingData,
          nextStep: PrioritySuggestionNextStep.openItem,
          confirmationRequired: false,
          confidence: PrioritySuggestionConfidence.strong,
          supportingCandidateIds: const [],
        );
      }
    }
    return null;
  }

  PrioritySuggestionHorizon _horizon(DateTime? instant, DateTime now) {
    if (instant == null || !instant.isAfter(now)) {
      return PrioritySuggestionHorizon.now;
    }
    final difference = instant.difference(now);
    if (difference <= const Duration(hours: 2)) {
      return PrioritySuggestionHorizon.nextTwoHours;
    }
    if (_sameCivilDay(instant, now)) {
      return PrioritySuggestionHorizon.today;
    }
    if (difference <= const Duration(hours: 24)) {
      return PrioritySuggestionHorizon.nextTwentyFourHours;
    }
    if (difference <= const Duration(days: 3)) {
      return PrioritySuggestionHorizon.nextThreeDays;
    }
    return PrioritySuggestionHorizon.later;
  }

  bool _sameCivilDay(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;

  PrioritySuggestion _materialize(
    _SuggestionProposal proposal, {
    required String accountScopeId,
    required DateTime now,
    required DateTime expiresAt,
    required int formulaVersion,
  }) {
    final supporting = proposal.supportingCandidateIds.toList()..sort();
    final scopeFingerprint = _fingerprint(accountScopeId);
    final identity = [
      scopeFingerprint,
      proposal.type.name,
      proposal.ranked.candidate.id,
      supporting.join(','),
      '$calculationVersion',
      '$formulaVersion',
      proposal.horizon.name,
    ].join('|');
    return PrioritySuggestion(
      suggestionId: 'priority-suggestion-${_fingerprint(identity)}',
      accountScopeId: accountScopeId,
      suggestionType: proposal.type,
      primaryCandidateId: proposal.ranked.candidate.id,
      supportingCandidateIds: supporting,
      horizon: proposal.horizon,
      severity: proposal.severity,
      reasonCodes: proposal.reasons,
      missingInformationCodes: proposal.missing,
      proposedNextStep: proposal.nextStep,
      confirmationRequired: proposal.confirmationRequired,
      confidenceLevel: proposal.confidence,
      calculatedAt: now,
      expiresAt: expiresAt,
      calculationVersion: calculationVersion,
    );
  }

  String _fingerprint(String input) =>
      sha256.convert(utf8.encode(input)).toString().substring(0, 24);
}

final class _SuggestionProposal {
  const _SuggestionProposal({
    required this.ranked,
    required this.type,
    required this.horizon,
    required this.severity,
    required this.reasons,
    required this.missing,
    required this.nextStep,
    required this.confirmationRequired,
    required this.confidence,
    required this.supportingCandidateIds,
    this.deduplicationKey,
  });

  final PriorityRankedCandidate ranked;
  final PrioritySuggestionType type;
  final PrioritySuggestionHorizon horizon;
  final PrioritySuggestionSeverity severity;
  final List<PrioritySuggestionReason> reasons;
  final List<PriorityMissingData> missing;
  final PrioritySuggestionNextStep nextStep;
  final bool confirmationRequired;
  final PrioritySuggestionConfidence confidence;
  final List<String> supportingCandidateIds;
  final String? deduplicationKey;
}

final class _ConflictResolution {
  const _ConflictResolution({
    required this.bySource,
    required this.invalidEvidence,
  });

  final Map<String, ProactiveDetectionSignal> bySource;
  final bool invalidEvidence;
}
