import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_id_generator.dart';
import 'package:moms_ai/models/conversation_models.dart';
import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/models/life_context/life_context_domains.dart';
import 'package:moms_ai/models/life_context/life_context_graph.dart';
import 'package:moms_ai/models/life_context/life_context_projection.dart';
import 'package:moms_ai/models/reasoning/reasoning_assessment.dart';
import 'package:moms_ai/models/reasoning/reasoning_input.dart';
import 'package:moms_ai/models/reasoning/reasoning_result.dart';
import 'package:moms_ai/services/reasoning/reasoning_application_service.dart';
import 'package:moms_ai/services/reasoning/reasoning_engine.dart';

void main() {
  final now = DateTime.utc(2026, 8, 5, 8);

  test('task, appointment and routine make cross-domain context ready',
      () async {
    final result = await _evaluate(
      now,
      projection: _projection(now, sections: [
        _section(LifeContextProjectionSectionType.task, 'Papiers urgents'),
        _section(LifeContextProjectionSectionType.event, 'Dentiste 15h'),
        _section(LifeContextProjectionSectionType.routine, 'École 16h30'),
      ]),
    );

    expect(
      result.assessment.outcome,
      ReasoningAssessmentOutcome.readyForCrossDomainReasoning,
    );
    final serialized = result.observations.toJson().toString();
    expect(serialized, isNot(contains('Papiers urgents')));
    expect(serialized, isNot(contains('Dentiste 15h')));
    expect(serialized, isNot(contains('École 16h30')));
  });

  test('an appointment awaiting confirmation keeps priority', () async {
    final result = await _evaluate(
      now,
      conversationState: ConversationState(
        phase: ConversationPhase.awaitingActionConfirmation,
        currentInstruction: 'Confirmer le rendez-vous',
        pendingAction: PendingConversationAction.eventConfirmation(
          _event(),
        ),
      ),
      projection: _projection(now, sections: [
        _section(LifeContextProjectionSectionType.task, 'Appeler la banque'),
        _section(LifeContextProjectionSectionType.routine, 'Sport'),
      ]),
    );

    expect(
      result.assessment.outcome,
      ReasoningAssessmentOutcome.activeWorkflowTakesPrecedence,
    );
  });

  test('truncated routine context blocks a confident assessment', () async {
    final result = await _evaluate(
      now,
      projection: _projection(
        now,
        partial: true,
        sections: [
          _section(LifeContextProjectionSectionType.task, 'Faire les courses'),
          _section(
            LifeContextProjectionSectionType.routine,
            'Planning incomplet',
            truncated: true,
          ),
        ],
      ),
    );

    expect(
      result.assessment.outcome,
      ReasoningAssessmentOutcome.limitedByContext,
    );
  });

  test('an unavailable context section also forces caution', () async {
    final result = await _evaluate(
      now,
      projection: _projection(
        now,
        partial: true,
        sections: [
          _section(LifeContextProjectionSectionType.event, 'Rendez-vous'),
          _section(
            LifeContextProjectionSectionType.memory,
            'Contexte indisponible',
            availability: LifeContextAvailability.unavailable,
          ),
        ],
      ),
    );

    expect(
      result.assessment.outcome,
      ReasoningAssessmentOutcome.limitedByContext,
    );
  });

  test('one isolated task never becomes a cross-domain conclusion', () async {
    final result = await _evaluate(
      now,
      projection: _projection(now, sections: [
        _section(LifeContextProjectionSectionType.task, 'Une seule tâche'),
      ]),
    );

    expect(
      result.assessment.outcome,
      ReasoningAssessmentOutcome.insufficientCrossDomainEvidence,
    );
    expect(result.assessment.sourceObservationIds, isEmpty);
  });
}

Future<ReasoningResult> _evaluate(
  DateTime now, {
  required LifeContextProjection projection,
  ConversationState conversationState = const ConversationState(),
}) =>
    ReasoningApplicationService(
      loadProjection: (_) async => projection,
      engine: ReasoningEngine(
        idGenerator: const _ScenarioId(),
        clock: () => now,
      ),
    ).evaluate(
      accountScopeId: 'account-a',
      purpose: ReasoningPurpose.organizeAcrossDomains,
      conversationState: conversationState,
      sessionGeneration: 7,
    );

final class _ScenarioId implements EntityIdGenerator {
  const _ScenarioId();

  @override
  String generate() => 'daily-life-scenario';
}

LifeContextProjection _projection(
  DateTime now, {
  required List<LifeContextProjectionSection> sections,
  bool partial = false,
}) =>
    LifeContextProjection(
      projectionId: 'daily-life-projection',
      sourceSnapshotId: 'daily-life-snapshot',
      accountScopeId: 'account-a',
      purpose: LifeContextConsumerPurpose.conversation,
      generatedAt: now,
      state: partial
          ? LifeContextProjectionState.partial
          : LifeContextProjectionState.complete,
      budgetRequested: 40,
      budgetUsed:
          sections.fold(0, (total, section) => total + section.budgetUsed),
      sections: sections,
      omittedCount: partial ? 1 : 0,
      warningCodes: partial ? const ['life_context_partial'] : const [],
    );

LifeContextProjectionSection _section(
  LifeContextProjectionSectionType type,
  String privateValue, {
  bool truncated = false,
  LifeContextAvailability availability = LifeContextAvailability.available,
}) =>
    LifeContextProjectionSection(
      type: type,
      availability: availability,
      freshness: LifeContextFreshness.current,
      items: [
        LifeContextProjectionItem(
          id: '${type.name}-item',
          domain: _domain(type),
          type: type.name,
          facts: [
            LifeContextProjectionFact(
              key: LifeContextProjectionFactKeys.status,
              value: privateValue,
              sensitivity: LifeContextSensitivityLevel.privatePersonal,
            ),
          ],
          confirmation: LifeContextConfirmation.confirmed,
          freshness: LifeContextFreshness.current,
          provenance: LifeContextProjectionProvenance(
            sourceDomain: _domain(type),
            sourceId: '${type.name}-source',
            sourceSnapshotId: 'daily-life-snapshot',
            sourceKind: _sourceKind(type),
          ),
        ),
      ],
      budgetLimit: 10,
      budgetUsed: 2,
      omittedCount: truncated ? 1 : 0,
      truncated: truncated,
      warningCode: truncated ? 'projection_truncated' : null,
    );

LifeContextDomain _domain(LifeContextProjectionSectionType type) =>
    switch (type) {
      LifeContextProjectionSectionType.event => LifeContextDomain.event,
      LifeContextProjectionSectionType.task => LifeContextDomain.task,
      LifeContextProjectionSectionType.routine => LifeContextDomain.routine,
      LifeContextProjectionSectionType.memory => LifeContextDomain.memory,
      _ => LifeContextDomain.human,
    };

LifeContextSourceKind _sourceKind(LifeContextProjectionSectionType type) =>
    switch (type) {
      LifeContextProjectionSectionType.event =>
        LifeContextSourceKind.eventService,
      LifeContextProjectionSectionType.task =>
        LifeContextSourceKind.taskService,
      LifeContextProjectionSectionType.routine =>
        LifeContextSourceKind.legacyProfileRoutine,
      LifeContextProjectionSectionType.memory =>
        LifeContextSourceKind.memoryFirestore,
      _ => LifeContextSourceKind.humanModelLocal,
    };

EventModel _event() => EventModel(
      title: 'Rendez-vous',
      date: '2026-08-05',
      time: '15:00',
      endTime: '16:00',
      durationMinutes: 60,
      travelMinutes: 0,
      category: 'Personnel',
      notes: '',
      createdAt: DateTime.utc(2026, 8, 5),
      startDateTimeIso: '2026-08-05T15:00:00',
      endDateTimeIso: '2026-08-05T16:00:00',
    );
