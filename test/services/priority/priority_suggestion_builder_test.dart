import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/life_context/life_context_domains.dart';
import 'package:moms_ai/models/life_context/life_context_graph.dart';
import 'package:moms_ai/models/life_context/life_context_projection.dart';
import 'package:moms_ai/models/local_notification_models.dart';
import 'package:moms_ai/models/priority/priority_models.dart';
import 'package:moms_ai/models/priority/priority_suggestion_models.dart';
import 'package:moms_ai/models/proactive_detection.dart';
import 'package:moms_ai/services/priority/priority_candidate_adapter.dart';
import 'package:moms_ai/services/priority/priority_engine.dart';
import 'package:moms_ai/services/priority/priority_suggestion_builder.dart';
import 'package:moms_ai/services/priority/priority_suggestion_conversation_context.dart';

void main() {
  final now = DateTime.utc(2026, 7, 27, 10);
  const builder = PrioritySuggestionBuilder();

  group('selection and temporal safety', () {
    test('filters in exact ranking order without a second suggestion ranking',
        () {
      final ordered = [
        _candidate(
          id: 'a-monitor',
          deadline: now.add(const Duration(days: 2)),
          effortMinutes: 30,
        ),
        _candidate(
          id: 'b-overdue',
          deadline: now.subtract(const Duration(minutes: 1)),
          consequenceType: PriorityConsequenceType.financial,
          consequenceLevel: PriorityConsequenceLevel.high,
        ),
        _candidate(
          id: 'c-fixed',
          type: PriorityCandidateType.eventCommitment,
          sourceDomain: PrioritySourceDomain.event,
          start: now.add(const Duration(minutes: 30)),
          deadline: now.add(const Duration(minutes: 30)),
          flexibility: PriorityFlexibility.fixed,
        ),
        _candidate(
          id: 'd-today',
          deadline: now.add(const Duration(hours: 4)),
          effortMinutes: 30,
        ),
      ];
      for (final sourceInput in [ordered, ordered.reversed.toList()]) {
        final result = builder.build(
          ranking: _explicitRanking(now, ordered, scoreInput: sourceInput),
          accountScopeId: 'account',
          referenceDate: now,
        );
        expect(
          result.suggestions.map((item) => item.primaryCandidateId),
          ['a-monitor', 'b-overdue', 'c-fixed'],
        );
      }
    });

    test('ignored ranked candidate does not reorder the following suggestions',
        () {
      final result = builder.build(
        ranking: _explicitRanking(now, [
          _candidate(id: 'ignored'),
          _candidate(
            id: 'first-admissible',
            deadline: now.add(const Duration(days: 2)),
            effortMinutes: 30,
          ),
          _candidate(
            id: 'second-admissible',
            deadline: now.add(const Duration(hours: 3)),
            effortMinutes: 30,
          ),
        ]),
        accountScopeId: 'account',
        referenceDate: now,
      );
      expect(
        result.suggestions.map((item) => item.primaryCandidateId),
        ['first-admissible', 'second-admissible'],
      );
    });

    test('returns no suggestion for distant or non-actionable candidates', () {
      final result = builder.build(
        ranking: _ranking(
          now,
          [
            _candidate(
              id: 'distant',
              deadline: now.add(const Duration(days: 21)),
            ),
            _candidate(id: 'no-deadline'),
          ],
        ),
        accountScopeId: 'account',
        referenceDate: now,
      );
      expect(result.suggestions, isEmpty);
      expect(
        result.warnings,
        contains(PrioritySuggestionWarning.noEligibleSuggestion),
      );
    });

    test('produces at most three useful suggestions, not simply top three', () {
      final candidates = [
        _candidate(id: 'not-actionable'),
        _candidate(
          id: 'soon-event',
          type: PriorityCandidateType.eventCommitment,
          sourceDomain: PrioritySourceDomain.event,
          start: now.add(const Duration(minutes: 30)),
          deadline: now.add(const Duration(minutes: 30)),
          flexibility: PriorityFlexibility.fixed,
        ),
        _candidate(
          id: 'today',
          deadline: now.add(const Duration(hours: 5)),
          effortMinutes: 30,
        ),
        _candidate(
          id: 'three-days',
          deadline: now.add(const Duration(days: 2)),
          effortMinutes: 30,
        ),
        _candidate(
          id: 'fourth',
          deadline: now.add(const Duration(days: 2, hours: 1)),
          effortMinutes: 30,
        ),
      ];
      final result = builder.build(
        ranking: _ranking(now, candidates),
        accountScopeId: 'account',
        referenceDate: now,
      );
      expect(result.suggestions, hasLength(3));
      expect(
        result.suggestions.map((item) => item.primaryCandidateId).toSet(),
        hasLength(3),
      );
      expect(
        result.suggestions.map((item) => item.primaryCandidateId),
        isNot(contains('not-actionable')),
      );
    });

    test('fixed event soon is protected and in-progress event is not overdue',
        () {
      final soon = builder.build(
        ranking: _ranking(
          now,
          [
            _candidate(
              id: 'soon',
              type: PriorityCandidateType.eventCommitment,
              sourceDomain: PrioritySourceDomain.event,
              start: now.add(const Duration(hours: 2)),
              deadline: now.add(const Duration(hours: 2)),
              flexibility: PriorityFlexibility.fixed,
            ),
          ],
        ),
        accountScopeId: 'account',
        referenceDate: now,
      );
      expect(
        soon.suggestions.single.suggestionType,
        PrioritySuggestionType.protectFixedCommitment,
      );

      final inProgress = builder.build(
        ranking: _ranking(
          now,
          [
            _candidate(
              id: 'running',
              type: PriorityCandidateType.eventCommitment,
              sourceDomain: PrioritySourceDomain.event,
              start: now.subtract(const Duration(minutes: 30)),
              flexibility: PriorityFlexibility.fixed,
            ),
          ],
        ),
        accountScopeId: 'account',
        referenceDate: now,
      );
      expect(inProgress.suggestions, isEmpty);
    });

    test('outbound travel permits preparation without assuming return travel',
        () {
      final result = builder.build(
        ranking: _ranking(
          now,
          [
            _candidate(
              id: 'travel',
              type: PriorityCandidateType.eventCommitment,
              sourceDomain: PrioritySourceDomain.event,
              start: now.add(const Duration(minutes: 45)),
              deadline: now.add(const Duration(minutes: 45)),
              flexibility: PriorityFlexibility.fixed,
              travelGoMinutes: 20,
              marginMinutes: null,
            ),
          ],
        ),
        accountScopeId: 'account',
        referenceDate: now,
      );
      final suggestion = result.suggestions.single;
      expect(suggestion.suggestionType, PrioritySuggestionType.prepare);
      expect(
        suggestion.reasonCodes,
        contains(PrioritySuggestionReason.structuredOutboundTravel),
      );
      expect(suggestion.toJson().toString(), isNot(contains('travelBack')));
    });

    test('overdue task is reviewed even without a structured consequence', () {
      final result = builder.build(
        ranking: _ranking(
          now,
          [
            _candidate(
              id: 'overdue-structured',
              deadline: now.subtract(const Duration(minutes: 1)),
              consequenceType: PriorityConsequenceType.legalAdministrative,
              consequenceLevel: PriorityConsequenceLevel.high,
            ),
            _candidate(
              id: 'overdue-unknown',
              deadline: now.subtract(const Duration(minutes: 1)),
            ),
          ],
        ),
        accountScopeId: 'account',
        referenceDate: now,
      );
      expect(result.suggestions, hasLength(2));
      expect(
        result.suggestions.first.suggestionType,
        PrioritySuggestionType.reviewOverdueItem,
      );
      expect(
        result.suggestions.first.primaryCandidateId,
        'overdue-structured',
      );
      expect(
        result.suggestions.last.suggestionType,
        PrioritySuggestionType.reviewOverdueItem,
      );
      expect(
        result.suggestions.last.primaryCandidateId,
        'overdue-unknown',
      );
    });

    test('past Event, Routine and Constraint never become overdue suggestions',
        () {
      final result = builder.build(
        ranking: _explicitRanking(now, [
          for (final entry in [
            (
              'past-event',
              PriorityCandidateType.eventCommitment,
              PrioritySourceDomain.event,
            ),
            (
              'running-event',
              PriorityCandidateType.eventCommitment,
              PrioritySourceDomain.event,
            ),
            (
              'past-routine',
              PriorityCandidateType.routineOccurrence,
              PrioritySourceDomain.routine,
            ),
            (
              'constraint',
              PriorityCandidateType.constraint,
              PrioritySourceDomain.constraint,
            ),
          ])
            _candidate(
              id: entry.$1,
              type: entry.$2,
              sourceDomain: entry.$3,
              start: now.subtract(const Duration(hours: 1)),
              deadline: now.subtract(const Duration(minutes: 1)),
              consequenceType: PriorityConsequenceType.financial,
              consequenceLevel: PriorityConsequenceLevel.high,
            ),
        ]),
        accountScopeId: 'account',
        referenceDate: now,
      );
      expect(
        result.suggestions.where(
          (item) =>
              item.suggestionType == PrioritySuggestionType.reviewOverdueItem,
        ),
        isEmpty,
      );
    });

    test('dueToday follows civil date, not an hour threshold', () {
      PrioritySuggestion suggestionAt(DateTime reference, DateTime deadline) {
        return builder
            .build(
              ranking: _ranking(
                reference,
                [
                  _candidate(
                    id: 'due',
                    deadline: deadline,
                    effortMinutes: 30,
                  ),
                ],
              ),
              accountScopeId: 'account',
              referenceDate: reference,
            )
            .suggestions
            .single;
      }

      final midnight = DateTime.utc(2026, 7, 27);
      final sameDay = suggestionAt(midnight, DateTime.utc(2026, 7, 27, 18));
      expect(sameDay.horizon, PrioritySuggestionHorizon.today);
      expect(
        sameDay.reasonCodes,
        contains(PrioritySuggestionReason.dueToday),
      );

      final evening = DateTime.utc(2026, 7, 27, 20);
      final nextMorning = suggestionAt(evening, DateTime.utc(2026, 7, 28, 8));
      expect(
        nextMorning.horizon,
        PrioritySuggestionHorizon.nextTwentyFourHours,
      );
      expect(
        nextMorning.reasonCodes,
        contains(PrioritySuggestionReason.dueWithin24Hours),
      );
      expect(
        nextMorning.reasonCodes,
        isNot(contains(PrioritySuggestionReason.dueToday)),
      );

      final beforeMidnight = DateTime.utc(2026, 7, 27, 23);
      expect(
        suggestionAt(
          beforeMidnight,
          DateTime.utc(2026, 7, 27, 23, 30),
        ).reasonCodes,
        contains(PrioritySuggestionReason.dueToday),
      );
      expect(
        suggestionAt(
          beforeMidnight,
          DateTime.utc(2026, 7, 28, 0, 30),
        ).reasonCodes,
        contains(PrioritySuggestionReason.dueWithin24Hours),
      );
      expect(
        suggestionAt(
          midnight,
          midnight.add(const Duration(hours: 24)),
        ).reasonCodes,
        contains(PrioritySuggestionReason.dueWithin24Hours),
      );
    });

    test('urgent task asks for deadline before duration', () {
      final result = builder.build(
        ranking: _ranking(
          now,
          [
            _candidate(id: 'urgent', explicitUrgency: .9),
            _candidate(id: 'ordinary'),
          ],
        ),
        accountScopeId: 'account',
        referenceDate: now,
      );
      expect(result.suggestions, hasLength(1));
      expect(
        result.suggestions.single.suggestionType,
        PrioritySuggestionType.clarifyMissingInformation,
      );
      expect(
        result.suggestions.single.proposedNextStep,
        PrioritySuggestionNextStep.provideDeadline,
      );
      expect(
        result.suggestions.single.reasonCodes,
        contains(PrioritySuggestionReason.missingDeadlineBlocksAssessment),
      );
    });

    test('old open task without a date is proposed for a relevance check', () {
      final result = builder.build(
        ranking: _ranking(
          now,
          [
            _candidate(
              id: 'old-open-task',
              createdAt: now.subtract(const Duration(days: 31)),
            ),
          ],
        ),
        accountScopeId: 'account',
        referenceDate: now,
      );

      expect(result.suggestions, hasLength(1));
      expect(
        result.suggestions.single.suggestionType,
        PrioritySuggestionType.reviewOverdueItem,
      );
      expect(
        result.suggestions.single.reasonCodes,
        contains(PrioritySuggestionReason.staleOpenTask),
      );
      expect(
        result.suggestions.single.proposedNextStep,
        PrioritySuggestionNextStep.openItem,
      );
    });

    test('recent or future-created undated task does not become stale', () {
      for (final createdAt in [
        now.subtract(const Duration(days: 29)),
        now.add(const Duration(minutes: 1)),
      ]) {
        final result = builder.build(
          ranking: _ranking(
            now,
            [_candidate(id: 'task', createdAt: createdAt)],
          ),
          accountScopeId: 'account',
          referenceDate: now,
        );
        expect(result.suggestions, isEmpty);
      }
    });
  });

  group('admissibility, conflict and identity', () {
    test('stale, future and foreign rankings fail closed', () {
      final ranking = _ranking(now, [
        _candidate(
          id: 'due',
          deadline: now.add(const Duration(hours: 1)),
        ),
      ]);
      expect(
        builder
            .build(
              ranking: ranking,
              accountScopeId: 'account',
              referenceDate: now.add(const Duration(minutes: 15)),
            )
            .warnings,
        contains(PrioritySuggestionWarning.staleRanking),
      );
      expect(
        builder
            .build(
              ranking: ranking,
              accountScopeId: 'account',
              referenceDate: now.subtract(const Duration(seconds: 1)),
            )
            .warnings,
        contains(PrioritySuggestionWarning.futureRanking),
      );
      expect(
        builder
            .build(
              ranking: ranking,
              accountScopeId: 'other',
              referenceDate: now,
            )
            .suggestions,
        isEmpty,
      );
    });

    test('only canonical current conflict evidence creates reviewConflict', () {
      final ranking = _ranking(now, [
        _candidate(id: 'first', sourceId: 'event-a'),
        _candidate(id: 'second', sourceId: 'event-b'),
      ]);
      final result = builder.build(
        ranking: ranking,
        accountScopeId: 'account',
        referenceDate: now,
        detectionSignals: [_conflict(now)],
      );
      expect(result.suggestions, hasLength(1));
      final suggestion = result.suggestions.single;
      expect(
        suggestion.suggestionType,
        PrioritySuggestionType.reviewConflict,
      );
      expect(suggestion.confirmationRequired, isTrue);
      expect(suggestion.supportingCandidateIds, hasLength(1));

      final noProof = builder.build(
        ranking: ranking,
        accountScopeId: 'account',
        referenceDate: now,
      );
      expect(noProof.suggestions, isEmpty);
    });

    test('partial and absent conflict participants fail closed', () {
      final completeRanking = _ranking(now, [
        _candidate(id: 'first', sourceId: 'event-a'),
        _candidate(id: 'second', sourceId: 'event-b'),
      ]);
      final partialRanking = _ranking(now, [
        _candidate(id: 'first', sourceId: 'event-a'),
      ]);
      for (final input in [
        (
          partialRanking,
          _conflict(now),
        ),
        (
          completeRanking,
          _conflict(now, participants: const ['event-a']),
        ),
      ]) {
        final result = builder.build(
          ranking: input.$1,
          accountScopeId: 'account',
          referenceDate: now,
          detectionSignals: [input.$2],
        );
        expect(
          result.suggestions.where(
            (item) =>
                item.suggestionType == PrioritySuggestionType.reviewConflict,
          ),
          isEmpty,
        );
        expect(
          result.warnings,
          contains(PrioritySuggestionWarning.invalidEvidence),
        );
      }
    });

    test('equivalent conflict proofs merge and incompatible proofs are refused',
        () {
      final ranking = _ranking(now, [
        _candidate(id: 'first', sourceId: 'event-a'),
        _candidate(id: 'second', sourceId: 'event-b'),
      ]);
      final equivalent = [
        _conflict(now, detectionId: 'detection-b'),
        _conflict(now, detectionId: 'detection-a'),
      ];
      final merged = builder.build(
        ranking: ranking,
        accountScopeId: 'account',
        referenceDate: now,
        detectionSignals: equivalent,
      );
      expect(
        merged.suggestions.where(
          (item) =>
              item.suggestionType == PrioritySuggestionType.reviewConflict,
        ),
        hasLength(1),
      );

      final incompatible = [
        _conflict(now, fingerprint: 'conflict-one'),
        _conflict(now, fingerprint: 'conflict-two'),
      ];
      for (final input in [incompatible, incompatible.reversed.toList()]) {
        final result = builder.build(
          ranking: ranking,
          accountScopeId: 'account',
          referenceDate: now,
          detectionSignals: input,
        );
        expect(result.suggestions, isEmpty);
        expect(
          result.warnings,
          contains(PrioritySuggestionWarning.invalidEvidence),
        );
      }
    });

    test('same inputs, reversed candidates and evidence yield stable identity',
        () {
      final candidates = [
        _candidate(
          id: 'a',
          deadline: now.add(const Duration(hours: 3)),
          effortMinutes: 30,
        ),
        _candidate(
          id: 'b',
          deadline: now.add(const Duration(days: 2)),
          effortMinutes: 30,
        ),
      ];
      final first = builder.build(
        ranking: _ranking(now, candidates),
        accountScopeId: 'account',
        referenceDate: now,
      );
      final second = builder.build(
        ranking: _ranking(now, candidates.reversed.toList()),
        accountScopeId: 'account',
        referenceDate: now,
      );
      expect(
        first.suggestions.map((item) => item.suggestionId),
        second.suggestions.map((item) => item.suggestionId),
      );
      expect(
        first.suggestions.map((item) => item.primaryCandidateId),
        second.suggestions.map((item) => item.primaryCandidateId),
      );
    });

    test('roles and household labels cannot change selection', () {
      final results = [
        'child',
        'dependent-adult',
        'grand-parent',
        'nanny',
        'colleague',
        'unrelated',
        'household-a',
        'residence-b',
      ].map((subject) {
        return builder
            .build(
              ranking: _ranking(
                now,
                [
                  _candidate(
                    id: 'same',
                    subjectEntityId: subject,
                    deadline: now.add(const Duration(hours: 3)),
                    effortMinutes: 30,
                  ),
                ],
              ),
              accountScopeId: 'account',
              referenceDate: now,
            )
            .suggestions
            .single
            .suggestionType;
      }).toSet();
      expect(results, {PrioritySuggestionType.actSoon});
    });

    test('suggestion model and diagnostics contain no private content', () {
      final result = builder.build(
        ranking: _ranking(
          now,
          [
            _candidate(
              id: 'technical-id',
              accountScopeId: 'private-account-name',
              deadline: now.add(const Duration(hours: 2)),
              effortMinutes: 30,
            ),
          ],
        ),
        accountScopeId: 'private-account-name',
        referenceDate: now,
      );
      final json = jsonEncode(result.suggestions.single.toJson());
      expect(json, isNot(contains('private-account-name')));
      expect(json, isNot(contains('title')));
      expect(json, isNot(contains('address')));
      expect(json, isNot(contains('medical')));
    });
  });

  test('Life Context to ranking to local conversation context stays read-only',
      () {
    final projection = _projection(now);
    final candidates = const PriorityCandidateAdapter().fromProjection(
      projection,
      evaluatedAt: now,
    );
    final ranking = _ranking(now, candidates);
    final suggestions = builder.build(
      ranking: ranking,
      accountScopeId: 'account',
      referenceDate: now,
    );
    final context =
        const PrioritySuggestionConversationContextBuilder().build(suggestions);

    expect(context.items, hasLength(1));
    expect(context.items.single.message, isNotEmpty);
    expect(context.items.single.confirmationRequired, isFalse);
    expect(context.items.length, lessThanOrEqualTo(3));
  });
}

PriorityRanking _ranking(DateTime now, List<PriorityCandidate> candidates) =>
    PriorityEngine().rank(
      candidates,
      evaluatedAt: now,
      expectedAccountScopeId:
          candidates.firstOrNull?.accountScopeId ?? 'account',
    );

PriorityRanking _explicitRanking(
  DateTime now,
  List<PriorityCandidate> ordered, {
  List<PriorityCandidate>? scoreInput,
}) {
  final engine = PriorityEngine();
  final scores = {
    for (final candidate in scoreInput ?? ordered)
      candidate.id: engine.score(
        candidate,
        evaluatedAt: now,
        expectedAccountScopeId: 'account',
      ),
  };
  return PriorityRanking(
    formulaVersion: 2,
    evaluatedAt: now,
    items: [
      for (var index = 0; index < ordered.length; index++)
        PriorityRankedCandidate(
          rank: index + 1,
          candidate: ordered[index],
          score: scores[ordered[index].id]!,
        ),
    ],
    omittedCount: 0,
  );
}

PriorityCandidate _candidate({
  required String id,
  String? sourceId,
  String accountScopeId = 'account',
  PrioritySourceDomain sourceDomain = PrioritySourceDomain.task,
  PriorityCandidateType type = PriorityCandidateType.task,
  DateTime? deadline,
  DateTime? start,
  DateTime? createdAt,
  int? effortMinutes,
  int? travelGoMinutes,
  int? marginMinutes,
  PriorityFlexibility flexibility = PriorityFlexibility.flexible,
  double? explicitUrgency,
  PriorityConsequenceType consequenceType = PriorityConsequenceType.unknown,
  PriorityConsequenceLevel consequenceLevel = PriorityConsequenceLevel.unknown,
  String? subjectEntityId,
}) =>
    PriorityCandidate(
      id: id,
      accountScopeId: accountScopeId,
      sourceDomain: sourceDomain,
      sourceId: sourceId ?? id,
      type: type,
      status: PriorityCandidateStatus.active,
      deadline: deadline,
      temporalStart: start,
      createdAt: createdAt,
      effortMinutes: effortMinutes,
      travelGoMinutes: travelGoMinutes,
      marginMinutes: marginMinutes,
      flexibility: flexibility,
      explicitUrgency: explicitUrgency,
      consequenceType: consequenceType,
      consequenceLevel: consequenceLevel,
      confirmation: LifeContextConfirmation.confirmed,
      freshness: PriorityFreshness.current,
      provenance: PriorityProvenance(
        sourceSnapshotId: 'snapshot',
        sourceItemId: id,
        sourceKind: 'test',
      ),
    );

ProactiveDetectionSignal _conflict(
  DateTime now, {
  List<String> participants = const ['event-a', 'event-b'],
  String detectionId = 'conflict-detection',
  String fingerprint = 'conflict-fingerprint',
}) =>
    ProactiveDetectionSignal(
      detectionId: detectionId,
      accountScopeId: 'account',
      detectorType: ProactiveDetectorType.conflict,
      reasonCode: ProactiveDetectionReason.structuredConflict,
      state: ProactiveDetectionState.eligible,
      confidenceLevel: DetectionConfidenceLevel.certain,
      evidenceLevel: DetectionEvidenceLevel.confirmedStructured,
      evidence: [
        for (final sourceId in participants)
          DetectionEvidence(
            sourceType: DetectionEvidenceSource.confirmedConflictResult,
            domain: LifeContextDomain.event,
            sourceId: sourceId,
            revision: 1,
            freshness: LifeContextFreshness.current,
            availability: LifeContextAvailability.available,
            certainty: DetectionEvidenceLevel.confirmedStructured,
            intervalStart: now.add(const Duration(hours: 1)),
            intervalEnd: now.add(const Duration(hours: 2)),
            confirmed: true,
          ),
      ],
      sourceRevisions: {for (final sourceId in participants) sourceId: 1},
      detectedAt: now,
      validFrom: now,
      validUntil: now.add(const Duration(hours: 1)),
      observedAt: now,
      replacementKey: 'conflict',
      incidentFingerprint: fingerprint,
      interactionDestination: NotificationDestinationType.home,
      policyVersion: 1,
      coverageState: DetectionCoverageKind.complete,
      technicalSeverity: DetectionTechnicalSeverity.important,
    );

LifeContextProjection _projection(DateTime now) {
  final item = LifeContextProjectionItem(
    id: 'event:event:soon',
    domain: LifeContextDomain.event,
    type: 'event',
    facts: [
      LifeContextProjectionFact(
        key: LifeContextProjectionFactKeys.start,
        value: now.add(const Duration(minutes: 30)).toIso8601String(),
        sensitivity: LifeContextSensitivityLevel.publicTechnical,
      ),
      LifeContextProjectionFact(
        key: LifeContextProjectionFactKeys.end,
        value: now.add(const Duration(hours: 1)).toIso8601String(),
        sensitivity: LifeContextSensitivityLevel.publicTechnical,
      ),
    ],
    confirmation: LifeContextConfirmation.confirmed,
    freshness: LifeContextFreshness.current,
    provenance: const LifeContextProjectionProvenance(
      sourceDomain: LifeContextDomain.event,
      sourceId: 'soon',
      sourceSnapshotId: 'snapshot',
      sourceKind: LifeContextSourceKind.eventService,
    ),
    validFrom: now.add(const Duration(minutes: 30)),
    validUntil: now.add(const Duration(hours: 1)),
  );
  return LifeContextProjection(
    projectionId: 'projection',
    sourceSnapshotId: 'snapshot',
    accountScopeId: 'account',
    purpose: LifeContextConsumerPurpose.conversation,
    generatedAt: now,
    state: LifeContextProjectionState.complete,
    budgetRequested: 10,
    budgetUsed: item.budgetCost,
    sections: [
      LifeContextProjectionSection(
        type: LifeContextProjectionSectionType.event,
        availability: LifeContextAvailability.available,
        freshness: LifeContextFreshness.current,
        items: [item],
        budgetLimit: 10,
        budgetUsed: item.budgetCost,
        omittedCount: 0,
        truncated: false,
      ),
    ],
    omittedCount: 0,
    warningCodes: const [],
  );
}
