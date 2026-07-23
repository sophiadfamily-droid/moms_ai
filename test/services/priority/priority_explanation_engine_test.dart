import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/life_context/life_context_graph.dart';
import 'package:moms_ai/models/priority/priority_explanation_models.dart';
import 'package:moms_ai/models/priority/priority_models.dart';
import 'package:moms_ai/models/priority/priority_propagation_models.dart';
import 'package:moms_ai/services/priority/priority_engine.dart';
import 'package:moms_ai/services/priority/priority_explanation_engine.dart';
import 'package:moms_ai/services/priority/priority_explanation_registry.dart';

void main() {
  final now = DateTime.utc(2026, 7, 23, 10);
  final scorer = PriorityEngine();
  final explainer = PriorityExplanationEngine();

  group('closed, versioned explanations', () {
    test('short and detailed outputs are bounded and deterministic', () {
      final candidate = _candidate(
        deadline: now.add(const Duration(hours: 1)),
        importance: .9,
        effortMinutes: 120,
      );
      final score = scorer.score(candidate, evaluatedAt: now);
      final short = explainer.explainDirect(
        candidate,
        score,
        detailLevel: PriorityExplanationDetailLevel.short,
        evaluatedAt: now,
      );
      final detailed = explainer.explainDirect(
        candidate,
        score,
        detailLevel: PriorityExplanationDetailLevel.detailed,
        evaluatedAt: now,
      );

      expect(short.schemaVersion, 1);
      expect(short.primaryReasons.length, lessThanOrEqualTo(3));
      expect(short.shortText, contains('Cette priorité'));
      expect(detailed.paragraphs, isNotEmpty);
      expect(
        detailed.paragraphs.fold<int>(0, (sum, item) => sum + item.length),
        lessThanOrEqualTo(PriorityExplanation.maximumDetailedLength),
      );
      expect(jsonEncode(detailed.toJson()), jsonEncode(detailed.toJson()));
      expect(detailed.toJson(), isNot(contains('candidateId')));
      expect(
        () => PriorityExplanationReason(
          schemaVersion: 2,
          code: PriorityExplanationReasonCode.overdue,
          polarity: PriorityExplanationPolarity.positive,
          shortText: 'raison',
          detailedText: 'raison détaillée',
          contribution: 1,
        ),
        throwsA(isA<PriorityException>()),
      );
    });

    test('registry covers every reason and rejects invalid text', () {
      PriorityExplanationRegistry.validate();
      expect(
        PriorityExplanationRegistry.definitions.length,
        PriorityExplanationReasonCode.values.length,
      );
      expect(
        () => PriorityExplanationReason(
          code: PriorityExplanationReasonCode.overdue,
          polarity: PriorityExplanationPolarity.positive,
          shortText: 'x' * 181,
          detailedText: 'détail',
          contribution: 1,
        ),
        throwsA(isA<PriorityException>()),
      );
    });
  });

  group('faithfulness to R.1', () {
    test('deadline buckets and explicit urgency map to registered reasons', () {
      final cases = <DateTime, PriorityExplanationReasonCode>{
        now.subtract(const Duration(minutes: 1)):
            PriorityExplanationReasonCode.overdue,
        now.add(const Duration(hours: 1)):
            PriorityExplanationReasonCode.dueVerySoon,
        DateTime.utc(2026, 7, 23, 20): PriorityExplanationReasonCode.dueToday,
        now.add(const Duration(days: 1)):
            PriorityExplanationReasonCode.dueTomorrow,
        now.add(const Duration(days: 3)): PriorityExplanationReasonCode.dueSoon,
        now.add(const Duration(days: 30)):
            PriorityExplanationReasonCode.distantDeadline,
      };
      for (final entry in cases.entries) {
        expect(
          _codes(_explain(_candidate(deadline: entry.key), now)),
          contains(entry.value),
        );
      }
      expect(
        _codes(_explain(_candidate(urgency: .9), now)),
        contains(PriorityExplanationReasonCode.explicitUrgency),
      );
      expect(
        _codes(_explain(_candidate(id: 'urgent-enfant'), now)),
        isNot(contains(PriorityExplanationReasonCode.explicitUrgency)),
      );
    });

    test('importance, effort, flexibility and impacts are never invented', () {
      expect(
        _codes(_explain(_candidate(importance: .9), now)),
        contains(PriorityExplanationReasonCode.explicitImportanceHigh),
      );
      expect(
        _codes(_explain(_candidate(importance: .1), now)),
        contains(PriorityExplanationReasonCode.explicitImportanceLow),
      );
      expect(
        _codes(_explain(_candidate(), now)),
        contains(PriorityExplanationReasonCode.importanceUnknown),
      );
      expect(
        _codes(
          _explain(
            _candidate(
              deadline: now.add(const Duration(hours: 1)),
              effortMinutes: 120,
            ),
            now,
          ),
        ),
        contains(PriorityExplanationReasonCode.insufficientTime),
      );
      expect(
        _codes(
          _explain(
            _candidate(flexibility: PriorityFlexibility.fixed),
            now,
          ),
        ),
        contains(PriorityExplanationReasonCode.fixed),
      );
      expect(
        _codes(_explain(_candidate(impacts: [_impact()]), now)),
        contains(PriorityExplanationReasonCode.directImpact),
      );
    });

    test('missing and stale information remain explicit', () {
      final explanation = _explain(
        _candidate(freshness: PriorityFreshness.stale),
        now,
      );
      expect(explanation.missingData, contains(PriorityMissingData.deadline));
      expect(
        _codes(explanation),
        containsAll([
          PriorityExplanationReasonCode.staleData,
          PriorityExplanationReasonCode.partialCalculation,
        ]),
      );
      expect(
        explanation.paragraphs.join(' '),
        contains('Informations manquantes'),
      );
    });
  });

  group('R.2 propagation and comparison', () {
    test('direct and propagated values stay distinct without technical IDs',
        () {
      final candidate = _candidate(importance: .8);
      final direct = scorer.score(candidate, evaluatedAt: now);
      final propagated = _propagated(
        candidate,
        direct,
        contribution: 10,
        influences: [_influence(candidate.id)],
        cycle: PriorityPropagationCycleState.cycleDetected,
        truncation: PriorityPropagationTruncationState.truncated,
        omitted: 2,
      );
      final explanation = explainer.explainPropagated(
        propagated,
        detailLevel: PriorityExplanationDetailLevel.detailed,
        evaluatedAt: now,
      );
      final encoded = jsonEncode(explanation.toJson());

      expect(explanation.propagationVersion, 1);
      expect(
        _codes(explanation),
        containsAll([
          PriorityExplanationReasonCode.propagatedDependency,
          PriorityExplanationReasonCode.cycleDetected,
          PriorityExplanationReasonCode.truncatedPropagation,
        ]),
      );
      expect(explanation.paragraphs.join(' '), contains('Score direct'));
      expect(encoded, isNot(contains('dependency-secret')));
      expect(encoded, isNot(contains('node-secret')));
    });

    test('zero propagation is explained and capped score is coherent', () {
      final candidate = _candidate(importance: 1, urgency: 1);
      final direct = scorer.score(candidate, evaluatedAt: now);
      final none = _propagated(candidate, direct);
      expect(
        _codes(
          explainer.explainPropagated(
            none,
            detailLevel: PriorityExplanationDetailLevel.short,
            evaluatedAt: now,
          ),
        ),
        contains(PriorityExplanationReasonCode.noPropagation),
      );

      final capped = _propagated(
        candidate,
        direct,
        contribution: 50,
        adjusted: 100,
        influences: [_influence(candidate.id)],
      );
      expect(
        () => explainer.explainPropagated(
          capped,
          detailLevel: PriorityExplanationDetailLevel.short,
          evaluatedAt: now,
        ),
        returnsNormally,
      );
    });

    test('comparison follows adjusted, direct and stable tie-breaks', () {
      final a = _candidate(id: 'a', importance: .9);
      final b = _candidate(id: 'b', importance: .1);
      final aScore = scorer.score(a, evaluatedAt: now);
      final bScore = scorer.score(b, evaluatedAt: now);
      expect(
        explainer
            .compare(
              _propagated(a, aScore),
              _propagated(b, bScore),
              evaluatedAt: now,
            )
            .basis,
        PriorityComparisonBasis.adjustedScore,
      );
      expect(
        () => explainer.compare(
          _propagated(b, bScore),
          _propagated(a, aScore),
          evaluatedAt: now,
        ),
        throwsA(
          isA<PriorityException>().having(
            (error) => error.code,
            'code',
            'priority_comparison_order_mismatch',
          ),
        ),
      );

      final sameA = _candidate(id: 'a');
      final sameB = _candidate(id: 'b');
      expect(
        explainer
            .compare(
              _propagated(sameA, scorer.score(sameA, evaluatedAt: now)),
              _propagated(sameB, scorer.score(sameB, evaluatedAt: now)),
              evaluatedAt: now,
            )
            .basis,
        PriorityComparisonBasis.stableOrder,
      );
    });

    test('ranking explanations are paginated and bounded', () {
      final candidates = List.generate(3, (index) => _candidate(id: '$index'));
      final scores = [
        for (final candidate in candidates)
          _propagated(candidate, scorer.score(candidate, evaluatedAt: now)),
      ];
      final ranking = PropagatedPriorityRanking(
        sourceSnapshotId: 'snapshot',
        evaluatedAt: now,
        propagationVersion: 1,
        items: [
          for (var index = 0; index < scores.length; index++)
            PropagatedPriorityRankedCandidate(
              rank: index + 1,
              score: scores[index],
            ),
        ],
        cycles: const [],
        omittedCount: 0,
        truncationState: PriorityPropagationTruncationState.complete,
      );
      final page = explainer.explainRanking(
        ranking,
        detailLevel: PriorityExplanationDetailLevel.short,
        offset: 0,
        limit: 2,
      );
      expect(page.explanations, hasLength(2));
      expect(page.hasMore, isTrue);
      expect(
        () => explainer.explainRanking(
          ranking,
          detailLevel: PriorityExplanationDetailLevel.short,
          offset: 0,
          limit: 11,
        ),
        throwsA(isA<PriorityException>()),
      );
    });
  });

  test('structurally identical situations have identical explanations', () {
    final baseline = _explain(_candidate(id: 'single'), now).shortText;
    for (final id in [
      'couple',
      'same-sex-couple',
      'single-parent',
      'many-children',
      'mother',
      'father',
      'blended-family',
      'work',
      'personal',
      'leisure',
    ]) {
      expect(_explain(_candidate(id: id), now).shortText, baseline, reason: id);
    }
  });
}

PriorityExplanation _explain(PriorityCandidate candidate, DateTime now) {
  final score = PriorityEngine().score(candidate, evaluatedAt: now);
  return PriorityExplanationEngine().explainDirect(
    candidate,
    score,
    detailLevel: PriorityExplanationDetailLevel.detailed,
    evaluatedAt: now,
  );
}

Set<PriorityExplanationReasonCode> _codes(PriorityExplanation explanation) => {
      ...explanation.primaryReasons.map((item) => item.code),
      ...explanation.secondaryReasons.map((item) => item.code),
      ...explanation.reducingFactors.map((item) => item.code),
      ...explanation.propagationReasons.map((item) => item.code),
      ...explanation.warnings.map((item) => item.code),
    };

PriorityCandidate _candidate({
  String id = 'candidate',
  DateTime? deadline,
  int? effortMinutes,
  PriorityFlexibility flexibility = PriorityFlexibility.unknown,
  double? importance,
  double? urgency,
  PriorityFreshness freshness = PriorityFreshness.current,
  List<PriorityDirectImpact> impacts = const [],
}) =>
    PriorityCandidate(
      id: id,
      accountScopeId: 'account',
      sourceDomain: PrioritySourceDomain.task,
      sourceId: id,
      type: PriorityCandidateType.task,
      status: PriorityCandidateStatus.active,
      deadline: deadline,
      effortMinutes: effortMinutes,
      flexibility: flexibility,
      explicitImportance: importance,
      explicitUrgency: urgency,
      directImpacts: impacts,
      confirmation: LifeContextConfirmation.confirmed,
      freshness: freshness,
      provenance: PriorityProvenance(
        sourceSnapshotId: 'snapshot',
        sourceItemId: id,
        sourceKind: 'projection',
      ),
    );

PriorityDirectImpact _impact() => const PriorityDirectImpact(
      id: 'impact',
      type: PriorityImpactType.blocks,
      depth: 1,
      confirmation: LifeContextConfirmation.confirmed,
      provenance: PriorityProvenance(
        sourceSnapshotId: 'snapshot',
        sourceItemId: 'impact',
        sourceKind: 'graph',
      ),
    );

PriorityDependencyInfluence _influence(String targetId) =>
    PriorityDependencyInfluence(
      id: 'influence',
      sourceCandidateId: 'dependent',
      targetCandidateId: targetId,
      dependencyId: 'dependency-secret',
      dependencyType: LifeContextDependencyType.requires,
      depth: 1,
      direction: PriorityPropagationDirection.dependentToPrerequisite,
      rawContribution: 10,
      depthFactor: 1,
      confirmationFactor: 1,
      freshnessFactor: 1,
      finalContribution: 10,
      provenance: const PriorityProvenance(
        sourceSnapshotId: 'snapshot',
        sourceItemId: 'dependency-secret',
        sourceKind: 'graph',
      ),
      path: PriorityPropagationPath(
        nodeIds: const ['node-secret-a', 'node-secret-b'],
        dependencyIds: const ['dependency-secret'],
        depth: 1,
        truncated: false,
      ),
      containsCycle: false,
      truncated: false,
    );

PropagatedPriorityScore _propagated(
  PriorityCandidate candidate,
  PriorityScore direct, {
  double contribution = 0,
  double? adjusted,
  List<PriorityDependencyInfluence> influences = const [],
  int omitted = 0,
  PriorityPropagationCycleState cycle = PriorityPropagationCycleState.none,
  PriorityPropagationTruncationState truncation =
      PriorityPropagationTruncationState.complete,
}) =>
    PropagatedPriorityScore(
      candidate: candidate,
      directScore: direct,
      propagatedContribution: contribution,
      adjustedScore:
          adjusted ?? (direct.finalScore + contribution).clamp(0, 100),
      confidence: direct.confidence,
      freshness: PriorityPropagationFreshness.fresh,
      missingData: direct.missingData,
      influences: influences,
      omittedInfluenceCount: omitted,
      cycleState: cycle,
      truncationState: truncation,
      formulaVersion: direct.formulaVersion,
      propagationVersion: 1,
    );
