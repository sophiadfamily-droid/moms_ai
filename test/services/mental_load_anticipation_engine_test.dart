import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/life_context/life_context_domains.dart';
import 'package:moms_ai/models/life_context/life_context_graph.dart';
import 'package:moms_ai/models/mental_load_anticipation.dart';
import 'package:moms_ai/models/proactive_detection.dart';
import 'package:moms_ai/services/mental_load_anticipation_engine.dart';
import 'package:moms_ai/services/proactive_detection_engine.dart';

void main() {
  final now = DateTime.utc(2026, 8, 17, 10);

  test('anticipates a confirmed preparation before an upcoming event', () {
    final result = const MentalLoadAnticipationEngine().evaluate(
      input: _input(now),
      policy: const MentalLoadAnticipationPolicy(),
      now: now,
    );

    expect(result, hasLength(1));
    expect(result.single.preparationSourceId, 'prepare-documents');
    expect(result.single.eventSourceId, 'school-registration');
    expect(result.single.priority, MentalLoadAnticipationPriority.urgent);
  });

  test('does not infer a preparation without an explicit dependency', () {
    final result = const MentalLoadAnticipationEngine().evaluate(
      input: _input(now, dependencies: const []),
      policy: const MentalLoadAnticipationPolicy(),
      now: now,
    );

    expect(result, isEmpty);
  });

  test('ignores completed, stale, late or distant evidence', () {
    for (final input in [
      _input(now, completed: true),
      _input(now, freshness: LifeContextFreshness.stale),
      _input(now, deadline: now.add(const Duration(days: 4))),
      _input(now, eventStart: now.add(const Duration(days: 20))),
    ]) {
      expect(
        const MentalLoadAnticipationEngine().evaluate(
          input: input,
          policy: const MentalLoadAnticipationPolicy(),
          now: now,
        ),
        isEmpty,
      );
    }
  });

  test('never returns candidates when coverage is unavailable', () {
    final result = const MentalLoadAnticipationEngine().evaluate(
      input: _input(now, evaluable: false),
      policy: const MentalLoadAnticipationPolicy(),
      now: now,
    );

    expect(result, isEmpty);
  });

  test('the first slice cannot write, notify or execute an action', () {
    final source = File('lib/services/mental_load_anticipation_engine.dart')
        .readAsStringSync();

    expect(source, isNot(contains('FirebaseFirestore')));
    expect(source, isNot(contains('NotificationService')));
    expect(source, isNot(contains('ActionHandler')));
    expect(source, isNot(contains('TaskService')));
    expect(source, isNot(contains('OpenAI')));
  });
}

ProactiveDetectionInput _input(
  DateTime now, {
  bool completed = false,
  bool evaluable = true,
  LifeContextFreshness freshness = LifeContextFreshness.current,
  DateTime? deadline,
  DateTime? eventStart,
  List<LifeContextDependency>? dependencies,
}) {
  final actualDeadline = deadline ?? now.add(const Duration(hours: 20));
  final actualEventStart = eventStart ?? now.add(const Duration(days: 2));
  return ProactiveDetectionInput(
    accountScopeId: 'account-a',
    subjects: [
      _subject(
        kind: DetectionSubjectKind.task,
        domain: LifeContextDomain.task,
        sourceId: 'prepare-documents',
        deadline: actualDeadline,
        completed: completed,
        freshness: freshness,
      ),
      _subject(
        kind: DetectionSubjectKind.event,
        domain: LifeContextDomain.event,
        sourceId: 'school-registration',
        plannedStart: actualEventStart,
        freshness: freshness,
      ),
    ],
    conflicts: const [],
    dependencies: dependencies ?? [_dependency(now)],
    coverage: DetectionCoverageState(
      kind: evaluable
          ? DetectionCoverageKind.complete
          : DetectionCoverageKind.unavailable,
      evaluatedDomains: const {
        LifeContextDomain.task,
        LifeContextDomain.event,
      },
      unavailableDomains: evaluable ? const {} : const {LifeContextDomain.task},
      staleDomains: const {},
      numberEvaluated: 2,
      numberTruncated: 0,
      evaluableCategories: evaluable
          ? const {ProactiveDetectorType.potentialOmission}
          : const {},
      nonEvaluableCategories: evaluable
          ? const {}
          : const {ProactiveDetectorType.potentialOmission},
    ),
    existingSignals: const [],
    observedAt: now,
    timezoneId: 'Europe/Paris',
  );
}

DetectionSubject _subject({
  required DetectionSubjectKind kind,
  required LifeContextDomain domain,
  required String sourceId,
  DateTime? deadline,
  DateTime? plannedStart,
  bool completed = false,
  LifeContextFreshness freshness = LifeContextFreshness.current,
}) =>
    DetectionSubject(
      kind: kind,
      domain: domain,
      sourceId: sourceId,
      revision: 1,
      freshness: freshness,
      availability: LifeContextAvailability.available,
      active: !completed,
      completed: completed,
      deleted: false,
      mandatory: false,
      flexible: true,
      evidence: [
        DetectionEvidence(
          sourceType: deadline != null
              ? DetectionEvidenceSource.explicitDeadline
              : DetectionEvidenceSource.fixedEventInterval,
          domain: domain,
          sourceId: sourceId,
          revision: 1,
          freshness: freshness,
          availability: LifeContextAvailability.available,
          certainty: DetectionEvidenceLevel.explicit,
          instant: deadline ?? plannedStart,
          confirmed: true,
        ),
      ],
      deadline: deadline,
      plannedStart: plannedStart,
    );

LifeContextDependency _dependency(DateTime now) => LifeContextDependency(
      prerequisiteNodeId: 'task:task:prepare-documents',
      dependentNodeId: 'event:event:school-registration',
      type: LifeContextDependencyType.explicitUserDependency,
      provenance: LifeContextRelationProvenance(
        sourceDomain: LifeContextDomain.task,
        sourceRecordId: 'prepare-documents-school-registration',
        evidenceType: 'explicitUserDependency',
        confirmation: LifeContextConfirmation.confirmed,
        ruleId: LifeContextRegisteredRuleIds.explicitDependency,
        ruleVersion: 1,
        readAt: now,
        snapshotId: 'snapshot-a',
        sectionSource: LifeContextSourceKind.taskService,
        nature: LifeContextRelationNature.direct,
      ),
    );
