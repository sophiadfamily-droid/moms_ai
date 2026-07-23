import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/life_context/life_context_domains.dart';
import 'package:moms_ai/models/life_context/life_context_graph.dart';
import 'package:moms_ai/models/life_context/life_context_projection.dart';
import 'package:moms_ai/models/priority/priority_models.dart';
import 'package:moms_ai/services/priority/priority_candidate_adapter.dart';
import 'package:moms_ai/services/priority/priority_engine.dart';
import 'package:moms_ai/services/priority/priority_formula.dart';

void main() {
  final now = DateTime.utc(2026, 7, 23, 10);
  final engine = PriorityEngine();

  group('priority models and formula', () {
    test('versions, bounds and deterministic serialization are enforced', () {
      final candidate = _candidate(deadline: now.add(const Duration(hours: 2)));
      final first = engine.score(candidate, evaluatedAt: now);
      final second = engine.score(candidate, evaluatedAt: now);

      expect(first.formulaVersion, PriorityFormula.version);
      expect(first.finalScore, inInclusiveRange(0, 100));
      expect(first.finalScore.isFinite, isTrue);
      expect(jsonEncode(first.toJson()), jsonEncode(second.toJson()));
      expect(
        () => _candidate(schemaVersion: 2),
        throwsA(isA<PriorityException>()),
      );
      expect(
        () => PriorityScore(
          candidateId: 'candidate',
          formulaVersion: 1,
          finalScore: double.nan,
          status: PriorityCalculationStatus.scored,
          confidence: PriorityConfidence.complete,
          components: first.components,
          missingData: const [],
        ),
        throwsA(isA<PriorityException>()),
      );
    });

    test('scope mismatch and invalid values are rejected', () {
      expect(
        () => engine.score(
          _candidate(),
          evaluatedAt: now,
          expectedAccountScopeId: 'other',
        ),
        throwsA(
          isA<PriorityException>().having(
            (error) => error.code,
            'code',
            'priority_account_mismatch',
          ),
        ),
      );
      expect(
        () => _candidate(explicitImportance: 1.1),
        throwsA(isA<PriorityException>()),
      );
    });
  });

  group('structured dimensions', () {
    test('urgency uses explicit values and UTC deadline buckets', () {
      double urgency(PriorityCandidate candidate) => engine
          .score(candidate, evaluatedAt: now)
          .components
          .firstWhere((item) => item.dimension == PriorityDimension.urgency)
          .normalizedValue;

      expect(urgency(_candidate(deadline: now.subtract(const Duration()))), 1);
      expect(urgency(_candidate(deadline: now.add(const Duration(hours: 1)))),
          .95);
      expect(urgency(_candidate(deadline: DateTime.utc(2026, 7, 23, 20))), .8);
      expect(
          urgency(_candidate(deadline: now.add(const Duration(days: 1)))), .7);
      expect(
          urgency(_candidate(deadline: now.add(const Duration(days: 3)))), .55);
      expect(
          urgency(_candidate(deadline: now.add(const Duration(days: 7)))), .35);
      expect(urgency(_candidate(deadline: now.add(const Duration(days: 30)))),
          .15);
      expect(urgency(_candidate()), .5);
      expect(urgency(_candidate(explicitUrgency: .9)), .9);
    });

    test('importance is explicit or neutral and marked missing', () {
      final explicit = engine.score(
        _candidate(explicitImportance: .8),
        evaluatedAt: now,
      );
      final unknown = engine.score(_candidate(), evaluatedAt: now);
      expect(_value(explicit, PriorityDimension.importance), .8);
      expect(_value(unknown, PriorityDimension.importance), .5);
      expect(unknown.missingData, contains(PriorityMissingData.importance));
    });

    test('deadline pressure compares structured duration with remaining time',
        () {
      final feasible = engine.score(
        _candidate(
          deadline: now.add(const Duration(hours: 3)),
          effortMinutes: 10,
        ),
        evaluatedAt: now,
      );
      final infeasible = engine.score(
        _candidate(
          deadline: now.add(const Duration(hours: 3)),
          effortMinutes: 240,
        ),
        evaluatedAt: now,
      );
      expect(
        _value(infeasible, PriorityDimension.deadlinePressure),
        greaterThan(_value(feasible, PriorityDimension.deadlinePressure)),
      );
    });

    test('effort alone neither rewards short work nor punishes long work', () {
      final short = engine.score(
        _candidate(effortMinutes: 10),
        evaluatedAt: now,
      );
      final long = engine.score(
        _candidate(effortMinutes: 480),
        evaluatedAt: now,
      );
      expect(_value(short, PriorityDimension.effort), .5);
      expect(short.finalScore, long.finalScore);
    });

    test('flexibility only follows the explicit structured field', () {
      final fixed = engine.score(
        _candidate(flexibility: PriorityFlexibility.fixed),
        evaluatedAt: now,
      );
      final flexible = engine.score(
        _candidate(flexibility: PriorityFlexibility.veryFlexible),
        evaluatedAt: now,
      );
      expect(_value(fixed, PriorityDimension.flexibility), 1);
      expect(_value(flexible, PriorityDimension.flexibility), .2);
    });

    test('only confirmed unique direct depth-one impacts count', () {
      final score = engine.score(
        _candidate(
          directImpacts: [
            _impact('direct', PriorityImpactType.blocks),
            _impact('uncertain', PriorityImpactType.responsibility,
                confirmation: LifeContextConfirmation.needsConfirmation),
            _impact('transitive', PriorityImpactType.blocks, depth: 2),
          ],
        ),
        evaluatedAt: now,
      );
      expect(_value(score, PriorityDimension.directImpact), 1);
      expect(
        score.components
            .firstWhere(
              (item) => item.dimension == PriorityDimension.directImpact,
            )
            .rawValue,
        1,
      );
    });

    test('missing data and stale state remain explicit', () {
      final score = engine.score(
        _candidate(freshness: PriorityFreshness.stale),
        evaluatedAt: now,
      );
      expect(score.status, PriorityCalculationStatus.staleSource);
      expect(score.confidence, isNot(PriorityConfidence.complete));
      expect(score.missingData, contains(PriorityMissingData.deadline));
      expect(score.missingData, contains(PriorityMissingData.importance));
    });
  });

  group('stable ranking and non-discrimination', () {
    test('tie breaks by deadline, rigidity, confirmation, freshness and id',
        () {
      final candidates = [
        _candidate(id: 'z', deadline: now.add(const Duration(days: 2))),
        _candidate(id: 'a', deadline: now.add(const Duration(days: 1))),
      ];
      expect(
        engine
            .rank(
              candidates,
              evaluatedAt: now,
              expectedAccountScopeId: 'account',
            )
            .items
            .first
            .candidate
            .id,
        'a',
      );

      final same = [
        _candidate(id: 'z'),
        _candidate(id: 'a'),
      ];
      expect(
        engine
            .rank(
              same.reversed,
              evaluatedAt: now,
              expectedAccountScopeId: 'account',
            )
            .items
            .map((item) => item.candidate.id),
        ['a', 'z'],
      );
    });

    test('ranking is bounded and reports omissions', () {
      final ranking = engine.rank(
        [
          _candidate(id: 'a'),
          _candidate(id: 'b'),
          _candidate(id: 'c'),
        ],
        evaluatedAt: now,
        expectedAccountScopeId: 'account',
        limit: 2,
      );
      expect(ranking.items, hasLength(2));
      expect(ranking.omittedCount, 1);
      expect(
        () => engine.rank(
          [_candidate()],
          evaluatedAt: now,
          expectedAccountScopeId: 'account',
          limit: PriorityFormula.maximumRankingSize + 1,
        ),
        throwsA(isA<PriorityException>()),
      );
    });

    test('family, gender, work and visible labels cannot affect a score', () {
      final baseline =
          engine.score(_candidate(id: 'baseline'), evaluatedAt: now);
      for (final id in [
        'single',
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
        'urgent-child-doctor-title',
      ]) {
        final score = engine.score(_candidate(id: id), evaluatedAt: now);
        expect(score.finalScore, baseline.finalScore, reason: id);
      }
    });
  });

  group('Life Context adapter', () {
    const adapter = PriorityCandidateAdapter();

    test('Task is adapted without reading text and completed Task is excluded',
        () {
      final projection = _projection([
        _item(
          id: 'task:task:open',
          domain: LifeContextDomain.task,
          type: 'task',
          sourceId: 'open',
          facts: const {
            LifeContextProjectionFactKeys.status: 'active',
            LifeContextProjectionFactKeys.dueDate: '2026-07-24T10:00:00Z',
            LifeContextProjectionFactKeys.title: 'urgent enfant médecin',
          },
        ),
        _item(
          id: 'task:task:done',
          domain: LifeContextDomain.task,
          type: 'task',
          sourceId: 'done',
          facts: const {LifeContextProjectionFactKeys.status: 'completed'},
        ),
      ]);
      final candidates = adapter.fromProjection(projection);
      expect(candidates, hasLength(1));
      expect(candidates.single.type, PriorityCandidateType.task);
      expect(candidates.single.explicitUrgency, isNull);
      expect(
        jsonEncode(candidates.single.toJson()),
        isNot(contains('urgent enfant médecin')),
      );
    });

    test('Event and Routine require explicit structured action markers', () {
      final projection = _projection([
        _item(
          id: 'event:event:fixed',
          domain: LifeContextDomain.event,
          type: 'event',
          sourceId: 'fixed',
          facts: const {
            LifeContextProjectionFactKeys.start: '2026-07-24T10:00:00Z',
          },
        ),
        _item(
          id: 'event:event:prep',
          domain: LifeContextDomain.event,
          type: 'event',
          sourceId: 'prep',
          facts: const {
            LifeContextProjectionFactKeys.actionRequired: 'true',
            LifeContextProjectionFactKeys.start: '2026-07-24T10:00:00Z',
          },
        ),
        _item(
          id: 'routine:routine:info',
          domain: LifeContextDomain.routine,
          type: 'routine',
          sourceId: 'info',
          facts: const {LifeContextProjectionFactKeys.actionRequired: 'true'},
        ),
      ]);
      final candidates = adapter.fromProjection(projection);
      expect(candidates, hasLength(1));
      expect(candidates.single.type, PriorityCandidateType.eventPreparation);
    });

    test('free Memory and Human facts never become candidates', () {
      final projection = _projection([
        _item(
          id: 'memory:memory:goal',
          domain: LifeContextDomain.memory,
          type: 'memory',
          sourceId: 'goal',
          facts: const {LifeContextProjectionFactKeys.title: 'goal'},
        ),
        _item(
          id: 'human:person:one',
          domain: LifeContextDomain.human,
          type: 'person',
          sourceId: 'one',
          facts: const {LifeContextProjectionFactKeys.kind: 'person'},
        ),
      ]);
      expect(adapter.fromProjection(projection), isEmpty);
    });

    test('LC.2 consequences are bounded to direct depth one', () {
      final impacts = adapter.directImpactsFromConsequences(
        [
          LifeContextTechnicalConsequence(
            triggerNodeId: 'task:a',
            affectedNodeId: 'task:b',
            relationPath: const ['dependency:a:b'],
            impactType: LifeContextImpactType.refreshProjection,
            ruleId: LifeContextRegisteredRuleIds.explicitDependency,
            depth: 1,
            containsCycle: false,
            confirmation: LifeContextConfirmation.confirmed,
          ),
          LifeContextTechnicalConsequence(
            triggerNodeId: 'task:a',
            affectedNodeId: 'task:c',
            relationPath: const ['dependency:a:b', 'dependency:b:c'],
            impactType: LifeContextImpactType.refreshProjection,
            ruleId: LifeContextRegisteredRuleIds.explicitDependency,
            depth: 2,
            containsCycle: false,
            confirmation: LifeContextConfirmation.confirmed,
          ),
        ],
        sourceSnapshotId: 'snapshot',
      );
      expect(impacts, hasLength(1));
      expect(impacts.single.depth, 1);
    });
  });
}

double _value(PriorityScore score, PriorityDimension dimension) =>
    score.components
        .firstWhere((component) => component.dimension == dimension)
        .normalizedValue;

PriorityCandidate _candidate({
  int schemaVersion = PriorityCandidate.currentSchemaVersion,
  String id = 'candidate',
  DateTime? deadline,
  int? effortMinutes,
  PriorityFlexibility flexibility = PriorityFlexibility.unknown,
  double? explicitImportance,
  double? explicitUrgency,
  PriorityFreshness freshness = PriorityFreshness.current,
  List<PriorityDirectImpact> directImpacts = const [],
}) =>
    PriorityCandidate(
      schemaVersion: schemaVersion,
      id: id,
      accountScopeId: 'account',
      sourceDomain: PrioritySourceDomain.task,
      sourceId: id,
      type: PriorityCandidateType.task,
      status: PriorityCandidateStatus.active,
      deadline: deadline,
      effortMinutes: effortMinutes,
      flexibility: flexibility,
      explicitImportance: explicitImportance,
      explicitUrgency: explicitUrgency,
      directImpacts: directImpacts,
      confirmation: LifeContextConfirmation.confirmed,
      freshness: freshness,
      provenance: PriorityProvenance(
        sourceSnapshotId: 'snapshot',
        sourceItemId: id,
        sourceKind: 'projection',
      ),
    );

PriorityDirectImpact _impact(
  String id,
  PriorityImpactType type, {
  int depth = 1,
  LifeContextConfirmation confirmation = LifeContextConfirmation.confirmed,
}) =>
    PriorityDirectImpact(
      id: id,
      type: type,
      depth: depth,
      confirmation: confirmation,
      provenance: const PriorityProvenance(
        sourceSnapshotId: 'snapshot',
        sourceItemId: 'source',
        sourceKind: 'lifeContextConsequence',
      ),
    );

LifeContextProjection _projection(List<LifeContextProjectionItem> items) =>
    LifeContextProjection(
      projectionId: 'projection',
      sourceSnapshotId: 'snapshot',
      accountScopeId: 'account',
      purpose: LifeContextConsumerPurpose.conversation,
      generatedAt: DateTime.utc(2026, 7, 23),
      state: LifeContextProjectionState.complete,
      budgetRequested: 100,
      budgetUsed: items.fold(0, (sum, item) => sum + item.budgetCost),
      sections: [
        LifeContextProjectionSection(
          type: LifeContextProjectionSectionType.task,
          availability: LifeContextAvailability.available,
          freshness: LifeContextFreshness.current,
          items: items,
          budgetLimit: 100,
          budgetUsed: items.fold(0, (sum, item) => sum + item.budgetCost),
          omittedCount: 0,
          truncated: false,
        ),
      ],
      omittedCount: 0,
      warningCodes: const [],
    );

LifeContextProjectionItem _item({
  required String id,
  required LifeContextDomain domain,
  required String type,
  required String sourceId,
  required Map<String, String> facts,
}) =>
    LifeContextProjectionItem(
      id: id,
      domain: domain,
      type: type,
      facts: [
        for (final entry in facts.entries)
          LifeContextProjectionFact(
            key: entry.key,
            value: entry.value,
            sensitivity: entry.key == LifeContextProjectionFactKeys.title
                ? LifeContextSensitivityLevel.ordinaryPersonal
                : LifeContextSensitivityLevel.publicTechnical,
          ),
      ],
      confirmation: LifeContextConfirmation.confirmed,
      freshness: LifeContextFreshness.current,
      provenance: LifeContextProjectionProvenance(
        sourceDomain: domain,
        sourceId: sourceId,
        sourceSnapshotId: 'snapshot',
        sourceKind: switch (domain) {
          LifeContextDomain.event => LifeContextSourceKind.eventService,
          LifeContextDomain.task => LifeContextSourceKind.taskService,
          LifeContextDomain.routine =>
            LifeContextSourceKind.legacyProfileRoutine,
          LifeContextDomain.memory => LifeContextSourceKind.memoryFirestore,
          _ => LifeContextSourceKind.humanModelLocal,
        },
      ),
    );
