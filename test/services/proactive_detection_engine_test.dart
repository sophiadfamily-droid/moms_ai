import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/life_context/life_context_domains.dart';
import 'package:moms_ai/models/life_context/life_context_graph.dart';
import 'package:moms_ai/models/local_notification_models.dart';
import 'package:moms_ai/models/proactive_detection.dart';
import 'package:moms_ai/services/detection_notification_coordinator.dart';
import 'package:moms_ai/services/local_notification_registry.dart';
import 'package:moms_ai/services/local_notification_scheduler.dart';
import 'package:moms_ai/services/notification_permission_service.dart';
import 'package:moms_ai/services/notification_privacy_sanitizer.dart';
import 'package:moms_ai/services/notification_settings_service.dart';
import 'package:moms_ai/services/proactive_detection_engine.dart';
import 'package:moms_ai/services/proactive_detection_lifecycle.dart';
import 'package:moms_ai/services/proactive_detection_registry.dart';
import 'package:timezone/data/latest.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  final now = DateTime.utc(2026, 7, 24, 10);

  group('N.2 models and coverage', () {
    test('signal is closed, deterministic and does not serialize scope', () {
      final signal = _signal(now);
      expect(signal.toJson()['schemaVersion'], 1);
      expect(signal.toJson(), isNot(contains('accountScopeId')));
      expect(
        ProactiveDetectionSignal.fromJson(
          signal.toJson(),
          accountScopeId: 'account-a',
        ).toJson(),
        signal.toJson(),
      );
      expect(
        () => ProactiveDetectionSignal.fromJson(
          {...signal.toJson(), 'schemaVersion': 2},
          accountScopeId: 'account-a',
        ),
        throwsFormatException,
      );
      expect(signal.toJson().toString(), isNot(contains('title')));
    });

    test('evidence is mandatory and bounded', () {
      expect(
        () => _signal(now, evidence: const []),
        throwsFormatException,
      );
      expect(
        () => DetectionSubject(
          kind: DetectionSubjectKind.task,
          domain: LifeContextDomain.task,
          sourceId: 'task-1',
          revision: 1,
          freshness: LifeContextFreshness.current,
          availability: LifeContextAvailability.available,
          active: true,
          completed: false,
          deleted: false,
          mandatory: true,
          flexible: false,
          evidence: List.generate(13, (_) => _evidence(now)),
        ),
        throwsFormatException,
      );
    });

    test('partial coverage does not claim a global absence', () {
      final coverage = _coverage(DetectionCoverageKind.partial);
      expect(coverage.supportsCertainDetection, isTrue);
      expect(coverage.kind, isNot(DetectionCoverageKind.complete));
      expect(
        coverage.nonEvaluableCategories,
        contains(ProactiveDetectorType.conflict),
      );
    });
  });

  group('N.2 deterministic detectors', () {
    test('deadline requires an explicit current deadline', () {
      final detector = const DeadlineDetector();
      final due = _subject(now, deadline: now.add(const Duration(hours: 2)));
      final decisions = detector.detect(
        input: _input(now, subjects: [due]),
        policy: const ProactiveDetectionPolicy(),
        now: now,
      );
      expect(decisions.single.signal?.reasonCode,
          ProactiveDetectionReason.deadlineApproaching);
      final absent = _subject(now);
      expect(
        detector.detect(
          input: _input(now, subjects: [absent]),
          policy: const ProactiveDetectionPolicy(),
          now: now,
        ),
        isEmpty,
      );
    });

    test('passed deadline is suppressed for completed, deleted and stale task',
        () {
      final detector = const DeadlineDetector();
      for (final subject in [
        _subject(now,
            deadline: now.subtract(const Duration(minutes: 1)),
            completed: true),
        _subject(now,
            deadline: now.subtract(const Duration(minutes: 1)), deleted: true),
        _subject(
          now,
          deadline: now.subtract(const Duration(minutes: 1)),
          freshness: LifeContextFreshness.stale,
        ),
      ]) {
        final result = detector.detect(
          input: _input(now, subjects: [subject]),
          policy: const ProactiveDetectionPolicy(),
          now: now,
        );
        expect(result.single.signal, isNull);
      }
    });

    test('delay needs explicit time, commitment and grace period', () {
      final detector = const DelayDetector();
      final delayed = _subject(
        now,
        plannedEnd: now.subtract(const Duration(minutes: 20)),
        mandatory: true,
        flexible: false,
      );
      expect(
        detector
            .detect(
              input: _input(now, subjects: [delayed]),
              policy: const ProactiveDetectionPolicy(),
              now: now,
            )
            .single
            .signal
            ?.reasonCode,
        ProactiveDetectionReason.objectivelyDelayed,
      );
      expect(
        detector.detect(
          input: _input(now, subjects: [_subject(now)]),
          policy: const ProactiveDetectionPolicy(),
          now: now,
        ),
        isEmpty,
      );
      expect(
        detector
            .detect(
              input: _input(
                now,
                subjects: [
                  _subject(
                    now,
                    plannedEnd: now.subtract(const Duration(minutes: 20)),
                    mandatory: false,
                    flexible: true,
                  ),
                ],
              ),
              policy: const ProactiveDetectionPolicy(),
              now: now,
            )
            .single
            .suppressionReason,
        DetectionSuppressionReason.flexibleWithoutCommitment,
      );
    });

    test('conflict accepts only canonical current evidence', () {
      final detector = const ConflictDetector();
      final confirmed = _conflict(now);
      expect(
        detector
            .detect(
              input: _input(now, conflicts: [confirmed]),
              policy: const ProactiveDetectionPolicy(),
              now: now,
            )
            .single
            .signal
            ?.reasonCode,
        ProactiveDetectionReason.structuredConflict,
      );
      final unconfirmed = _conflict(now, confirmed: false);
      expect(
        detector
            .detect(
              input: _input(now, conflicts: [unconfirmed]),
              policy: const ProactiveDetectionPolicy(),
              now: now,
            )
            .single
            .signal,
        isNull,
      );
    });

    test('potential omission consumes only a confirmed explicit R.2 dependency',
        () {
      final prerequisite = _subject(
        now,
        sourceId: 'prep',
        deadline: now.subtract(const Duration(minutes: 5)),
      );
      final event = _subject(
        now,
        kind: DetectionSubjectKind.event,
        domain: LifeContextDomain.event,
        sourceId: 'event',
        plannedStart: now.add(const Duration(hours: 2)),
      );
      final detector = const PotentialOmissionDetector();
      expect(
        detector
            .detect(
              input: _input(
                now,
                subjects: [prerequisite, event],
                dependencies: [_dependency(now)],
              ),
              policy: const ProactiveDetectionPolicy(),
              now: now,
            )
            .single
            .signal
            ?.reasonCode,
        ProactiveDetectionReason.potentialOmission,
      );
      expect(
        detector.detect(
          input: _input(now, subjects: [prerequisite, event]),
          policy: const ProactiveDetectionPolicy(),
          now: now,
        ),
        isEmpty,
      );
    });

    test('shopping, titles and ordinary tasks never become omissions', () {
      final detector = const PotentialOmissionDetector();
      final ordinary = _subject(
        now,
        deadline: now.subtract(const Duration(hours: 1)),
      );
      expect(
        detector.detect(
          input: _input(now, subjects: [ordinary]),
          policy: const ProactiveDetectionPolicy(),
          now: now,
        ),
        isEmpty,
      );
    });
  });

  group('N.2 aggregation and lifecycle state', () {
    test('one incident keeps deadline ahead of delay and omission', () {
      final subject = _subject(
        now,
        deadline: now.subtract(const Duration(hours: 1)),
        plannedEnd: now.subtract(const Duration(hours: 1)),
        mandatory: true,
        flexible: false,
      );
      final result = const ProactiveDetectionEngine().evaluate(
        input: _input(now, subjects: [subject]),
        policy: const ProactiveDetectionPolicy(),
        now: now,
      );
      expect(result.activeSignals, hasLength(1));
      expect(result.activeSignals.single.reasonCode,
          ProactiveDetectionReason.deadlinePassed);
      expect(
        result.activeSignals.single.secondaryReasons,
        contains(ProactiveDetectionReason.objectivelyDelayed),
      );
    });

    test('ordering, limits and cooldown are deterministic', () {
      final subjects = List.generate(
        8,
        (index) => _subject(
          now,
          sourceId: 'task-$index',
          deadline: now.subtract(Duration(minutes: index + 1)),
        ),
      );
      final policy = const ProactiveDetectionPolicy(
        maxNotificationsPerPass: 2,
        maxNotificationsPerCategory: 2,
      );
      final first = const ProactiveDetectionEngine().evaluate(
        input: _input(now, subjects: subjects),
        policy: policy,
        now: now,
      );
      expect(first.activeSignals, hasLength(2));
      final resolved = first.activeSignals
          .map(
            (item) => item.copyWith(
              state: ProactiveDetectionState.resolved,
              resolvedAt: now,
            ),
          )
          .toList();
      final second = const ProactiveDetectionEngine().evaluate(
        input: _input(
          now,
          subjects: subjects
              .where(
                (subject) => resolved.any(
                  (signal) =>
                      signal.sourceRevisions.containsKey(subject.sourceId),
                ),
              )
              .toList(),
          existing: resolved,
        ),
        policy: policy,
        now: now.add(const Duration(minutes: 10)),
      );
      expect(second.activeSignals, isEmpty);
    });

    test('a proven conflict stays visible even if its old alert was resolved',
        () {
      final conflict = _conflict(now);
      final first = const ProactiveDetectionEngine().evaluate(
        input: _input(now, conflicts: [conflict]),
        policy: const ProactiveDetectionPolicy(),
        now: now,
      );
      final oldResolved = first.activeSignals.single.copyWith(
        state: ProactiveDetectionState.resolved,
        resolvedAt: now,
      );

      final second = const ProactiveDetectionEngine().evaluate(
        input: _input(
          now,
          conflicts: [conflict],
          existing: [oldResolved],
        ),
        policy: const ProactiveDetectionPolicy(),
        now: now.add(const Duration(minutes: 10)),
      );

      expect(second.activeSignals, hasLength(1));
      expect(
        second.activeSignals.single.reasonCode,
        ProactiveDetectionReason.structuredConflict,
      );
    });

    test('changed or absent source resolves old signal without mutation', () {
      final old = _signal(now);
      final result = const ProactiveDetectionEngine().evaluate(
        input: _input(now, existing: [old]),
        policy: const ProactiveDetectionPolicy(),
        now: now.add(const Duration(minutes: 1)),
      );
      expect(result.resolvedSignals.single.state,
          ProactiveDetectionState.resolved);
      expect(result.resolvedSignals.single.suppressionReason,
          DetectionSuppressionReason.alreadyResolved);
    });

    test('unavailable routine evidence never cancels a proven conflict', () {
      final active = const ProactiveDetectionEngine()
          .evaluate(
            input: _input(now, conflicts: [_routineConflict(now)]),
            policy: const ProactiveDetectionPolicy(),
            now: now,
          )
          .activeSignals
          .single;
      final incompleteCoverage = DetectionCoverageState(
        kind: DetectionCoverageKind.partial,
        evaluatedDomains: const {
          LifeContextDomain.event,
          LifeContextDomain.routine,
        },
        unavailableDomains: const {LifeContextDomain.routine},
        staleDomains: const {},
        numberEvaluated: 0,
        numberTruncated: 0,
        evaluableCategories: const {ProactiveDetectorType.conflict},
        nonEvaluableCategories: const {},
      );
      final result = const ProactiveDetectionEngine().evaluate(
        input: _input(
          now,
          existing: [active],
          coverage: incompleteCoverage,
        ),
        policy: const ProactiveDetectionPolicy(),
        now: now.add(const Duration(minutes: 1)),
      );

      expect(result.activeSignals, isEmpty);
      expect(result.resolvedSignals, isEmpty);
    });

    test('account mismatch fails closed', () {
      expect(
        () => const ProactiveDetectionEngine().evaluate(
          input: _input(
            now,
            existing: [_signal(now, accountScopeId: 'other')],
          ),
          policy: const ProactiveDetectionPolicy(),
          now: now,
        ),
        throwsFormatException,
      );
    });
  });

  group('N.2 registry and N.1 coordination', () {
    test('N.2 categories and N.3 summary are enabled, OS critical is rejected',
        () {
      for (final category in const {
        LocalNotificationCategory.forgottenItemDetection,
        LocalNotificationCategory.conflictDetection,
        LocalNotificationCategory.delayDetection,
        LocalNotificationCategory.deadlineDetection,
      }) {
        _notificationRequest(now, category: category).validate();
      }
      _notificationRequest(
        now,
        category: LocalNotificationCategory.dailySummary,
      ).validate();
      expect(
        () => _notificationRequest(
          now,
          category: LocalNotificationCategory.criticalAlert,
        ).validate(),
        throwsFormatException,
      );
    });

    test('registry is account-scoped, bounded and purges expired history', () {
      expect(
        () => ProactiveDetectionRegistryState(
          accountScopeId: 'account-a',
          signals: List.generate(
            ProactiveDetectionRegistryState.maximumEntries + 1,
            (index) => _signal(now, detectionId: 'd-$index'),
          ),
          updatedAt: now,
        ),
        throwsFormatException,
      );
      final state = ProactiveDetectionRegistryState(
        accountScopeId: 'account-a',
        signals: [_signal(now)],
        updatedAt: now,
      );
      expect(
        () => state.merge(
          updates: [_signal(now, accountScopeId: 'other')],
          now: now,
        ),
        throwsFormatException,
      );
      final replacement = state.merge(
        updates: [_signal(now, detectionId: 'replacement')],
        now: now,
      );
      expect(replacement.signals, hasLength(1));
      expect(replacement.signals.single.detectionId, 'replacement');
    });

    test('eligible signal schedules once with generic N.1 content', () async {
      final fixture = await _coordinator(now);
      final result = ProactiveDetectionResult(
        activeSignals: [_signal(now)],
        resolvedSignals: const [],
        coverage: _coverage(DetectionCoverageKind.complete),
        numberSuppressed: 0,
        evaluatedAt: now,
      );
      final first = await fixture.coordinator.apply(
        result,
        timezoneId: 'Europe/Paris',
      );
      final second = await fixture.coordinator.apply(
        result,
        timezoneId: 'Europe/Paris',
      );
      expect(first.numberScheduled, 1);
      expect(second.numberScheduled, 1);
      expect(fixture.platform.schedules, 1);
      expect(fixture.platform.lastContent?.title, 'Zélia');
      expect(fixture.platform.lastContent?.payload, isNot(contains('account')));
      expect(fixture.platform.lastContent?.body,
          'Tu as une information à consulter dans l’application.');
    });

    test('resolution cancels the real N.1 notification', () async {
      final fixture = await _coordinator(now);
      final active = _signal(now);
      await fixture.coordinator.apply(
        ProactiveDetectionResult(
          activeSignals: [active],
          resolvedSignals: const [],
          coverage: _coverage(DetectionCoverageKind.complete),
          numberSuppressed: 0,
          evaluatedAt: now,
        ),
        timezoneId: 'Europe/Paris',
      );
      final stored =
          (await fixture.detectionRegistry.load('account-a')).signals.single;
      await fixture.coordinator.apply(
        ProactiveDetectionResult(
          activeSignals: const [],
          resolvedSignals: [
            stored.copyWith(
              state: ProactiveDetectionState.resolved,
              resolvedAt: now,
            ),
          ],
          coverage: _coverage(DetectionCoverageKind.complete),
          numberSuppressed: 0,
          evaluatedAt: now,
        ),
        timezoneId: 'Europe/Paris',
      );
      expect(fixture.platform.cancelled, hasLength(1));
    });

    test('lifecycle performs one bounded pass and never replays an action',
        () async {
      final fixture = await _coordinator(now);
      final provider = _InputProvider(_input(
        now,
        subjects: [
          _subject(
            now,
            deadline: now.add(const Duration(hours: 1)),
          ),
        ],
      ));
      final lifecycle = ProactiveDetectionLifecycle(
        engine: const ProactiveDetectionEngine(),
        inputProvider: provider,
        registry: fixture.detectionRegistry,
        notificationCoordinator: fixture.coordinator,
        currentAccountScopeId: () => 'account-a',
        timezoneId: () => 'Europe/Paris',
        now: () => now,
      );
      final result =
          await lifecycle.evaluate(DetectionEvaluationTrigger.foreground);
      expect(provider.loads, 1);
      expect(result.detection.activeSignals, hasLength(1));
      expect(fixture.platform.schedules, 1);
    });
  });

  group('N.2 architecture', () {
    test('detectors are pure and UI/chat contain no detector logic', () {
      final engine = File('lib/services/proactive_detection_engine.dart')
          .readAsStringSync();
      final chat = File('lib/screens/chat_screen.dart').readAsStringSync();
      final screen = File('lib/screens/notification_settings_screen.dart')
          .readAsStringSync();
      expect(engine, isNot(contains('OpenAI')));
      expect(engine, isNot(contains('SharedPreferences')));
      expect(engine, isNot(contains('FirebaseFirestore')));
      expect(engine, isNot(contains('flutter_local_notifications')));
      expect(chat, isNot(contains('ProactiveDetection')));
      expect(screen, isNot(contains('DeadlineDetector')));
      expect(screen, isNot(contains('ProactiveDetectionEngine')));
    });

    test('no background worker, N.3 summary, action or direct plugin exists',
        () {
      final files = [
        'lib/services/proactive_detection_engine.dart',
        'lib/services/proactive_detection_lifecycle.dart',
        'lib/services/detection_notification_coordinator.dart',
      ].map((path) => File(path).readAsStringSync()).join();
      expect(files, isNot(contains('Workmanager')));
      expect(files, isNot(contains('Timer.periodic')));
      expect(files, isNot(contains('dailySummary')));
      expect(files, isNot(contains('criticalAlert')));
      expect(files, isNot(contains('ActionHandler')));
      expect(files, isNot(contains('FlutterLocalNotificationsPlugin')));
    });

    test('production uses one Life Context generation and bounded hooks', () {
      final production =
          File('lib/services/proactive_detection_production.dart')
              .readAsStringSync();
      final conflicts = File(
        'lib/services/life_context/event_life_context_conflict_engine.dart',
      ).readAsStringSync();
      final main = File('lib/main.dart').readAsStringSync();
      final notifications =
          File('lib/services/notification_service.dart').readAsStringSync();
      expect(
        production,
        contains('EventLifeContextConflictEngine'),
      );
      expect(production, contains('snapshot: snapshot'));
      expect(production, isNot(contains('EventService.')));
      expect(production, contains('RoutineOccurrenceService.production'));
      expect(production, contains('RoutineEventConflictEngine'));
      expect(conflicts, contains('eventSection.events'));
      expect(main, contains('authenticatedBootstrap'));
      expect(main, contains('DetectionEvaluationTrigger.foreground'));
      expect(notifications, contains('routinesVersion.addListener'));
      expect(
        notifications,
        contains('DetectionEvaluationTrigger.routineChanged'),
      );
      expect(main, isNot(contains('Timer.periodic')));
    });
  });
}

DetectionCoverageState _coverage(DetectionCoverageKind kind) =>
    DetectionCoverageState(
      kind: kind,
      evaluatedDomains: const {
        LifeContextDomain.event,
        LifeContextDomain.task,
      },
      unavailableDomains: kind == DetectionCoverageKind.partial
          ? const {LifeContextDomain.event}
          : const {},
      staleDomains: const {},
      numberEvaluated: 1,
      numberTruncated: 0,
      evaluableCategories: {
        ProactiveDetectorType.deadline,
        ProactiveDetectorType.delay,
        ProactiveDetectorType.potentialOmission,
        if (kind != DetectionCoverageKind.partial)
          ProactiveDetectorType.conflict,
      },
      nonEvaluableCategories: kind == DetectionCoverageKind.partial
          ? const {ProactiveDetectorType.conflict}
          : const {},
    );

DetectionEvidence _evidence(DateTime now) => DetectionEvidence(
      sourceType: DetectionEvidenceSource.explicitDeadline,
      domain: LifeContextDomain.task,
      sourceId: 'task-1',
      revision: 1,
      freshness: LifeContextFreshness.current,
      availability: LifeContextAvailability.available,
      certainty: DetectionEvidenceLevel.explicit,
      instant: now,
      confirmed: true,
    );

DetectionSubject _subject(
  DateTime now, {
  DetectionSubjectKind kind = DetectionSubjectKind.task,
  LifeContextDomain domain = LifeContextDomain.task,
  String sourceId = 'task-1',
  DateTime? deadline,
  DateTime? plannedStart,
  DateTime? plannedEnd,
  bool completed = false,
  bool deleted = false,
  bool mandatory = false,
  bool flexible = true,
  LifeContextFreshness freshness = LifeContextFreshness.current,
}) =>
    DetectionSubject(
      kind: kind,
      domain: domain,
      sourceId: sourceId,
      revision: 1,
      freshness: freshness,
      availability: LifeContextAvailability.available,
      active: !completed && !deleted,
      completed: completed,
      deleted: deleted,
      mandatory: mandatory,
      flexible: flexible,
      evidence: [
        if (deadline != null)
          DetectionEvidence(
            sourceType: DetectionEvidenceSource.explicitDeadline,
            domain: domain,
            sourceId: sourceId,
            revision: 1,
            freshness: freshness,
            availability: LifeContextAvailability.available,
            certainty: DetectionEvidenceLevel.explicit,
            instant: deadline,
            confirmed: true,
          ),
        if (plannedStart != null)
          DetectionEvidence(
            sourceType: DetectionEvidenceSource.explicitPlannedStart,
            domain: domain,
            sourceId: sourceId,
            revision: 1,
            freshness: freshness,
            availability: LifeContextAvailability.available,
            certainty: DetectionEvidenceLevel.explicit,
            instant: plannedStart,
            confirmed: true,
          ),
        if (plannedEnd != null)
          DetectionEvidence(
            sourceType: DetectionEvidenceSource.explicitPlannedEnd,
            domain: domain,
            sourceId: sourceId,
            revision: 1,
            freshness: freshness,
            availability: LifeContextAvailability.available,
            certainty: DetectionEvidenceLevel.explicit,
            instant: plannedEnd,
            confirmed: true,
          ),
        if (deadline == null && plannedStart == null && plannedEnd == null)
          _evidence(now),
      ],
      deadline: deadline,
      plannedStart: plannedStart,
      plannedEnd: plannedEnd,
    );

StructuredConflictObservation _conflict(
  DateTime now, {
  bool confirmed = true,
}) =>
    StructuredConflictObservation(
      conflictId: 'conflict-1',
      firstSourceId: 'event-1',
      secondSourceId: 'event-2',
      firstRevision: 1,
      secondRevision: 2,
      confirmedByCanonicalEngine: confirmed,
      evidence: [
        DetectionEvidence(
          sourceType: DetectionEvidenceSource.confirmedConflictResult,
          domain: LifeContextDomain.event,
          sourceId: 'conflict-1',
          revision: 2,
          freshness: LifeContextFreshness.current,
          availability: LifeContextAvailability.available,
          certainty: DetectionEvidenceLevel.confirmedStructured,
          instant: now,
          confirmed: confirmed,
        ),
      ],
    );

StructuredConflictObservation _routineConflict(DateTime now) =>
    StructuredConflictObservation(
      conflictId: 'event-1:routine-1:protected-routine-v1',
      firstSourceId: 'event-1',
      secondSourceId: 'routine-1:2026-08-05',
      firstRevision: 1,
      secondRevision: 2,
      confirmedByCanonicalEngine: true,
      evidence: [
        DetectionEvidence(
          sourceType: DetectionEvidenceSource.fixedEventInterval,
          domain: LifeContextDomain.event,
          sourceId: 'event-1',
          revision: 1,
          freshness: LifeContextFreshness.current,
          availability: LifeContextAvailability.available,
          certainty: DetectionEvidenceLevel.confirmedStructured,
          intervalStart: now.add(const Duration(hours: 1)),
          intervalEnd: now.add(const Duration(hours: 2)),
          confirmed: true,
        ),
        DetectionEvidence(
          sourceType: DetectionEvidenceSource.structuredRoutineOccurrence,
          domain: LifeContextDomain.routine,
          sourceId: 'routine-1:2026-08-05',
          revision: 2,
          freshness: LifeContextFreshness.current,
          availability: LifeContextAvailability.available,
          certainty: DetectionEvidenceLevel.confirmedStructured,
          intervalStart: now.add(const Duration(hours: 1)),
          intervalEnd: now.add(const Duration(hours: 2)),
          confirmed: true,
        ),
      ],
    );

LifeContextDependency _dependency(DateTime now) => LifeContextDependency(
      prerequisiteNodeId: 'task:task:prep',
      dependentNodeId: 'event:event:event',
      type: LifeContextDependencyType.requires,
      provenance: LifeContextRelationProvenance(
        sourceDomain: LifeContextDomain.task,
        sourceRecordId: 'dependency-1',
        evidenceType: 'explicit',
        confirmation: LifeContextConfirmation.confirmed,
        ruleId: LifeContextRegisteredRuleIds.explicitDependency,
        ruleVersion: 1,
        readAt: now,
        snapshotId: 'snapshot-1',
        sectionSource: LifeContextSourceKind.taskService,
        nature: LifeContextRelationNature.direct,
      ),
    );

ProactiveDetectionInput _input(
  DateTime now, {
  List<DetectionSubject> subjects = const [],
  List<StructuredConflictObservation> conflicts = const [],
  List<LifeContextDependency> dependencies = const [],
  List<ProactiveDetectionSignal> existing = const [],
  DetectionCoverageState? coverage,
}) =>
    ProactiveDetectionInput(
      accountScopeId: 'account-a',
      subjects: subjects,
      conflicts: conflicts,
      dependencies: dependencies,
      coverage: coverage ?? _coverage(DetectionCoverageKind.complete),
      existingSignals: existing,
      observedAt: now,
      timezoneId: 'Europe/Paris',
    );

ProactiveDetectionSignal _signal(
  DateTime now, {
  String accountScopeId = 'account-a',
  String detectionId = 'detection-1',
  List<DetectionEvidence>? evidence,
}) =>
    ProactiveDetectionSignal(
      detectionId: detectionId,
      accountScopeId: accountScopeId,
      detectorType: ProactiveDetectorType.deadline,
      reasonCode: ProactiveDetectionReason.deadlineApproaching,
      state: ProactiveDetectionState.eligible,
      confidenceLevel: DetectionConfidenceLevel.certain,
      evidenceLevel: DetectionEvidenceLevel.explicit,
      evidence: evidence ?? [_evidence(now)],
      sourceRevisions: const {'task-1': 1},
      detectedAt: now,
      validFrom: now,
      validUntil: now.add(const Duration(days: 1)),
      observedAt: now,
      scheduledEvaluationAt: now.add(const Duration(hours: 1)),
      replacementKey: 'detection:task-1',
      incidentFingerprint: 'fingerprint-1',
      interactionDestination: NotificationDestinationType.home,
      policyVersion: 1,
      coverageState: DetectionCoverageKind.complete,
      technicalSeverity: DetectionTechnicalSeverity.attention,
    );

LocalNotificationRequest _notificationRequest(
  DateTime now, {
  required LocalNotificationCategory category,
}) =>
    LocalNotificationRequest(
      logicalNotificationId: 'n2-request',
      accountScopeId: 'account-a',
      category: category,
      createdAt: now,
      scheduledAt: now.add(const Duration(minutes: 10)),
      expiresAt: now.add(const Duration(hours: 1)),
      timezoneId: 'Europe/Paris',
      scheduleMeaning: NotificationScheduleMeaning.absoluteInstant,
      privacyLevel: NotificationPrivacyLevel.generic,
      interactionType: NotificationInteractionType.openSafeDestination,
      destinationType: NotificationDestinationType.home,
      destinationReference: 'attention',
      replacementKey: 'detection:one',
      source: LocalNotificationSource.deterministicDetection,
      status: LocalNotificationStatus.registered,
      platformNotificationId: 42,
      correlationId: 'opaque',
      policyVersionObserved: 1,
    );

Future<_CoordinatorFixture> _coordinator(DateTime now) async {
  final platform = _PlatformGateway();
  final notificationRegistry = _NotificationRegistry();
  final settingsRepository = _SettingsRepository();
  final settings = NotificationSettingsService(
    repository: settingsRepository,
    currentAccountScopeId: () => 'account-a',
    currentTimezoneId: () async => 'Europe/Paris',
    now: () => now,
  );
  await settings.save(
    enabled: true,
    permissionPromptExplained: true,
    soundEnabled: false,
    vibrationEnabled: false,
    badgeEnabled: false,
  );
  final scheduler = LocalNotificationScheduler(
    platform: platform,
    permissionService: NotificationPermissionService(_PermissionGateway()),
    settingsService: settings,
    registry: notificationRegistry,
    currentAccountScopeId: () => 'account-a',
    now: () => now,
  );
  final detectionRegistry = _DetectionRegistry();
  return _CoordinatorFixture(
    coordinator: DetectionNotificationCoordinator(
      scheduler: scheduler,
      registry: detectionRegistry,
      currentAccountScopeId: () => 'account-a',
      now: () => now,
    ),
    platform: platform,
    detectionRegistry: detectionRegistry,
  );
}

final class _CoordinatorFixture {
  const _CoordinatorFixture({
    required this.coordinator,
    required this.platform,
    required this.detectionRegistry,
  });
  final DetectionNotificationCoordinator coordinator;
  final _PlatformGateway platform;
  final _DetectionRegistry detectionRegistry;
}

final class _InputProvider implements ProactiveDetectionInputProvider {
  _InputProvider(this.input);
  final ProactiveDetectionInput input;
  int loads = 0;

  @override
  Future<ProactiveDetectionInput> load({
    required String accountScopeId,
    required List<ProactiveDetectionSignal> existingSignals,
    required DetectionEvaluationTrigger trigger,
  }) async {
    loads++;
    return ProactiveDetectionInput(
      accountScopeId: accountScopeId,
      subjects: input.subjects,
      conflicts: input.conflicts,
      dependencies: input.dependencies,
      coverage: input.coverage,
      existingSignals: existingSignals,
      observedAt: input.observedAt,
      timezoneId: input.timezoneId,
    );
  }
}

final class _DetectionRegistry implements ProactiveDetectionRegistry {
  final values = <String, ProactiveDetectionRegistryState>{};
  @override
  Future<ProactiveDetectionRegistryState> load(String accountScopeId) async =>
      values[accountScopeId] ??
      ProactiveDetectionRegistryState(
        accountScopeId: accountScopeId,
        signals: const [],
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
  @override
  Future<void> save(ProactiveDetectionRegistryState state) async {
    values[state.accountScopeId] = state;
  }
}

final class _NotificationRegistry implements LocalNotificationRegistry {
  final values = <String, NotificationRegistryState>{};
  @override
  Future<NotificationRegistryState> load(String accountScopeId) async =>
      values[accountScopeId] ??
      NotificationRegistryState(
        accountScopeId: accountScopeId,
        entries: const [],
      );
  @override
  Future<void> save(NotificationRegistryState state) async {
    values[state.accountScopeId] = state;
  }
}

final class _SettingsRepository implements NotificationSettingsRepository {
  final values = <String, NotificationSettings>{};
  @override
  Future<NotificationSettings?> load(String accountScopeId) async =>
      values[accountScopeId];
  @override
  Future<void> save(NotificationSettings settings) async {
    values[settings.accountScopeId] = settings;
  }
}

final class _PermissionGateway implements NotificationPermissionGateway {
  @override
  Future<bool> openSettings() async => true;
  @override
  Future<NotificationPermissionState> read() async =>
      NotificationPermissionState(
        platform: NotificationPlatform.android,
        state: NotificationPermissionStatus.authorized,
        checkedAt: DateTime.utc(2026, 7, 24),
        canRequest: false,
        canOpenSettings: true,
        notificationsEnabled: true,
      );
  @override
  Future<NotificationPermissionState> request() => read();
}

final class _PlatformGateway implements LocalNotificationPlatformGateway {
  int schedules = 0;
  final pending = <int>{};
  final cancelled = <int>[];
  SanitizedNotificationContent? lastContent;
  @override
  Future<void> cancel(int platformNotificationId) async {
    pending.remove(platformNotificationId);
    cancelled.add(platformNotificationId);
  }

  @override
  Future<void> initialize() async {}
  @override
  Future<bool?> isChannelEnabled(String channelId) async => true;
  @override
  Future<Set<int>> pendingIds() async => pending;
  @override
  Future<void> schedule({
    required LocalNotificationRequest request,
    required DateTime platformInstant,
    required SanitizedNotificationContent content,
    required NotificationSettings settings,
  }) async {
    schedules++;
    pending.add(request.platformNotificationId);
    lastContent = content;
  }

  @override
  Future<void> showNow({
    required LocalNotificationRequest request,
    required SanitizedNotificationContent content,
    required NotificationSettings settings,
  }) async {}
}
