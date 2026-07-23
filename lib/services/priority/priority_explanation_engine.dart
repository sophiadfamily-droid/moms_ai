import '../../models/life_context/life_context_graph.dart';
import '../../models/priority/priority_explanation_models.dart';
import '../../models/priority/priority_models.dart';
import '../../models/priority/priority_propagation_models.dart';
import 'priority_explanation_registry.dart';

final class PriorityExplanationEngine {
  PriorityExplanationEngine() {
    PriorityExplanationRegistry.validate();
  }

  static const int maximumPrimaryReasons = 3;
  static const int maximumSecondaryReasons = 6;
  static const int maximumRankingExplanations = 10;

  PriorityExplanation explainDirect(
    PriorityCandidate candidate,
    PriorityScore score, {
    required PriorityExplanationDetailLevel detailLevel,
    required DateTime evaluatedAt,
  }) {
    _validateDirect(candidate, score);
    return _build(
      candidate: candidate,
      directScore: score,
      propagatedScore: null,
      detailLevel: detailLevel,
      evaluatedAt: evaluatedAt,
    );
  }

  PriorityExplanation explainPropagated(
    PropagatedPriorityScore score, {
    required PriorityExplanationDetailLevel detailLevel,
    required DateTime evaluatedAt,
  }) {
    _validateDirect(score.candidate, score.directScore);
    final expectedAdjusted =
        (score.directScore.finalScore + score.propagatedContribution)
            .clamp(0, 100)
            .toDouble();
    if (score.formulaVersion != score.directScore.formulaVersion ||
        (score.adjustedScore - expectedAdjusted).abs() > .001) {
      throw const PriorityException('incoherent_propagated_priority_score');
    }
    return _build(
      candidate: score.candidate,
      directScore: score.directScore,
      propagatedScore: score,
      detailLevel: detailLevel,
      evaluatedAt: evaluatedAt,
    );
  }

  PriorityComparisonExplanation compare(
    PropagatedPriorityScore first,
    PropagatedPriorityScore second, {
    required DateTime evaluatedAt,
  }) {
    if (first.candidate.id == second.candidate.id) {
      throw const PriorityException('invalid_priority_comparison');
    }
    if (_rankingComparator(first, second) > 0) {
      throw const PriorityException('priority_comparison_order_mismatch');
    }
    final basis = _comparisonBasis(first, second);
    final code = switch (basis) {
      PriorityComparisonBasis.adjustedScore =>
        PriorityExplanationReasonCode.higherAdjustedScore,
      PriorityComparisonBasis.directScore =>
        PriorityExplanationReasonCode.higherDirectScore,
      PriorityComparisonBasis.deadline =>
        PriorityExplanationReasonCode.closerDeadline,
      PriorityComparisonBasis.rigidity =>
        PriorityExplanationReasonCode.moreRigid,
      PriorityComparisonBasis.confirmation =>
        PriorityExplanationReasonCode.strongerConfirmation,
      PriorityComparisonBasis.freshness =>
        PriorityExplanationReasonCode.fresherData,
      PriorityComparisonBasis.stableOrder =>
        PriorityExplanationReasonCode.stableTieBreak,
      PriorityComparisonBasis.equivalent =>
        PriorityExplanationReasonCode.equivalentRanking,
    };
    final reason = PriorityExplanationRegistry.create(code, contribution: 0);
    final shortText = switch (basis) {
      PriorityComparisonBasis.adjustedScore =>
        'Le premier élément est classé avant le second car son score ajusté est supérieur.',
      PriorityComparisonBasis.directScore =>
        'Le premier élément est classé avant le second car son score direct est supérieur.',
      PriorityComparisonBasis.deadline =>
        'Le premier élément est classé avant le second car son échéance est plus proche.',
      PriorityComparisonBasis.rigidity =>
        'Le premier élément est classé avant le second car sa contrainte temporelle est plus rigide.',
      PriorityComparisonBasis.confirmation =>
        'Le premier élément est classé avant le second car ses données sont mieux confirmées.',
      PriorityComparisonBasis.freshness =>
        'Le premier élément est classé avant le second car ses données sont plus fraîches.',
      PriorityComparisonBasis.stableOrder =>
        'Les critères utiles sont équivalents ; un ordre stable a été conservé.',
      PriorityComparisonBasis.equivalent =>
        'Les deux éléments ont un classement équivalent selon les données disponibles.',
    };
    return PriorityComparisonExplanation(
      firstCandidateId: first.candidate.id,
      secondCandidateId: second.candidate.id,
      basis: basis,
      shortText: shortText,
      reasons: [reason],
      evaluatedAt: evaluatedAt.toUtc(),
    );
  }

  PriorityRankingExplanation explainRanking(
    PropagatedPriorityRanking ranking, {
    required PriorityExplanationDetailLevel detailLevel,
    required int offset,
    required int limit,
  }) {
    if (offset < 0 ||
        limit < 1 ||
        limit > maximumRankingExplanations ||
        offset > ranking.items.length) {
      throw const PriorityException('invalid_ranking_explanation_limit');
    }
    final selected = ranking.items.skip(offset).take(limit).toList();
    return PriorityRankingExplanation(
      offset: offset,
      totalCount: ranking.items.length,
      explanations: selected
          .map(
            (item) => explainPropagated(
              item.score,
              detailLevel: detailLevel,
              evaluatedAt: ranking.evaluatedAt,
            ),
          )
          .toList(),
      hasMore: offset + selected.length < ranking.items.length,
    );
  }

  PriorityExplanation _build({
    required PriorityCandidate candidate,
    required PriorityScore directScore,
    required PropagatedPriorityScore? propagatedScore,
    required PriorityExplanationDetailLevel detailLevel,
    required DateTime evaluatedAt,
  }) {
    final reasons = _directReasons(candidate, directScore);
    final propagationReasons = _propagationReasons(propagatedScore);
    final warnings = _warnings(candidate, directScore, propagatedScore);
    final combined = _deduplicate([...reasons, ...propagationReasons]);
    final positives = combined
        .where(
          (reason) =>
              reason.polarity == PriorityExplanationPolarity.positive &&
              reason.contribution > 0,
        )
        .toList()
      ..sort(_reasonComparator);
    final primary = positives.take(maximumPrimaryReasons).toList();
    final primaryCodes = primary.map((reason) => reason.code).toSet();
    final secondary = combined
        .where(
          (reason) =>
              !primaryCodes.contains(reason.code) &&
              reason.polarity == PriorityExplanationPolarity.neutral,
        )
        .take(maximumSecondaryReasons)
        .toList();
    final reducing = combined
        .where(
          (reason) => reason.polarity == PriorityExplanationPolarity.reducing,
        )
        .take(maximumSecondaryReasons)
        .toList();
    final shortText = _shortText(
      primary,
      reducing,
      warnings,
      directScore,
      propagatedScore,
    );
    final paragraphs = _paragraphs(
      primary: primary,
      secondary: secondary,
      reducing: reducing,
      propagation: propagationReasons,
      warnings: warnings,
      directScore: directScore,
      propagatedScore: propagatedScore,
      missingData: directScore.missingData,
      detailLevel: detailLevel,
    );
    return PriorityExplanation(
      candidateId: candidate.id,
      formulaVersion: directScore.formulaVersion,
      propagationVersion: propagatedScore?.propagationVersion,
      detailLevel: detailLevel,
      calculationStatus: directScore.status,
      confidence: directScore.confidence,
      shortText: shortText,
      paragraphs: paragraphs,
      primaryReasons: primary,
      secondaryReasons: secondary,
      reducingFactors: reducing,
      missingData: directScore.missingData,
      propagationReasons: propagationReasons,
      cycleState:
          propagatedScore?.cycleState ?? PriorityPropagationCycleState.none,
      truncationState: propagatedScore?.truncationState ??
          PriorityPropagationTruncationState.complete,
      warnings: warnings,
      sourceSnapshotId: candidate.provenance.sourceSnapshotId,
      evaluatedAt: evaluatedAt.toUtc(),
    );
  }

  List<PriorityExplanationReason> _directReasons(
    PriorityCandidate candidate,
    PriorityScore score,
  ) {
    final result = <PriorityExplanationReason>[];
    for (final component in score.components) {
      for (final rawCode in component.reasonCodes) {
        final code = _mapReasonCode(rawCode, component);
        result.add(
          PriorityExplanationRegistry.create(
            code,
            contribution: component.contribution * 100,
            dimension: component.dimension,
          ),
        );
      }
    }
    if (candidate.freshness == PriorityFreshness.stale) {
      result.add(
        PriorityExplanationRegistry.create(
          PriorityExplanationReasonCode.staleData,
          contribution: 0,
        ),
      );
    }
    return _deduplicate(result);
  }

  List<PriorityExplanationReason> _propagationReasons(
    PropagatedPriorityScore? score,
  ) {
    if (score == null || score.propagatedContribution == 0) {
      return [
        PriorityExplanationRegistry.create(
          PriorityExplanationReasonCode.noPropagation,
          contribution: 0,
        ),
      ];
    }
    final reasons = <PriorityExplanationReason>[
      PriorityExplanationRegistry.create(
        PriorityExplanationReasonCode.propagatedDependency,
        contribution: score.propagatedContribution,
        depth: score.influences.isEmpty
            ? null
            : score.influences
                .map((influence) => influence.depth)
                .reduce((a, b) => a > b ? a : b),
      ),
    ];
    if (score.influences.any((influence) => influence.confirmationFactor < 1)) {
      reasons.add(
        PriorityExplanationRegistry.create(
          PriorityExplanationReasonCode.uncertainDependency,
          contribution: 0,
        ),
      );
    }
    return reasons;
  }

  List<PriorityExplanationReason> _warnings(
    PriorityCandidate candidate,
    PriorityScore score,
    PropagatedPriorityScore? propagated,
  ) {
    final warnings = <PriorityExplanationReason>[];
    if (score.confidence != PriorityConfidence.complete ||
        score.status == PriorityCalculationStatus.partiallyScored) {
      warnings.add(
        PriorityExplanationRegistry.create(
          PriorityExplanationReasonCode.partialCalculation,
          contribution: 0,
        ),
      );
    }
    if (candidate.freshness == PriorityFreshness.stale ||
        score.status == PriorityCalculationStatus.staleSource) {
      warnings.add(
        PriorityExplanationRegistry.create(
          PriorityExplanationReasonCode.staleData,
          contribution: 0,
        ),
      );
    }
    if (propagated?.cycleState == PriorityPropagationCycleState.cycleDetected) {
      warnings.add(
        PriorityExplanationRegistry.create(
          PriorityExplanationReasonCode.cycleDetected,
          contribution: 0,
        ),
      );
    }
    if (propagated?.truncationState ==
            PriorityPropagationTruncationState.truncated ||
        (propagated?.omittedInfluenceCount ?? 0) > 0) {
      warnings.add(
        PriorityExplanationRegistry.create(
          PriorityExplanationReasonCode.truncatedPropagation,
          contribution: 0,
        ),
      );
    }
    return _deduplicate(warnings);
  }

  PriorityExplanationReasonCode _mapReasonCode(
    String rawCode,
    PriorityScoreComponent component,
  ) {
    if (rawCode.startsWith('flexibility_')) {
      return switch (rawCode.substring('flexibility_'.length)) {
        'fixed' => PriorityExplanationReasonCode.fixed,
        'low' => PriorityExplanationReasonCode.lowFlexibility,
        'flexible' => PriorityExplanationReasonCode.flexible,
        'veryFlexible' => PriorityExplanationReasonCode.veryFlexible,
        'unknown' => PriorityExplanationReasonCode.flexibilityUnknown,
        _ => throw const PriorityException(
            'unknown_priority_explanation_reason',
          ),
      };
    }
    return switch (rawCode) {
      'deadline_overdue' => PriorityExplanationReasonCode.overdue,
      'deadline_under_2h' => PriorityExplanationReasonCode.dueVerySoon,
      'deadline_today_utc' => PriorityExplanationReasonCode.dueToday,
      'deadline_tomorrow' => PriorityExplanationReasonCode.dueTomorrow,
      'deadline_under_3d' ||
      'deadline_under_7d' =>
        PriorityExplanationReasonCode.dueSoon,
      'deadline_later' => PriorityExplanationReasonCode.distantDeadline,
      'deadline_neutral_missing' ||
      'urgency_neutral_missing_deadline' =>
        PriorityExplanationReasonCode.noDeadline,
      'explicit_urgency' => PriorityExplanationReasonCode.explicitUrgency,
      'explicit_importance' => _importanceCode(component.rawValue),
      'importance_neutral_missing' =>
        PriorityExplanationReasonCode.importanceUnknown,
      'effort_exceeds_remaining_time' =>
        PriorityExplanationReasonCode.insufficientTime,
      'effort_neutral_deadline_input' ||
      'structured_effort_compared_to_deadline' =>
        PriorityExplanationReasonCode.effortKnown,
      'effort_neutral_missing' ||
      'deadline_without_effort' =>
        PriorityExplanationReasonCode.effortUnknown,
      'direct_impact_depth_1' => PriorityExplanationReasonCode.directImpact,
      'no_confirmed_direct_impact' =>
        PriorityExplanationReasonCode.noDirectImpact,
      'missing_data_penalty' => PriorityExplanationReasonCode.missingData,
      _ => throw const PriorityException(
          'unknown_priority_explanation_reason',
        ),
    };
  }

  PriorityExplanationReasonCode _importanceCode(double value) {
    if (value >= .67) {
      return PriorityExplanationReasonCode.explicitImportanceHigh;
    }
    if (value <= .33) {
      return PriorityExplanationReasonCode.explicitImportanceLow;
    }
    return PriorityExplanationReasonCode.explicitImportanceModerate;
  }

  String _shortText(
    List<PriorityExplanationReason> primary,
    List<PriorityExplanationReason> reducing,
    List<PriorityExplanationReason> warnings,
    PriorityScore directScore,
    PropagatedPriorityScore? propagated,
  ) {
    final selected = primary.take(2).map((reason) => reason.shortText).toList();
    if (selected.isNotEmpty) {
      final factors = selected.length == 1
          ? selected.single
          : '${selected.first} et ${selected.last}';
      return 'Cette priorité s’explique surtout parce que $factors.';
    }
    if (directScore.status == PriorityCalculationStatus.notScorable) {
      return 'Les données disponibles ne permettent pas de calculer cette priorité.';
    }
    if (reducing.isNotEmpty) {
      return 'Cette priorité reste limitée parce que ${reducing.first.shortText}.';
    }
    if (warnings.isNotEmpty) {
      return 'Cette priorité a été calculée avec une réserve : ${warnings.first.shortText}.';
    }
    if ((propagated?.propagatedContribution ?? 0) == 0) {
      return 'Cette priorité repose sur les seules données structurées du score direct.';
    }
    return 'Cette priorité repose sur les données structurées disponibles.';
  }

  List<String> _paragraphs({
    required List<PriorityExplanationReason> primary,
    required List<PriorityExplanationReason> secondary,
    required List<PriorityExplanationReason> reducing,
    required List<PriorityExplanationReason> propagation,
    required List<PriorityExplanationReason> warnings,
    required PriorityScore directScore,
    required PropagatedPriorityScore? propagatedScore,
    required List<PriorityMissingData> missingData,
    required PriorityExplanationDetailLevel detailLevel,
  }) {
    if (detailLevel == PriorityExplanationDetailLevel.short) {
      return [
        _shortText(primary, reducing, warnings, directScore, propagatedScore),
      ];
    }
    final paragraphs = <String>[
      propagatedScore == null
          ? 'Score direct : ${_number(directScore.finalScore)} sur 100.'
          : 'Score direct : ${_number(directScore.finalScore)} sur 100. '
              'Influence des dépendances : ${_number(propagatedScore.propagatedContribution)} point(s). '
              'Score ajusté : ${_number(propagatedScore.adjustedScore)} sur 100.',
    ];
    if (primary.isNotEmpty) {
      paragraphs.add(
        _boundedParagraph(
          'Ce qui augmente la priorité : ',
          primary.map((reason) => reason.detailedText),
        ),
      );
    }
    final neutralAndReducing = [...reducing, ...secondary];
    if (neutralAndReducing.isNotEmpty) {
      paragraphs.add(
        _boundedParagraph(
          'Ce qui la réduit ou reste neutre : ',
          neutralAndReducing.map((reason) => reason.detailedText),
        ),
      );
    }
    if (missingData.isNotEmpty) {
      paragraphs.add(
        _boundedParagraph(
          'Informations manquantes : ',
          missingData.map(_missingText),
        ),
      );
    }
    paragraphs.add(
      _boundedParagraph(
        'Dépendances prises en compte : ',
        propagation.map((reason) => reason.detailedText),
      ),
    );
    if (warnings.isNotEmpty) {
      paragraphs.add(
        _boundedParagraph(
          'Limites du calcul : ',
          warnings.map((reason) => reason.detailedText),
        ),
      );
    }
    return paragraphs;
  }

  String _missingText(PriorityMissingData value) => switch (value) {
        PriorityMissingData.deadline => 'Aucune échéance n’est renseignée.',
        PriorityMissingData.effort => 'La durée estimée n’est pas connue.',
        PriorityMissingData.importance => 'L’importance n’a pas été indiquée.',
        PriorityMissingData.flexibility => 'La flexibilité n’est pas précisée.',
        PriorityMissingData.directImpact =>
          'Aucun impact direct structuré n’est disponible.',
        PriorityMissingData.freshness =>
          'La fraîcheur de la source n’est pas connue.',
      };

  List<PriorityExplanationReason> _deduplicate(
    List<PriorityExplanationReason> source,
  ) {
    final byCode = <PriorityExplanationReasonCode, PriorityExplanationReason>{};
    for (final reason in source) {
      final existing = byCode[reason.code];
      if (existing == null ||
          reason.contribution.abs() > existing.contribution.abs()) {
        byCode[reason.code] = reason;
      }
    }
    return byCode.values.toList()..sort(_reasonComparator);
  }

  int _reasonComparator(
    PriorityExplanationReason left,
    PriorityExplanationReason right,
  ) {
    final contribution =
        right.contribution.abs().compareTo(left.contribution.abs());
    return contribution != 0
        ? contribution
        : left.code.index.compareTo(right.code.index);
  }

  PriorityComparisonBasis _comparisonBasis(
    PropagatedPriorityScore first,
    PropagatedPriorityScore second,
  ) {
    if (first.adjustedScore != second.adjustedScore) {
      return PriorityComparisonBasis.adjustedScore;
    }
    if (first.directScore.finalScore != second.directScore.finalScore) {
      return PriorityComparisonBasis.directScore;
    }
    final deadline = _compareNullableDate(
      first.candidate.deadline,
      second.candidate.deadline,
    );
    if (deadline != 0) return PriorityComparisonBasis.deadline;
    if (_rigidity(first.candidate.flexibility) !=
        _rigidity(second.candidate.flexibility)) {
      return PriorityComparisonBasis.rigidity;
    }
    if (_confirmation(first.candidate.confirmation) !=
        _confirmation(second.candidate.confirmation)) {
      return PriorityComparisonBasis.confirmation;
    }
    if (_freshness(first.candidate.freshness) !=
        _freshness(second.candidate.freshness)) {
      return PriorityComparisonBasis.freshness;
    }
    if (first.candidate.id != second.candidate.id) {
      return PriorityComparisonBasis.stableOrder;
    }
    return PriorityComparisonBasis.equivalent;
  }

  int _rankingComparator(
    PropagatedPriorityScore first,
    PropagatedPriorityScore second,
  ) {
    var comparison = second.adjustedScore.compareTo(first.adjustedScore);
    if (comparison != 0) return comparison;
    comparison =
        second.directScore.finalScore.compareTo(first.directScore.finalScore);
    if (comparison != 0) return comparison;
    comparison = _compareNullableDate(
      first.candidate.deadline,
      second.candidate.deadline,
    );
    if (comparison != 0) return comparison;
    comparison = _rigidity(second.candidate.flexibility)
        .compareTo(_rigidity(first.candidate.flexibility));
    if (comparison != 0) return comparison;
    comparison = _confirmation(second.candidate.confirmation)
        .compareTo(_confirmation(first.candidate.confirmation));
    if (comparison != 0) return comparison;
    comparison = _freshness(second.candidate.freshness)
        .compareTo(_freshness(first.candidate.freshness));
    if (comparison != 0) return comparison;
    return first.candidate.id.compareTo(second.candidate.id);
  }

  void _validateDirect(PriorityCandidate candidate, PriorityScore score) {
    candidate.validate();
    if (candidate.id != score.candidateId ||
        score.components.isEmpty ||
        score.components.any(
          (component) =>
              component.reasonCodes.isEmpty || !component.contribution.isFinite,
        )) {
      throw const PriorityException('incoherent_priority_explanation_input');
    }
  }

  int _compareNullableDate(DateTime? first, DateTime? second) {
    if (first == null && second == null) return 0;
    if (first == null) return 1;
    if (second == null) return -1;
    return first.toUtc().compareTo(second.toUtc());
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

  String _number(double value) {
    final fixed = value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2);
    return fixed.replaceAll('.', ',');
  }

  String _boundedParagraph(String prefix, Iterable<String> sentences) {
    final buffer = StringBuffer(prefix);
    for (final sentence in sentences) {
      final separator = buffer.length == prefix.length ? '' : ' ';
      if (buffer.length + separator.length + sentence.length >
          PriorityExplanation.maximumParagraphLength) {
        break;
      }
      buffer
        ..write(separator)
        ..write(sentence);
    }
    return buffer.toString();
  }
}
