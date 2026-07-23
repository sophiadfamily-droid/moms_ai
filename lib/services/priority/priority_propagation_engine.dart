import '../../models/life_context/life_context_graph.dart';
import '../../models/priority/priority_models.dart';
import '../../models/priority/priority_propagation_models.dart';
import '../life_context/life_context_relation_engine.dart';
import 'priority_graph_candidate_adapter.dart';
import 'priority_propagation_formula.dart';

final class PriorityPropagationEngine {
  PriorityPropagationEngine({
    PriorityGraphCandidateAdapter candidateAdapter =
        const PriorityGraphCandidateAdapter(),
  }) : _candidateAdapter = candidateAdapter {
    PriorityPropagationFormula.validate();
  }

  final PriorityGraphCandidateAdapter _candidateAdapter;

  PropagatedPriorityRanking propagate(
    PriorityRanking ranking,
    LifeContextGraph graph, {
    required String expectedAccountScopeId,
    required DateTime evaluatedAt,
    int maxDepth = PriorityPropagationFormula.maximumDepth,
    int maxVisitedNodes = PriorityPropagationFormula.maximumVisitedNodes,
    int maxVisitedEdges = PriorityPropagationFormula.maximumVisitedEdges,
    int maxInfluencesPerCandidate =
        PriorityPropagationFormula.maximumInfluencesPerCandidate,
    int limit = PriorityPropagationFormula.maximumRankingSize,
  }) {
    _validateInputs(
      ranking,
      graph,
      expectedAccountScopeId: expectedAccountScopeId,
      maxDepth: maxDepth,
      maxVisitedNodes: maxVisitedNodes,
      maxVisitedEdges: maxVisitedEdges,
      maxInfluencesPerCandidate: maxInfluencesPerCandidate,
      limit: limit,
    );
    final candidatesByNode = _candidateAdapter.candidatesByNode(
      ranking,
      graph,
      expectedAccountScopeId: expectedAccountScopeId,
    );
    final nodeByCandidateId = {
      for (final entry in candidatesByNode.entries)
        entry.value.candidate.id: entry.key,
    };
    final incoming = <String, List<LifeContextDependency>>{};
    for (final dependency in graph.dependencies) {
      incoming
          .putIfAbsent(dependency.dependentNodeId, () => [])
          .add(dependency);
    }
    for (final dependencies in incoming.values) {
      dependencies.sort((a, b) => a.id.compareTo(b.id));
    }

    final influencesByTarget = <String, List<PriorityDependencyInfluence>>{};
    final influenceKeys = <String>{};
    final traversedNodes = <String>{};
    var visitedEdges = 0;
    var globallyTruncated = false;

    for (final source in ranking.items) {
      final sourceNodeId = nodeByCandidateId[source.candidate.id];
      if (sourceNodeId == null ||
          source.score.status == PriorityCalculationStatus.notScorable) {
        continue;
      }
      var frontier = <_PropagationFrontier>[
        _PropagationFrontier(
          currentNodeId: sourceNodeId,
          nodePath: [sourceNodeId],
          dependencyPath: const [],
        ),
      ];
      for (var depth = 1; depth <= maxDepth && frontier.isNotEmpty; depth++) {
        final next = <_PropagationFrontier>[];
        for (final current in frontier
          ..sort((a, b) => a.pathKey.compareTo(b.pathKey))) {
          traversedNodes.add(current.currentNodeId);
          if (traversedNodes.length > maxVisitedNodes) {
            globallyTruncated = true;
            break;
          }
          for (final dependency in incoming[current.currentNodeId] ??
              const <LifeContextDependency>[]) {
            visitedEdges++;
            if (visitedEdges > maxVisitedEdges) {
              globallyTruncated = true;
              break;
            }
            final rule = PriorityPropagationFormula.rules[dependency.type];
            if (rule == null) {
              throw const PriorityException(
                'unsupported_priority_dependency_type',
              );
            }
            if (!rule.propagates ||
                depth > rule.maximumDepth ||
                !dependency.validity.isActiveAt(evaluatedAt.toUtc())) {
              continue;
            }
            final confirmationFactor =
                _confirmationFactor(dependency.provenance);
            if (confirmationFactor == 0) continue;

            final prerequisite = dependency.prerequisiteNodeId;
            final pathNodes = <String>[...current.nodePath, prerequisite];
            final pathDependencies = <String>[
              ...current.dependencyPath,
              dependency.id,
            ];
            if (current.nodePath.contains(prerequisite)) {
              continue;
            }

            final target = candidatesByNode[prerequisite];
            if (target != null &&
                target.candidate.id != source.candidate.id &&
                target.score.status != PriorityCalculationStatus.notScorable &&
                !_countedDirectly(target.candidate, dependency)) {
              final path = PriorityPropagationPath(
                nodeIds: pathNodes,
                dependencyIds: pathDependencies,
                depth: depth,
                truncated: false,
              );
              final key = '${source.candidate.id}>${target.candidate.id}:'
                  '${pathDependencies.join(">")}';
              if (influenceKeys.add(key)) {
                final influence = _influence(
                  source: source,
                  target: target,
                  dependency: dependency,
                  path: path,
                  depth: depth,
                );
                influencesByTarget
                    .putIfAbsent(target.candidate.id, () => [])
                    .add(influence);
              }
            }
            next.add(
              _PropagationFrontier(
                currentNodeId: prerequisite,
                nodePath: pathNodes,
                dependencyPath: pathDependencies,
              ),
            );
          }
          if (globallyTruncated) break;
        }
        if (globallyTruncated) break;
        if (depth == maxDepth &&
            next.any(
              (entry) => (incoming[entry.currentNodeId] ??
                      const <LifeContextDependency>[])
                  .isNotEmpty,
            )) {
          globallyTruncated = true;
        }
        frontier = next;
      }
      if (globallyTruncated) break;
    }

    final graphCycles = _cycles(graph, maxVisitedNodes);
    final cycleNodeIds = graphCycles.expand((cycle) => cycle.nodeIds).toSet();
    final propagated = <PropagatedPriorityScore>[];
    for (final item in ranking.items) {
      final allInfluences = influencesByTarget[item.candidate.id] ?? const [];
      final sorted = List<PriorityDependencyInfluence>.of(allInfluences)
        ..sort((a, b) {
          final contribution =
              b.finalContribution.compareTo(a.finalContribution);
          return contribution != 0 ? contribution : a.id.compareTo(b.id);
        });
      final retained =
          sorted.take(maxInfluencesPerCandidate).toList(growable: false);
      final omitted = sorted.length - retained.length;
      final contribution = _round(
        retained
            .fold<double>(
              0,
              (sum, influence) => sum + influence.finalContribution,
            )
            .clamp(
              0,
              PriorityPropagationFormula.maximumContributionPerCandidate,
            )
            .toDouble(),
      );
      final isScorable =
          item.score.status != PriorityCalculationStatus.notScorable;
      final adjusted = isScorable
          ? _round((item.score.finalScore + contribution).clamp(0, 100))
          : item.score.finalScore;
      final nodeId = nodeByCandidateId[item.candidate.id];
      propagated.add(
        PropagatedPriorityScore(
          candidate: item.candidate,
          directScore: item.score,
          propagatedContribution: isScorable ? contribution : 0,
          adjustedScore: adjusted,
          confidence: item.score.confidence,
          freshness: _propagationFreshness(item.candidate.freshness),
          missingData: item.score.missingData,
          influences: isScorable ? retained : const [],
          omittedInfluenceCount: omitted,
          cycleState: nodeId != null && cycleNodeIds.contains(nodeId)
              ? PriorityPropagationCycleState.cycleDetected
              : PriorityPropagationCycleState.none,
          truncationState: globallyTruncated || omitted > 0
              ? PriorityPropagationTruncationState.truncated
              : PriorityPropagationTruncationState.complete,
          formulaVersion: item.score.formulaVersion,
          propagationVersion: PriorityPropagationFormula.version,
        ),
      );
    }
    propagated.sort(_compare);
    final retainedScores = propagated.take(limit).toList(growable: false);
    return PropagatedPriorityRanking(
      sourceSnapshotId: graph.snapshotId,
      evaluatedAt: evaluatedAt.toUtc(),
      propagationVersion: PriorityPropagationFormula.version,
      items: [
        for (var index = 0; index < retainedScores.length; index++)
          PropagatedPriorityRankedCandidate(
            rank: index + 1,
            score: retainedScores[index],
          ),
      ],
      cycles: graphCycles,
      omittedCount: propagated.length - retainedScores.length,
      truncationState:
          globallyTruncated || propagated.length > retainedScores.length
              ? PriorityPropagationTruncationState.truncated
              : PriorityPropagationTruncationState.complete,
    );
  }

  List<PriorityDependencyInfluence> influencesFor(
    String candidateId,
    PropagatedPriorityRanking ranking,
  ) {
    for (final item in ranking.items) {
      if (item.score.candidate.id == candidateId) {
        return item.score.influences;
      }
    }
    return const [];
  }

  List<PriorityPropagationPath> pathsFor(
    String candidateId,
    PropagatedPriorityRanking ranking,
  ) =>
      List.unmodifiable(
        influencesFor(candidateId, ranking)
            .map((influence) => influence.path)
            .toList(),
      );

  void _validateInputs(
    PriorityRanking ranking,
    LifeContextGraph graph, {
    required String expectedAccountScopeId,
    required int maxDepth,
    required int maxVisitedNodes,
    required int maxVisitedEdges,
    required int maxInfluencesPerCandidate,
    required int limit,
  }) {
    graph.validate();
    if (expectedAccountScopeId.trim().isEmpty ||
        graph.accountScopeId != expectedAccountScopeId) {
      throw const PriorityException('priority_graph_account_mismatch');
    }
    if (maxDepth < 1 ||
        maxDepth > PriorityPropagationFormula.maximumDepth ||
        maxVisitedNodes < 1 ||
        maxVisitedNodes > PriorityPropagationFormula.maximumVisitedNodes ||
        maxVisitedEdges < 1 ||
        maxVisitedEdges > PriorityPropagationFormula.maximumVisitedEdges ||
        maxInfluencesPerCandidate < 1 ||
        maxInfluencesPerCandidate >
            PriorityPropagationFormula.maximumInfluencesPerCandidate ||
        limit < 1 ||
        limit > PriorityPropagationFormula.maximumRankingSize) {
      throw const PriorityException('invalid_priority_propagation_limit');
    }
    for (final item in ranking.items) {
      if (item.candidate.accountScopeId != expectedAccountScopeId) {
        throw const PriorityException('priority_graph_account_mismatch');
      }
      if (item.candidate.provenance.sourceSnapshotId != graph.snapshotId) {
        throw const PriorityException('priority_graph_snapshot_mismatch');
      }
    }
  }

  PriorityDependencyInfluence _influence({
    required PriorityRankedCandidate source,
    required PriorityRankedCandidate target,
    required LifeContextDependency dependency,
    required PriorityPropagationPath path,
    required int depth,
  }) {
    final rule = PriorityPropagationFormula.rules[dependency.type]!;
    final raw = source.score.finalScore * rule.baseCoefficient;
    final depthFactor = PriorityPropagationFormula.depthFactors[depth]!;
    final confirmationFactor = _confirmationFactor(dependency.provenance);
    final freshnessFactor = _freshnessFactor(source.candidate.freshness);
    final contribution = _round(
      (raw * depthFactor * confirmationFactor * freshnessFactor)
          .clamp(
            0,
            PriorityPropagationFormula.maximumContributionPerInfluence,
          )
          .toDouble(),
    );
    return PriorityDependencyInfluence(
      id: 'propagation:${source.candidate.id}>${target.candidate.id}:'
          '${path.dependencyIds.join(">")}',
      sourceCandidateId: source.candidate.id,
      targetCandidateId: target.candidate.id,
      dependencyId: dependency.id,
      dependencyType: dependency.type,
      depth: depth,
      direction: PriorityPropagationDirection.dependentToPrerequisite,
      rawContribution: _round(raw),
      depthFactor: depthFactor,
      confirmationFactor: confirmationFactor,
      freshnessFactor: freshnessFactor,
      finalContribution: contribution,
      provenance: PriorityProvenance(
        sourceSnapshotId: dependency.provenance.snapshotId,
        sourceItemId: dependency.id,
        sourceKind: dependency.provenance.sectionSource.name,
        ruleId: dependency.provenance.ruleId,
      ),
      path: path,
      containsCycle: false,
      truncated: false,
    );
  }

  List<PriorityPropagationCycle> _cycles(
    LifeContextGraph graph,
    int maxVisitedNodes,
  ) =>
      LifeContextGraphQuery(graph)
          .dependencyCycles(maxVisitedNodes: maxVisitedNodes)
          .map(
            (cycle) => PriorityPropagationCycle(
              id: _cycleKey(cycle.nodeIds, cycle.dependencyIds),
              nodeIds: cycle.nodeIds,
              dependencyIds: cycle.dependencyIds,
            ),
          )
          .toList(growable: false);

  bool _countedDirectly(
    PriorityCandidate target,
    LifeContextDependency dependency,
  ) =>
      target.directImpacts.any(
        (impact) =>
            impact.depth == 1 &&
            impact.provenance.ruleId == dependency.provenance.ruleId &&
            impact.provenance.sourceItemId == dependency.prerequisiteNodeId,
      );

  double _confirmationFactor(LifeContextRelationProvenance provenance) {
    return switch (provenance.confirmation) {
      LifeContextConfirmation.confirmed => 1,
      LifeContextConfirmation.inferred
          when LifeContextRegisteredRuleIds.all.contains(provenance.ruleId) =>
        .5,
      LifeContextConfirmation.proposed ||
      LifeContextConfirmation.needsConfirmation ||
      LifeContextConfirmation.rejected ||
      LifeContextConfirmation.historical =>
        0,
      _ => 0,
    };
  }

  double _freshnessFactor(PriorityFreshness freshness) => switch (freshness) {
        PriorityFreshness.current => 1,
        PriorityFreshness.stale => .5,
        PriorityFreshness.unknown => .25,
      };

  PriorityPropagationFreshness _propagationFreshness(
    PriorityFreshness freshness,
  ) =>
      switch (freshness) {
        PriorityFreshness.current => PriorityPropagationFreshness.fresh,
        PriorityFreshness.stale => PriorityPropagationFreshness.stale,
        PriorityFreshness.unknown => PriorityPropagationFreshness.unavailable,
      };

  int _compare(
    PropagatedPriorityScore left,
    PropagatedPriorityScore right,
  ) {
    var result = right.adjustedScore.compareTo(left.adjustedScore);
    if (result != 0) return result;
    result =
        right.directScore.finalScore.compareTo(left.directScore.finalScore);
    if (result != 0) return result;
    result = _compareNullableDate(
      left.candidate.deadline,
      right.candidate.deadline,
    );
    if (result != 0) return result;
    result = _rigidity(right.candidate.flexibility)
        .compareTo(_rigidity(left.candidate.flexibility));
    if (result != 0) return result;
    result = _confirmationRank(right.candidate.confirmation)
        .compareTo(_confirmationRank(left.candidate.confirmation));
    if (result != 0) return result;
    result = _freshnessRank(right.candidate.freshness)
        .compareTo(_freshnessRank(left.candidate.freshness));
    if (result != 0) return result;
    return left.candidate.id.compareTo(right.candidate.id);
  }

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

  int _confirmationRank(LifeContextConfirmation value) => switch (value) {
        LifeContextConfirmation.confirmed => 5,
        LifeContextConfirmation.inferred => 4,
        LifeContextConfirmation.proposed => 3,
        LifeContextConfirmation.needsConfirmation => 2,
        LifeContextConfirmation.historical => 1,
        LifeContextConfirmation.rejected => 0,
      };

  int _freshnessRank(PriorityFreshness value) => switch (value) {
        PriorityFreshness.current => 2,
        PriorityFreshness.stale => 1,
        PriorityFreshness.unknown => 0,
      };

  String _cycleKey(List<String> nodes, List<String> dependencies) {
    if (nodes.isEmpty) {
      throw const PriorityException('invalid_priority_cycle');
    }
    final sortedDependencies = List<String>.of(dependencies)..sort();
    return 'cycle:${sortedDependencies.join(">")}';
  }

  double _round(num value) => (value.toDouble() * 100).roundToDouble() / 100;
}

final class _PropagationFrontier {
  const _PropagationFrontier({
    required this.currentNodeId,
    required this.nodePath,
    required this.dependencyPath,
  });

  final String currentNodeId;
  final List<String> nodePath;
  final List<String> dependencyPath;

  String get pathKey => '${nodePath.join(">")}:${dependencyPath.join(">")}';
}
