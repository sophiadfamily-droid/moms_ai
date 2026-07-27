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
      expect(PriorityFormula.weights, const {
        PriorityDimension.urgency: .25,
        PriorityDimension.importance: .25,
        PriorityDimension.deadlinePressure: .25,
        PriorityDimension.effort: .05,
        PriorityDimension.flexibility: .10,
        PriorityDimension.directImpact: .10,
        PriorityDimension.dataQuality: .10,
      });
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

    test('only closed structured consequences affect the score', () {
      final unknown = engine.score(_candidate(), evaluatedAt: now);
      for (final type in [
        PriorityConsequenceType.healthSafety,
        PriorityConsequenceType.legalAdministrative,
        PriorityConsequenceType.financial,
        PriorityConsequenceType.otherPersonCommitment,
        PriorityConsequenceType.work,
        PriorityConsequenceType.essentialLogistics,
        PriorityConsequenceType.comfortPreference,
      ]) {
        final structured = engine.score(
          _candidate(
            consequenceType: type,
            consequenceLevel: type == PriorityConsequenceType.comfortPreference
                ? PriorityConsequenceLevel.low
                : PriorityConsequenceLevel.high,
          ),
          evaluatedAt: now,
        );
        expect(structured.finalScore, greaterThan(unknown.finalScore));
        expect(
          structured.components
              .expand((component) => component.reasonCodes)
              .where((code) => code.startsWith('consequence_')),
          ['consequence_${type.name}'],
        );
      }
      expect(unknown.missingData, contains(PriorityMissingData.consequence));
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
      expect(ranking.warnings, contains(PriorityRankingWarning.truncated));
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

    test('ranking excludes foreign and terminal candidates fail-closed', () {
      final ranking = engine.rank(
        [
          _candidate(id: 'active'),
          _candidate(id: 'foreign', accountScopeId: 'other'),
          _candidate(
            id: 'completed',
            status: PriorityCandidateStatus.completed,
          ),
          _candidate(
            id: 'cancelled',
            status: PriorityCandidateStatus.cancelled,
          ),
          _candidate(id: 'expired', status: PriorityCandidateStatus.expired),
        ],
        evaluatedAt: now,
        expectedAccountScopeId: 'account',
      );
      expect(ranking.items.map((item) => item.candidate.id), ['active']);
      expect(
        ranking.warnings,
        contains(PriorityRankingWarning.excludedCandidates),
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

    test('subject roles and household structure never affect priority', () {
      final scores = [
        'child',
        'dependent-adult',
        'nanny',
        'grand-parent',
        'colleague',
        'unrelated-person',
        'household-a',
        'household-b',
      ]
          .map(
            (id) => engine
                .score(_candidate(subjectEntityId: id), evaluatedAt: now)
                .finalScore,
          )
          .toSet();
      expect(scores, hasLength(1));
    });

    test('ties use created date and stable technical IDs deterministically',
        () {
      final candidates = [
        _candidate(
          id: 'later-created',
          createdAt: now.subtract(const Duration(days: 1)),
          sourceId: 'z',
        ),
        _candidate(
          id: 'earlier-created',
          createdAt: now.subtract(const Duration(days: 2)),
          sourceId: 'z',
        ),
      ];
      expect(
        engine
            .rank(
              candidates.reversed,
              evaluatedAt: now,
              expectedAccountScopeId: 'account',
            )
            .items
            .first
            .candidate
            .id,
        'earlier-created',
      );
    });

    test('V2 domain tie-break is explicit and stable for every pair', () {
      expect(
        PriorityFormula.domainTieBreakOrderV2.keys.toSet(),
        PrioritySourceDomain.values.toSet(),
      );
      final domains = PrioritySourceDomain.values;
      for (var leftIndex = 0; leftIndex < domains.length; leftIndex++) {
        for (var rightIndex = leftIndex + 1;
            rightIndex < domains.length;
            rightIndex++) {
          final left = _candidateForDomain(domains[leftIndex]);
          final right = _candidateForDomain(domains[rightIndex]);
          final expected =
              PriorityFormula.domainTieBreakOrderV2[left.sourceDomain]! <
                      PriorityFormula.domainTieBreakOrderV2[right.sourceDomain]!
                  ? left.sourceDomain
                  : right.sourceDomain;
          for (final input in [
            [left, right],
            [right, left],
          ]) {
            final first = engine.rank(
              input,
              evaluatedAt: now,
              expectedAccountScopeId: 'account',
            );
            final repeated = engine.rank(
              input.reversed,
              evaluatedAt: now,
              expectedAccountScopeId: 'account',
            );
            expect(first.items.first.candidate.sourceDomain, expected);
            expect(
              first.items.map((item) => item.candidate.sourceDomain),
              repeated.items.map((item) => item.candidate.sourceDomain),
            );
          }
        }
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
      final candidates = adapter.fromProjection(projection, evaluatedAt: now);
      expect(candidates, hasLength(1));
      expect(candidates.single.type, PriorityCandidateType.task);
      expect(candidates.single.explicitUrgency, isNull);
      expect(
        jsonEncode(candidates.single.toJson()),
        isNot(contains('urgent enfant médecin')),
      );
    });

    test('fixed Event is comparable and Routine needs a dated occurrence', () {
      final projection = _projection([
        _item(
          id: 'event:event:fixed',
          domain: LifeContextDomain.event,
          type: 'event',
          sourceId: 'fixed',
          facts: const {
            LifeContextProjectionFactKeys.start: '2026-07-24T10:00:00Z',
            LifeContextProjectionFactKeys.end: '2026-07-24T11:00:00Z',
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
            LifeContextProjectionFactKeys.end: '2026-07-24T11:00:00Z',
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
      final candidates = adapter.fromProjection(projection, evaluatedAt: now);
      expect(candidates, hasLength(2));
      expect(
        candidates.map((candidate) => candidate.type),
        containsAll([
          PriorityCandidateType.eventCommitment,
          PriorityCandidateType.eventPreparation,
        ]),
      );
    });

    test('Event boundaries exclude ended and invalid events fail-closed', () {
      LifeContextProjection event({
        required String id,
        required String start,
        String? end,
        String status = 'active',
        DateTime? validUntil,
      }) =>
          _projection([
            _item(
              id: 'event:event:$id',
              domain: LifeContextDomain.event,
              type: 'event',
              sourceId: id,
              facts: {
                LifeContextProjectionFactKeys.status: status,
                LifeContextProjectionFactKeys.start: start,
                if (end != null) LifeContextProjectionFactKeys.end: end,
              },
              validUntil: validUntil,
            ),
          ]);

      final future = adapter.fromProjection(
        event(
          id: 'future',
          start: '2026-07-23T11:00:00Z',
          end: '2026-07-23T12:00:00Z',
        ),
        evaluatedAt: now,
      );
      final startsNow = adapter.fromProjection(
        event(
          id: 'starts-now',
          start: '2026-07-23T10:00:00Z',
          end: '2026-07-23T11:00:00Z',
        ),
        evaluatedAt: now,
      );
      final inProgress = adapter.fromProjection(
        event(
          id: 'in-progress',
          start: '2026-07-23T09:30:00Z',
          end: '2026-07-23T10:30:00Z',
        ),
        evaluatedAt: now,
      );

      expect(future, hasLength(1));
      expect(startsNow, hasLength(1));
      expect(inProgress, hasLength(1));
      for (final candidate in [...startsNow, ...inProgress]) {
        final reasons = engine
            .score(candidate, evaluatedAt: now)
            .components
            .expand((component) => component.reasonCodes);
        expect(reasons, isNot(contains('deadline_overdue')));
      }

      for (final projection in [
        event(
          id: 'ends-now',
          start: '2026-07-23T09:00:00Z',
          end: '2026-07-23T10:00:00Z',
        ),
        event(
          id: 'ended',
          start: '2026-07-23T09:00:00Z',
          end: '2026-07-23T09:59:00Z',
        ),
        event(
          id: 'expired-valid-until',
          start: '2026-07-23T09:00:00Z',
          validUntil: DateTime.utc(2026, 7, 23, 9, 59),
        ),
        event(
          id: 'invalid-end',
          start: '2026-07-23T11:00:00Z',
          end: 'not-a-date',
        ),
        event(
          id: 'end-before-start',
          start: '2026-07-23T11:00:00Z',
          end: '2026-07-23T10:59:00Z',
        ),
        event(
          id: 'cancelled',
          start: '2026-07-23T11:00:00Z',
          end: '2026-07-23T12:00:00Z',
          status: 'cancelled',
        ),
      ]) {
        expect(
          adapter.fromProjection(projection, evaluatedAt: now),
          isEmpty,
        );
      }

      final foreignCandidates = adapter.fromProjection(
        _projection(
          [
            _item(
              id: 'memory:constraint:foreign',
              domain: LifeContextDomain.memory,
              type: 'constraint',
              sourceId: 'foreign',
              facts: const {
                LifeContextProjectionFactKeys.status: 'active',
              },
            ),
          ],
          accountScopeId: 'other-account',
        ),
        evaluatedAt: now,
      );
      expect(
        engine
            .rank(
              foreignCandidates,
              evaluatedAt: now,
              expectedAccountScopeId: 'account',
            )
            .items,
        isEmpty,
      );
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
      expect(adapter.fromProjection(projection, evaluatedAt: now), isEmpty);
    });

    test('constraints require confirmed active status and a current window',
        () {
      LifeContextProjection constraint({
        required String id,
        String? status = 'active',
        LifeContextConfirmation confirmation =
            LifeContextConfirmation.confirmed,
        DateTime? validFrom,
        DateTime? validUntil,
      }) =>
          _projection([
            _item(
              id: 'memory:constraint:$id',
              domain: LifeContextDomain.memory,
              type: 'constraint',
              sourceId: id,
              facts: {
                LifeContextProjectionFactKeys.category: 'other',
                if (status != null)
                  LifeContextProjectionFactKeys.status: status,
              },
              confirmation: confirmation,
              validFrom: validFrom,
              validUntil: validUntil,
            ),
          ]);

      final active = adapter.fromProjection(
        constraint(
          id: 'active',
          validFrom: now.subtract(const Duration(days: 1)),
          validUntil: now.add(const Duration(days: 1)),
        ),
        evaluatedAt: now,
      );
      expect(active.single.type, PriorityCandidateType.constraint);

      for (final status in [
        'proposed',
        'rejected',
        'superseded',
        'expired',
        'obsolete',
        'archived',
        'deleted',
        'unknown',
      ]) {
        expect(
          adapter.fromProjection(
            constraint(id: status, status: status),
            evaluatedAt: now,
          ),
          isEmpty,
          reason: status,
        );
      }
      for (final projection in [
        constraint(id: 'missing-status', status: null),
        constraint(
          id: 'expired-by-window',
          validUntil: now.subtract(const Duration(minutes: 1)),
        ),
        constraint(id: 'at-valid-until', validUntil: now),
        constraint(
          id: 'future',
          validFrom: now.add(const Duration(minutes: 1)),
        ),
        constraint(
          id: 'proposed-confirmation',
          confirmation: LifeContextConfirmation.proposed,
        ),
        constraint(
          id: 'contradictory-confirmation',
          confirmation: LifeContextConfirmation.rejected,
        ),
      ]) {
        expect(
          adapter.fromProjection(projection, evaluatedAt: now),
          isEmpty,
        );
      }
    });

    test('cancelled, expired, invalid and corrupted candidates are excluded',
        () {
      for (final status in ['completed', 'cancelled', 'expired', 'invalid']) {
        final projection = _projection([
          _item(
            id: 'task:task:$status',
            domain: LifeContextDomain.task,
            type: 'task',
            sourceId: status,
            facts: {LifeContextProjectionFactKeys.status: status},
          ),
        ]);
        expect(
          adapter.fromProjection(projection, evaluatedAt: now),
          isEmpty,
          reason: status,
        );
      }
      final corruptEvent = _projection([
        _item(
          id: 'event:event:invalid',
          domain: LifeContextDomain.event,
          type: 'event',
          sourceId: 'invalid',
          facts: const {
            LifeContextProjectionFactKeys.start: 'not-a-date',
          },
        ),
      ]);
      expect(
        adapter.fromProjection(corruptEvent, evaluatedAt: now),
        isEmpty,
      );
    });

    test('serialized candidates and diagnostics contain no private text', () {
      final projection = _projection([
        _item(
          id: 'task:task:private',
          domain: LifeContextDomain.task,
          type: 'task',
          sourceId: 'private',
          facts: const {
            LifeContextProjectionFactKeys.status: 'active',
            LifeContextProjectionFactKeys.title:
                'Nom privé et dossier médical complet',
          },
        ),
      ]);
      final candidate =
          adapter.fromProjection(projection, evaluatedAt: now).single;
      final score = engine.score(candidate, evaluatedAt: now);
      final diagnostic = jsonEncode({
        'status': score.status.name,
        'confidence': score.confidence.name,
        'reasons': score.components
            .expand((component) => component.reasonCodes)
            .toList(),
      });
      expect(jsonEncode(candidate.toJson()), isNot(contains('Nom privé')));
      expect(diagnostic, isNot(contains('médical')));
      expect(diagnostic, isNot(contains('private')));
    });

    test('structured projection normalizes into one read-only global ranking',
        () {
      final projection = _projection([
        _item(
          id: 'event:event:medical',
          domain: LifeContextDomain.event,
          type: 'event',
          sourceId: 'medical',
          facts: const {
            LifeContextProjectionFactKeys.start: '2026-07-23T11:00:00Z',
            LifeContextProjectionFactKeys.end: '2026-07-23T11:30:00Z',
            LifeContextProjectionFactKeys.durationMinutes: '30',
            LifeContextProjectionFactKeys.consequenceType: 'healthSafety',
            LifeContextProjectionFactKeys.consequenceLevel: 'critical',
          },
        ),
        _item(
          id: 'task:task:administrative',
          domain: LifeContextDomain.task,
          type: 'task',
          sourceId: 'administrative',
          facts: const {
            LifeContextProjectionFactKeys.status: 'active',
            LifeContextProjectionFactKeys.dueDate: '2026-07-24T10:00:00Z',
            LifeContextProjectionFactKeys.consequenceType:
                'legalAdministrative',
            LifeContextProjectionFactKeys.consequenceLevel: 'high',
          },
        ),
        _item(
          id: 'routine:routine:occurrence',
          domain: LifeContextDomain.routine,
          type: 'routine',
          sourceId: 'occurrence',
          facts: const {
            LifeContextProjectionFactKeys.actionRequired: 'true',
            LifeContextProjectionFactKeys.start: '2026-07-23T18:00:00Z',
          },
        ),
        _item(
          id: 'memory:constraint:confirmed',
          domain: LifeContextDomain.memory,
          type: 'constraint',
          sourceId: 'confirmed',
          facts: const {
            LifeContextProjectionFactKeys.status: 'active',
            LifeContextProjectionFactKeys.consequenceType: 'essentialLogistics',
            LifeContextProjectionFactKeys.consequenceLevel: 'moderate',
          },
        ),
      ]);

      final candidates = adapter.fromProjection(projection, evaluatedAt: now);
      final ranking = engine.rank(
        candidates.reversed,
        evaluatedAt: now,
        expectedAccountScopeId: 'account',
      );

      expect(candidates.map((item) => item.sourceId).toSet(), {
        'medical',
        'administrative',
        'occurrence',
        'confirmed',
      });
      expect(ranking.items.first.candidate.sourceId, 'medical');
      expect(
        ranking.items.map((item) => item.candidate.sourceId).toSet(),
        candidates.map((item) => item.sourceId).toSet(),
      );
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
  String? sourceId,
  PrioritySourceDomain sourceDomain = PrioritySourceDomain.task,
  PriorityCandidateType type = PriorityCandidateType.task,
  String accountScopeId = 'account',
  PriorityCandidateStatus status = PriorityCandidateStatus.active,
  DateTime? deadline,
  DateTime? createdAt,
  int? effortMinutes,
  PriorityFlexibility flexibility = PriorityFlexibility.unknown,
  double? explicitImportance,
  double? explicitUrgency,
  PriorityFreshness freshness = PriorityFreshness.current,
  List<PriorityDirectImpact> directImpacts = const [],
  PriorityConsequenceType consequenceType = PriorityConsequenceType.unknown,
  PriorityConsequenceLevel consequenceLevel = PriorityConsequenceLevel.unknown,
  String? subjectEntityId,
}) =>
    PriorityCandidate(
      schemaVersion: schemaVersion,
      id: id,
      accountScopeId: accountScopeId,
      sourceDomain: sourceDomain,
      sourceId: sourceId ?? id,
      type: type,
      status: status,
      deadline: deadline,
      createdAt: createdAt,
      effortMinutes: effortMinutes,
      flexibility: flexibility,
      explicitImportance: explicitImportance,
      explicitUrgency: explicitUrgency,
      directImpacts: directImpacts,
      consequenceType: consequenceType,
      consequenceLevel: consequenceLevel,
      subjectEntityId: subjectEntityId,
      confirmation: LifeContextConfirmation.confirmed,
      freshness: freshness,
      provenance: PriorityProvenance(
        sourceSnapshotId: 'snapshot',
        sourceItemId: id,
        sourceKind: 'projection',
      ),
    );

PriorityCandidate _candidateForDomain(PrioritySourceDomain domain) =>
    _candidate(
      id: 'same-candidate',
      sourceId: 'same-source',
      sourceDomain: domain,
      type: switch (domain) {
        PrioritySourceDomain.task => PriorityCandidateType.task,
        PrioritySourceDomain.event => PriorityCandidateType.eventCommitment,
        PrioritySourceDomain.routine => PriorityCandidateType.routineOccurrence,
        PrioritySourceDomain.constraint => PriorityCandidateType.constraint,
      },
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

LifeContextProjection _projection(
  List<LifeContextProjectionItem> items, {
  String accountScopeId = 'account',
}) =>
    LifeContextProjection(
      projectionId: 'projection',
      sourceSnapshotId: 'snapshot',
      accountScopeId: accountScopeId,
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
  LifeContextConfirmation confirmation = LifeContextConfirmation.confirmed,
  DateTime? validFrom,
  DateTime? validUntil,
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
      confirmation: confirmation,
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
      validFrom: validFrom,
      validUntil: validUntil,
    );
