import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/life_context/life_context_domains.dart';
import 'package:moms_ai/models/life_context/life_context_graph.dart';
import 'package:moms_ai/models/priority/priority_models.dart';
import 'package:moms_ai/models/priority/priority_propagation_models.dart';
import 'package:moms_ai/services/priority/priority_engine.dart';
import 'package:moms_ai/services/priority/priority_graph_candidate_adapter.dart';
import 'package:moms_ai/services/priority/priority_propagation_engine.dart';
import 'package:moms_ai/services/priority/priority_propagation_formula.dart';

void main() {
  final now = DateTime.utc(2026, 7, 23, 10);
  final propagation = PriorityPropagationEngine();

  group('propagation models and registry', () {
    test('influence is versioned, bounded and deterministic', () {
      final influence = _influence();
      expect(influence.schemaVersion, 1);
      expect(influence.finalContribution, inInclusiveRange(0, 100));
      expect(jsonEncode(influence.toJson()), jsonEncode(influence.toJson()));
      expect(
        () => _influence(schemaVersion: 2),
        throwsA(isA<PriorityException>()),
      );
      expect(
        () => _influence(depthFactor: 1.1),
        throwsA(isA<PriorityException>()),
      );
    });

    test('registry is closed and coefficients decrease with depth', () {
      PriorityPropagationFormula.validate();
      expect(
        PriorityPropagationFormula.rules.keys,
        containsAll(LifeContextDependencyType.values),
      );
      expect(PriorityPropagationFormula.depthFactors[1], 1);
      expect(PriorityPropagationFormula.depthFactors[2], .5);
      expect(PriorityPropagationFormula.depthFactors[3], .25);
      expect(
        PriorityPropagationFormula
            .rules[LifeContextDependencyType.belongsTo]!.propagates,
        isFalse,
      );
      expect(
        PriorityPropagationFormula
            .rules[LifeContextDependencyType.custom]!.propagates,
        isFalse,
      );
    });
  });

  group('candidate/node association', () {
    const adapter = PriorityGraphCandidateAdapter();

    test('Task, Event and Routine use deterministic source identity', () {
      final candidates = [
        _candidate('task', PrioritySourceDomain.task),
        _candidate('event', PrioritySourceDomain.event,
            type: PriorityCandidateType.eventPreparation),
        _candidate('routine', PrioritySourceDomain.routine,
            type: PriorityCandidateType.routineOccurrence),
      ];
      final graph = _graph(candidates);
      for (final candidate in candidates) {
        expect(adapter.nodeForCandidate(candidate, graph)?.sourceId,
            candidate.sourceId);
      }
    });

    test(
        'candidate without node and node without candidate remain unassociated',
        () {
      final candidate = _candidate('missing', PrioritySourceDomain.task);
      final graph = _graph([_candidate('other', PrioritySourceDomain.task)]);
      expect(adapter.nodeForCandidate(candidate, graph), isNull);
      expect(
        adapter.candidatesByNode(
          _ranking([candidate], now),
          graph,
          expectedAccountScopeId: 'account',
        ),
        isEmpty,
      );
    });

    test('scope mismatch is refused', () {
      final candidate = _candidate('task', PrioritySourceDomain.task);
      expect(
        () => adapter.nodeForCandidate(
          candidate,
          _graph([candidate], accountScopeId: 'other'),
        ),
        throwsA(isA<PriorityException>()),
      );
    });
  });

  group('dependency types and direction', () {
    for (final type in [
      LifeContextDependencyType.requires,
      LifeContextDependencyType.blocks,
      LifeContextDependencyType.follows,
      LifeContextDependencyType.explicitUserDependency,
    ]) {
      test('${type.name} reinforces the prerequisite only', () {
        final a = _candidate('a', PrioritySourceDomain.task);
        final b = _candidate('b', PrioritySourceDomain.task);
        final graph = _graph([a, b], links: [('a', 'b', type)]);
        final result = propagation.propagate(
          _ranking([a, b], now),
          graph,
          expectedAccountScopeId: 'account',
          evaluatedAt: now,
        );
        expect(_score(result, 'a').propagatedContribution, greaterThan(0));
        expect(_score(result, 'b').propagatedContribution, 0);
        expect(
          _score(result, 'a').influences.single.direction,
          PriorityPropagationDirection.dependentToPrerequisite,
        );
      });
    }

    test('non-propagating types and simple relations add nothing', () {
      final a = _candidate('a', PrioritySourceDomain.task);
      final b = _candidate('b', PrioritySourceDomain.task);
      for (final type in [
        LifeContextDependencyType.belongsTo,
        LifeContextDependencyType.scheduledBy,
        LifeContextDependencyType.generatedFrom,
        LifeContextDependencyType.custom,
      ]) {
        final result = propagation.propagate(
          _ranking([a, b], now),
          _graph([a, b], links: [('a', 'b', type)]),
          expectedAccountScopeId: 'account',
          evaluatedAt: now,
        );
        expect(_score(result, 'a').propagatedContribution, 0,
            reason: type.name);
      }

      final graph = _graph([
        a,
        b
      ], relations: [
        LifeContextGraphRelation(
          sourceNodeId: _nodeId(a),
          targetNodeId: _nodeId(b),
          type: LifeContextRelationType.responsibilityFor,
          provenance: _provenance('relation'),
          freshness: LifeContextFreshness.current,
        ),
      ]);
      final result = propagation.propagate(
        _ranking([a, b], now),
        graph,
        expectedAccountScopeId: 'account',
        evaluatedAt: now,
      );
      expect(
          result.items.every((item) => item.score.propagatedContribution == 0),
          isTrue);
    });
  });

  group('chains, bounds and aggregation', () {
    test('A → B → C yields a reduced depth-two contribution to A', () {
      final candidates = [
        _candidate('a', PrioritySourceDomain.task),
        _candidate('b', PrioritySourceDomain.task),
        _candidate('c', PrioritySourceDomain.task, importance: 1),
      ];
      final result = propagation.propagate(
        _ranking(candidates, now),
        _graph(candidates, links: [
          ('a', 'b', LifeContextDependencyType.requires),
          ('b', 'c', LifeContextDependencyType.requires),
        ]),
        expectedAccountScopeId: 'account',
        evaluatedAt: now,
      );
      final aInfluences = _score(result, 'a').influences;
      final depthOne =
          aInfluences.firstWhere((influence) => influence.depth == 1);
      final depthTwo =
          aInfluences.firstWhere((influence) => influence.depth == 2);
      expect(depthTwo.depthFactor, lessThan(depthOne.depthFactor));
      expect(depthTwo.path.nodeIds, hasLength(3));
    });

    test('depth beyond three is ignored and reported truncated', () {
      final candidates = [
        for (final id in ['a', 'b', 'c', 'd', 'e'])
          _candidate(id, PrioritySourceDomain.task),
      ];
      final result = propagation.propagate(
        _ranking(candidates, now),
        _graph(candidates, links: [
          ('a', 'b', LifeContextDependencyType.requires),
          ('b', 'c', LifeContextDependencyType.requires),
          ('c', 'd', LifeContextDependencyType.requires),
          ('d', 'e', LifeContextDependencyType.requires),
        ]),
        expectedAccountScopeId: 'account',
        evaluatedAt: now,
      );
      expect(
          result.truncationState, PriorityPropagationTruncationState.truncated);
      expect(
        result.items
            .expand((item) => item.score.influences)
            .every((influence) => influence.depth <= 3),
        isTrue,
      );
    });

    test('top N and global contribution cap prevent connection explosion', () {
      final target = _candidate('target', PrioritySourceDomain.task);
      final dependents = [
        for (var index = 0; index < 8; index++)
          _candidate('d$index', PrioritySourceDomain.task, importance: 1),
      ];
      final candidates = [target, ...dependents];
      final result = propagation.propagate(
        _ranking(candidates, now),
        _graph(candidates, links: [
          for (final dependent in dependents)
            (
              'target',
              dependent.sourceId,
              LifeContextDependencyType.blocks,
            ),
        ]),
        expectedAccountScopeId: 'account',
        evaluatedAt: now,
      );
      final score = _score(result, 'target');
      expect(
        score.influences.length,
        PriorityPropagationFormula.maximumInfluencesPerCandidate,
      );
      expect(score.omittedInfluenceCount, 3);
      expect(
        score.propagatedContribution,
        lessThanOrEqualTo(
          PriorityPropagationFormula.maximumContributionPerCandidate,
        ),
      );
    });

    test('input permutation preserves adjusted ranking', () {
      final candidates = [
        _candidate('a', PrioritySourceDomain.task),
        _candidate('b', PrioritySourceDomain.task, importance: 1),
        _candidate('c', PrioritySourceDomain.task),
      ];
      final graph = _graph(candidates, links: [
        ('a', 'b', LifeContextDependencyType.blocks),
      ]);
      final first = propagation.propagate(
        _ranking(candidates, now),
        graph,
        expectedAccountScopeId: 'account',
        evaluatedAt: now,
      );
      final second = propagation.propagate(
        _ranking(candidates.reversed.toList(), now),
        graph,
        expectedAccountScopeId: 'account',
        evaluatedAt: now,
      );
      expect(
        first.items.map((item) => item.score.candidate.id),
        second.items.map((item) => item.score.candidate.id),
      );
    });
  });

  group('confirmation, freshness, deduplication and cycles', () {
    test('only confirmed and registered inferred dependencies propagate', () {
      final a = _candidate('a', PrioritySourceDomain.task);
      final b = _candidate('b', PrioritySourceDomain.task);
      for (final confirmation in [
        LifeContextConfirmation.proposed,
        LifeContextConfirmation.needsConfirmation,
        LifeContextConfirmation.rejected,
        LifeContextConfirmation.historical,
      ]) {
        final result = propagation.propagate(
          _ranking([a, b], now),
          _graph(
            [a, b],
            links: [('a', 'b', LifeContextDependencyType.requires)],
            confirmation: confirmation,
          ),
          expectedAccountScopeId: 'account',
          evaluatedAt: now,
        );
        expect(_score(result, 'a').propagatedContribution, 0,
            reason: confirmation.name);
      }
      final inferred = propagation.propagate(
        _ranking([a, b], now),
        _graph(
          [a, b],
          links: [('a', 'b', LifeContextDependencyType.requires)],
          confirmation: LifeContextConfirmation.inferred,
        ),
        expectedAccountScopeId: 'account',
        evaluatedAt: now,
      );
      expect(_score(inferred, 'a').propagatedContribution, greaterThan(0));
      expect(
        _score(inferred, 'a').influences.single.confirmationFactor,
        .5,
      );
    });

    test('stale source contribution is reduced and remains traceable', () {
      final a = _candidate('a', PrioritySourceDomain.task);
      final fresh = _candidate('fresh', PrioritySourceDomain.task);
      final stale = _candidate(
        'stale',
        PrioritySourceDomain.task,
        freshness: PriorityFreshness.stale,
      );
      final graph = _graph([
        a,
        fresh,
        stale
      ], links: [
        ('a', 'fresh', LifeContextDependencyType.requires),
        ('a', 'stale', LifeContextDependencyType.requires),
      ]);
      final result = propagation.propagate(
        _ranking([a, fresh, stale], now),
        graph,
        expectedAccountScopeId: 'account',
        evaluatedAt: now,
      );
      final influences = _score(result, 'a').influences;
      expect(
        influences
            .firstWhere(
                (item) => item.sourceCandidateId == 'priority:task:fresh')
            .freshnessFactor,
        1,
      );
      expect(
        influences
            .firstWhere(
                (item) => item.sourceCandidateId == 'priority:task:stale')
            .freshnessFactor,
        .5,
      );
    });

    test('R.1 direct impact matching the dependency is not counted again', () {
      final aBase = _candidate('a', PrioritySourceDomain.task);
      final a = _candidate(
        'a',
        PrioritySourceDomain.task,
        impacts: [
          PriorityDirectImpact(
            id: 'already-direct',
            type: PriorityImpactType.blocks,
            depth: 1,
            confirmation: LifeContextConfirmation.confirmed,
            provenance: PriorityProvenance(
              sourceSnapshotId: 'snapshot',
              sourceItemId: _nodeId(aBase),
              sourceKind: 'graph',
              ruleId: LifeContextRegisteredRuleIds.explicitDependency,
            ),
          ),
        ],
      );
      final b = _candidate('b', PrioritySourceDomain.task);
      final result = propagation.propagate(
        _ranking([a, b], now),
        _graph([
          a,
          b
        ], links: [
          ('a', 'b', LifeContextDependencyType.requires),
        ]),
        expectedAccountScopeId: 'account',
        evaluatedAt: now,
      );
      expect(_score(result, 'a').propagatedContribution, 0);
    });

    test('two- and three-node cycles terminate, are marked and stay capped',
        () {
      for (final links in [
        [
          ('a', 'b', LifeContextDependencyType.requires),
          ('b', 'a', LifeContextDependencyType.requires),
        ],
        [
          ('a', 'b', LifeContextDependencyType.requires),
          ('b', 'c', LifeContextDependencyType.requires),
          ('c', 'a', LifeContextDependencyType.requires),
        ],
      ]) {
        final ids = links.expand((link) => [link.$1, link.$2]).toSet();
        final candidates = [
          for (final id in ids) _candidate(id, PrioritySourceDomain.task),
        ];
        final result = propagation.propagate(
          _ranking(candidates, now),
          _graph(candidates, links: links),
          expectedAccountScopeId: 'account',
          evaluatedAt: now,
        );
        expect(result.cycles, isNotEmpty);
        expect(
          result.items.every(
            (item) =>
                item.score.propagatedContribution <=
                PriorityPropagationFormula.maximumContributionPerCandidate,
          ),
          isTrue,
        );
        expect(
          result.items.any(
            (item) =>
                item.score.cycleState ==
                PriorityPropagationCycleState.cycleDetected,
          ),
          isTrue,
        );
      }
    });
  });

  group('score preservation, consistency and non-discrimination', () {
    test('no dependency preserves direct score exactly', () {
      final candidate = _candidate('a', PrioritySourceDomain.task);
      final direct = _ranking([candidate], now);
      final result = propagation.propagate(
        direct,
        _graph([candidate]),
        expectedAccountScopeId: 'account',
        evaluatedAt: now,
      );
      final score = result.items.single.score;
      expect(score.directScore, same(direct.items.single.score));
      expect(score.propagatedContribution, 0);
      expect(score.adjustedScore, score.directScore.finalScore);
    });

    test('snapshot and account mismatches are refused', () {
      final candidate = _candidate('a', PrioritySourceDomain.task);
      expect(
        () => propagation.propagate(
          _ranking([candidate], now),
          _graph([candidate], snapshotId: 'other'),
          expectedAccountScopeId: 'account',
          evaluatedAt: now,
        ),
        throwsA(isA<PriorityException>()),
      );
      expect(
        () => propagation.propagate(
          _ranking([candidate], now),
          _graph([candidate], accountScopeId: 'other'),
          expectedAccountScopeId: 'account',
          evaluatedAt: now,
        ),
        throwsA(isA<PriorityException>()),
      );
    });

    test('labels and family situations cannot alter structural propagation',
        () {
      final baseline = [
        _candidate('a', PrioritySourceDomain.task),
        _candidate('b', PrioritySourceDomain.task),
      ];
      final baselineResult = propagation.propagate(
        _ranking(baseline, now),
        _graph(baseline, links: [
          ('a', 'b', LifeContextDependencyType.requires),
        ]),
        expectedAccountScopeId: 'account',
        evaluatedAt: now,
      );
      for (final suffix in [
        'single',
        'couple',
        'children',
        'mother',
        'father',
        'work',
        'personal',
        'leisure',
      ]) {
        final candidates = [
          _candidate('a-$suffix', PrioritySourceDomain.task),
          _candidate('b-$suffix', PrioritySourceDomain.task),
        ];
        final result = propagation.propagate(
          _ranking(candidates, now),
          _graph(candidates, links: [
            (
              'a-$suffix',
              'b-$suffix',
              LifeContextDependencyType.requires,
            ),
          ]),
          expectedAccountScopeId: 'account',
          evaluatedAt: now,
        );
        expect(
          result.items.map((item) => item.score.propagatedContribution).toList()
            ..sort(),
          baselineResult.items
              .map((item) => item.score.propagatedContribution)
              .toList()
            ..sort(),
          reason: suffix,
        );
      }
    });
  });
}

PriorityDependencyInfluence _influence({
  int schemaVersion = 1,
  double depthFactor = 1,
}) =>
    PriorityDependencyInfluence(
      schemaVersion: schemaVersion,
      id: 'influence',
      sourceCandidateId: 'source',
      targetCandidateId: 'target',
      dependencyId: 'dependency',
      dependencyType: LifeContextDependencyType.requires,
      depth: 1,
      direction: PriorityPropagationDirection.dependentToPrerequisite,
      rawContribution: 10,
      depthFactor: depthFactor,
      confirmationFactor: 1,
      freshnessFactor: 1,
      finalContribution: 10,
      provenance: const PriorityProvenance(
        sourceSnapshotId: 'snapshot',
        sourceItemId: 'dependency',
        sourceKind: 'graph',
      ),
      path: PriorityPropagationPath(
        nodeIds: const ['dependent', 'prerequisite'],
        dependencyIds: const ['dependency'],
        depth: 1,
        truncated: false,
      ),
      containsCycle: false,
      truncated: false,
    );

PriorityCandidate _candidate(
  String id,
  PrioritySourceDomain domain, {
  PriorityCandidateType? type,
  double? importance,
  PriorityFreshness freshness = PriorityFreshness.current,
  List<PriorityDirectImpact> impacts = const [],
}) =>
    PriorityCandidate(
      id: 'priority:${domain.name}:$id',
      accountScopeId: 'account',
      sourceDomain: domain,
      sourceId: id,
      type: type ??
          switch (domain) {
            PrioritySourceDomain.task => PriorityCandidateType.task,
            PrioritySourceDomain.event =>
              PriorityCandidateType.eventPreparation,
            PrioritySourceDomain.routine =>
              PriorityCandidateType.routineOccurrence,
          },
      status: PriorityCandidateStatus.active,
      explicitImportance: importance,
      flexibility: PriorityFlexibility.flexible,
      directImpacts: impacts,
      confirmation: LifeContextConfirmation.confirmed,
      freshness: freshness,
      provenance: PriorityProvenance(
        sourceSnapshotId: 'snapshot',
        sourceItemId: id,
        sourceKind: 'projection',
      ),
    );

PriorityRanking _ranking(List<PriorityCandidate> candidates, DateTime now) =>
    PriorityEngine().rank(
      candidates,
      evaluatedAt: now,
      expectedAccountScopeId: 'account',
    );

LifeContextGraph _graph(
  List<PriorityCandidate> candidates, {
  List<(String, String, LifeContextDependencyType)> links = const [],
  List<LifeContextGraphRelation> relations = const [],
  LifeContextConfirmation confirmation = LifeContextConfirmation.confirmed,
  String accountScopeId = 'account',
  String snapshotId = 'snapshot',
}) {
  final bySourceId = {
    for (final candidate in candidates) candidate.sourceId: candidate
  };
  return LifeContextGraph(
    accountScopeId: accountScopeId,
    snapshotId: snapshotId,
    nodes: candidates
        .map(
          (candidate) => LifeContextGraphNode(
            domain: _domain(candidate.sourceDomain),
            sourceId: candidate.sourceId,
            resourceType: _nodeType(candidate.sourceDomain),
            accountScopeId: accountScopeId,
          ),
        )
        .toList(),
    relations: relations,
    dependencies: [
      for (var index = 0; index < links.length; index++)
        LifeContextDependency(
          prerequisiteNodeId: _nodeId(bySourceId[links[index].$1]!),
          dependentNodeId: _nodeId(bySourceId[links[index].$2]!),
          type: links[index].$3,
          provenance: _provenance(
            'dependency-$index-${links[index].$3.name}',
            confirmation: confirmation,
            snapshotId: snapshotId,
          ),
        ),
    ],
  );
}

LifeContextRelationProvenance _provenance(
  String id, {
  LifeContextConfirmation confirmation = LifeContextConfirmation.confirmed,
  String snapshotId = 'snapshot',
}) =>
    LifeContextRelationProvenance(
      sourceDomain: LifeContextDomain.task,
      sourceRecordId: id,
      evidenceType: 'explicit',
      confirmation: confirmation,
      ruleId: LifeContextRegisteredRuleIds.explicitDependency,
      ruleVersion: 1,
      readAt: DateTime.utc(2026, 7, 23),
      snapshotId: snapshotId,
      sectionSource: LifeContextSourceKind.taskService,
      nature: LifeContextRelationNature.direct,
    );

String _nodeId(PriorityCandidate candidate) =>
    LifeContextGraphNode.deterministicId(
      _domain(candidate.sourceDomain),
      _nodeType(candidate.sourceDomain),
      candidate.sourceId,
    );

LifeContextDomain _domain(PrioritySourceDomain domain) => switch (domain) {
      PrioritySourceDomain.task => LifeContextDomain.task,
      PrioritySourceDomain.event => LifeContextDomain.event,
      PrioritySourceDomain.routine => LifeContextDomain.routine,
    };

LifeContextNodeType _nodeType(PrioritySourceDomain domain) => switch (domain) {
      PrioritySourceDomain.task => LifeContextNodeType.task,
      PrioritySourceDomain.event => LifeContextNodeType.event,
      PrioritySourceDomain.routine => LifeContextNodeType.routine,
    };

PropagatedPriorityScore _score(
  PropagatedPriorityRanking ranking,
  String sourceId,
) =>
    ranking.items
        .firstWhere((item) => item.score.candidate.sourceId == sourceId)
        .score;
