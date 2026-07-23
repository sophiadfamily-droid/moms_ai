import '../../models/life_context/life_context_graph.dart';
import '../../models/priority/priority_models.dart';
import 'priority_formula.dart';

final class PriorityEngine {
  PriorityEngine() {
    PriorityFormula.validate();
  }

  PriorityScore score(
    PriorityCandidate candidate, {
    required DateTime evaluatedAt,
    String? expectedAccountScopeId,
  }) {
    candidate.validate();
    if (expectedAccountScopeId != null &&
        candidate.accountScopeId != expectedAccountScopeId) {
      throw const PriorityException('priority_account_mismatch');
    }
    final now = evaluatedAt.toUtc();
    final missing = <PriorityMissingData>{};
    final components = <PriorityScoreComponent>[
      _urgency(candidate, now, missing),
      _importance(candidate, missing),
      _deadline(candidate, now, missing),
      _effort(candidate, missing),
      _flexibility(candidate, missing),
      _directImpact(candidate, missing),
    ];
    final confidence = _confidence(candidate, missing);
    components.add(_dataQuality(candidate, missing, confidence));

    final positive = components
        .where(
            (component) => component.dimension != PriorityDimension.dataQuality)
        .fold<double>(0, (sum, component) => sum + component.contribution);
    final penalty = components
        .firstWhere(
            (component) => component.dimension == PriorityDimension.dataQuality)
        .contribution;
    final finalScore =
        _round((positive + penalty).clamp(0, 1).toDouble() * 100);
    final status = switch (candidate.status) {
      PriorityCandidateStatus.completed ||
      PriorityCandidateStatus.historical =>
        PriorityCalculationStatus.notScorable,
      _ when candidate.freshness == PriorityFreshness.stale =>
        PriorityCalculationStatus.staleSource,
      _ when confidence == PriorityConfidence.complete =>
        PriorityCalculationStatus.scored,
      _ => PriorityCalculationStatus.partiallyScored,
    };
    return PriorityScore(
      candidateId: candidate.id,
      formulaVersion: PriorityFormula.version,
      finalScore: finalScore,
      status: status,
      confidence: confidence,
      components: components,
      missingData: missing.toList(),
    );
  }

  List<PriorityScore> scoreAll(
    Iterable<PriorityCandidate> candidates, {
    required DateTime evaluatedAt,
    required String expectedAccountScopeId,
  }) =>
      candidates
          .map(
            (candidate) => score(
              candidate,
              evaluatedAt: evaluatedAt,
              expectedAccountScopeId: expectedAccountScopeId,
            ),
          )
          .toList(growable: false);

  PriorityRanking rank(
    Iterable<PriorityCandidate> candidates, {
    required DateTime evaluatedAt,
    required String expectedAccountScopeId,
    int limit = 50,
    bool includeNotScorable = false,
  }) {
    if (limit < 1 || limit > PriorityFormula.maximumRankingSize) {
      throw const PriorityException('invalid_priority_ranking_limit');
    }
    final scored = candidates
        .map(
          (candidate) => (
            candidate: candidate,
            score: score(
              candidate,
              evaluatedAt: evaluatedAt,
              expectedAccountScopeId: expectedAccountScopeId,
            ),
          ),
        )
        .where(
          (entry) =>
              includeNotScorable ||
              entry.score.status != PriorityCalculationStatus.notScorable,
        )
        .toList()
      ..sort(_compare);
    final retained = scored.take(limit).toList(growable: false);
    return PriorityRanking(
      formulaVersion: PriorityFormula.version,
      evaluatedAt: evaluatedAt.toUtc(),
      items: [
        for (var index = 0; index < retained.length; index++)
          PriorityRankedCandidate(
            rank: index + 1,
            candidate: retained[index].candidate,
            score: retained[index].score,
          ),
      ],
      omittedCount: scored.length - retained.length,
    );
  }

  int _compare(
    ({PriorityCandidate candidate, PriorityScore score}) left,
    ({PriorityCandidate candidate, PriorityScore score}) right,
  ) {
    var result = right.score.finalScore.compareTo(left.score.finalScore);
    if (result != 0) return result;
    result =
        _compareNullableDate(left.candidate.deadline, right.candidate.deadline);
    if (result != 0) return result;
    result = _rigidity(right.candidate.flexibility)
        .compareTo(_rigidity(left.candidate.flexibility));
    if (result != 0) return result;
    result = _confirmation(right.candidate.confirmation)
        .compareTo(_confirmation(left.candidate.confirmation));
    if (result != 0) return result;
    result = _freshness(right.candidate.freshness)
        .compareTo(_freshness(left.candidate.freshness));
    if (result != 0) return result;
    return left.candidate.id.compareTo(right.candidate.id);
  }

  PriorityScoreComponent _urgency(
    PriorityCandidate candidate,
    DateTime now,
    Set<PriorityMissingData> missing,
  ) {
    if (candidate.explicitUrgency case final explicit?) {
      return _component(
        candidate,
        PriorityDimension.urgency,
        explicit,
        explicit,
        const ['explicit_urgency'],
      );
    }
    if (candidate.deadline case final deadline?) {
      final normalized = _temporalPressure(deadline.toUtc(), now);
      return _component(
        candidate,
        PriorityDimension.urgency,
        deadline.toUtc().difference(now).inMinutes.toDouble(),
        normalized,
        [_deadlineReason(deadline.toUtc(), now)],
      );
    }
    missing.add(PriorityMissingData.deadline);
    return _component(
      candidate,
      PriorityDimension.urgency,
      .5,
      .5,
      const ['urgency_neutral_missing_deadline'],
      missingData: const [PriorityMissingData.deadline],
    );
  }

  PriorityScoreComponent _importance(
    PriorityCandidate candidate,
    Set<PriorityMissingData> missing,
  ) {
    final value = candidate.explicitImportance;
    if (value != null) {
      return _component(
        candidate,
        PriorityDimension.importance,
        value,
        value,
        const ['explicit_importance'],
      );
    }
    missing.add(PriorityMissingData.importance);
    return _component(
      candidate,
      PriorityDimension.importance,
      .5,
      .5,
      const ['importance_neutral_missing'],
      missingData: const [PriorityMissingData.importance],
    );
  }

  PriorityScoreComponent _deadline(
    PriorityCandidate candidate,
    DateTime now,
    Set<PriorityMissingData> missing,
  ) {
    final deadline = candidate.deadline?.toUtc();
    if (deadline == null) {
      missing.add(PriorityMissingData.deadline);
      return _component(
        candidate,
        PriorityDimension.deadlinePressure,
        .5,
        .5,
        const ['deadline_neutral_missing'],
        missingData: const [PriorityMissingData.deadline],
      );
    }
    final remainingMinutes = deadline.difference(now).inMinutes;
    var normalized = _temporalPressure(deadline, now);
    final reasons = <String>[_deadlineReason(deadline, now)];
    if (candidate.effortMinutes case final effort?) {
      if (remainingMinutes <= 0 || effort >= remainingMinutes) {
        normalized = 1;
        reasons.add('effort_exceeds_remaining_time');
      } else {
        final ratio = effort / remainingMinutes;
        if (ratio >= .5) {
          normalized = normalized < .8 ? .8 : normalized;
        } else if (ratio >= .25) {
          normalized = normalized < .6 ? .6 : normalized;
        }
        reasons.add('structured_effort_compared_to_deadline');
      }
    } else {
      missing.add(PriorityMissingData.effort);
      reasons.add('deadline_without_effort');
    }
    return _component(
      candidate,
      PriorityDimension.deadlinePressure,
      remainingMinutes.toDouble(),
      normalized,
      reasons,
      missingData: candidate.effortMinutes == null
          ? const [PriorityMissingData.effort]
          : const [],
    );
  }

  PriorityScoreComponent _effort(
    PriorityCandidate candidate,
    Set<PriorityMissingData> missing,
  ) {
    if (candidate.effortMinutes == null) {
      missing.add(PriorityMissingData.effort);
    }
    return _component(
      candidate,
      PriorityDimension.effort,
      candidate.effortMinutes?.toDouble() ?? .5,
      .5,
      [
        candidate.effortMinutes == null
            ? 'effort_neutral_missing'
            : 'effort_neutral_deadline_input',
      ],
      missingData: candidate.effortMinutes == null
          ? const [PriorityMissingData.effort]
          : const [],
    );
  }

  PriorityScoreComponent _flexibility(
    PriorityCandidate candidate,
    Set<PriorityMissingData> missing,
  ) {
    final normalized = switch (candidate.flexibility) {
      PriorityFlexibility.fixed => 1.0,
      PriorityFlexibility.low => .75,
      PriorityFlexibility.flexible => .4,
      PriorityFlexibility.veryFlexible => .2,
      PriorityFlexibility.unknown => .5,
    };
    if (candidate.flexibility == PriorityFlexibility.unknown) {
      missing.add(PriorityMissingData.flexibility);
    }
    return _component(
      candidate,
      PriorityDimension.flexibility,
      candidate.flexibility.index.toDouble(),
      normalized,
      ['flexibility_${candidate.flexibility.name}'],
      missingData: candidate.flexibility == PriorityFlexibility.unknown
          ? const [PriorityMissingData.flexibility]
          : const [],
    );
  }

  PriorityScoreComponent _directImpact(
    PriorityCandidate candidate,
    Set<PriorityMissingData> missing,
  ) {
    final direct = <String, PriorityDirectImpact>{};
    for (final impact in candidate.directImpacts) {
      if (impact.depth != 1 ||
          impact.confirmation != LifeContextConfirmation.confirmed) {
        continue;
      }
      direct.putIfAbsent(impact.id, () => impact);
    }
    final retained =
        direct.values.take(PriorityFormula.maximumDirectImpacts).toList();
    final strongest = retained.fold<double>(0, (value, impact) {
      final weight = switch (impact.type) {
        PriorityImpactType.blocks => 1.0,
        PriorityImpactType.directDependent => .75,
        PriorityImpactType.responsibility => .6,
        PriorityImpactType.technicalConsequence => .5,
      };
      return weight > value ? weight : value;
    });
    if (candidate.directImpacts.isEmpty) {
      missing.add(PriorityMissingData.directImpact);
    }
    return _component(
      candidate,
      PriorityDimension.directImpact,
      retained.length.toDouble(),
      strongest,
      [
        retained.isEmpty
            ? 'no_confirmed_direct_impact'
            : 'direct_impact_depth_1',
      ],
      missingData: candidate.directImpacts.isEmpty
          ? const [PriorityMissingData.directImpact]
          : const [],
    );
  }

  PriorityScoreComponent _dataQuality(
    PriorityCandidate candidate,
    Set<PriorityMissingData> missing,
    PriorityConfidence confidence,
  ) {
    if (candidate.freshness == PriorityFreshness.unknown) {
      missing.add(PriorityMissingData.freshness);
    }
    final normalized = (1 - missing.length / PriorityMissingData.values.length)
        .clamp(0, 1)
        .toDouble();
    final penalty = -(1 - normalized) *
        PriorityFormula.weights[PriorityDimension.dataQuality]!;
    return PriorityScoreComponent(
      dimension: PriorityDimension.dataQuality,
      rawValue: missing.length.toDouble(),
      normalizedValue: normalized,
      weight: PriorityFormula.weights[PriorityDimension.dataQuality]!,
      contribution: penalty,
      provenance: candidate.provenance,
      confidence: confidence,
      missingData: missing.toList(),
      reasonCodes: const ['missing_data_penalty'],
    );
  }

  PriorityScoreComponent _component(
    PriorityCandidate candidate,
    PriorityDimension dimension,
    double raw,
    double normalized,
    List<String> reasons, {
    List<PriorityMissingData> missingData = const [],
  }) {
    final weight = PriorityFormula.weights[dimension]!;
    return PriorityScoreComponent(
      dimension: dimension,
      rawValue: raw,
      normalizedValue: normalized,
      weight: weight,
      contribution: normalized * weight,
      provenance: candidate.provenance,
      confidence: missingData.isEmpty
          ? PriorityConfidence.complete
          : PriorityConfidence.partial,
      missingData: missingData,
      reasonCodes: reasons,
    );
  }

  PriorityConfidence _confidence(
    PriorityCandidate candidate,
    Set<PriorityMissingData> missing,
  ) {
    if (candidate.status == PriorityCandidateStatus.completed ||
        candidate.status == PriorityCandidateStatus.historical) {
      return PriorityConfidence.notCalculable;
    }
    if (missing.length >= 5) return PriorityConfidence.stronglyUncertain;
    if (missing.isNotEmpty ||
        candidate.freshness != PriorityFreshness.current) {
      return PriorityConfidence.partial;
    }
    return PriorityConfidence.complete;
  }

  double _temporalPressure(DateTime deadline, DateTime now) {
    final remaining = deadline.difference(now);
    if (!deadline.isAfter(now)) return 1;
    if (remaining <= PriorityFormula.immediateWindow) return .95;
    if (_sameUtcDay(deadline, now)) return .8;
    if (remaining <= PriorityFormula.tomorrowWindow) return .7;
    if (remaining <= PriorityFormula.threeDayWindow) return .55;
    if (remaining <= PriorityFormula.sevenDayWindow) return .35;
    return .15;
  }

  String _deadlineReason(DateTime deadline, DateTime now) {
    final remaining = deadline.difference(now);
    if (!deadline.isAfter(now)) return 'deadline_overdue';
    if (remaining <= PriorityFormula.immediateWindow) {
      return 'deadline_under_2h';
    }
    if (_sameUtcDay(deadline, now)) return 'deadline_today_utc';
    if (remaining <= PriorityFormula.tomorrowWindow) return 'deadline_tomorrow';
    if (remaining <= PriorityFormula.threeDayWindow) return 'deadline_under_3d';
    if (remaining <= PriorityFormula.sevenDayWindow) return 'deadline_under_7d';
    return 'deadline_later';
  }

  bool _sameUtcDay(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;

  int _compareNullableDate(DateTime? left, DateTime? right) {
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    return left.toUtc().compareTo(right.toUtc());
  }

  int _rigidity(PriorityFlexibility value) => switch (value) {
        PriorityFlexibility.fixed => 4,
        PriorityFlexibility.low => 3,
        PriorityFlexibility.flexible => 2,
        PriorityFlexibility.veryFlexible => 1,
        PriorityFlexibility.unknown => 0,
      };

  int _confirmation(LifeContextConfirmation value) => switch (value) {
        LifeContextConfirmation.confirmed => 5,
        LifeContextConfirmation.inferred => 4,
        LifeContextConfirmation.proposed => 3,
        LifeContextConfirmation.needsConfirmation => 2,
        LifeContextConfirmation.historical => 1,
        LifeContextConfirmation.rejected => 0,
      };

  int _freshness(PriorityFreshness value) => switch (value) {
        PriorityFreshness.current => 2,
        PriorityFreshness.stale => 1,
        PriorityFreshness.unknown => 0,
      };

  double _round(double value) => (value * 100).roundToDouble() / 100;
}
