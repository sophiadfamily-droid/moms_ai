import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/action_autonomy_policy.dart';
import 'package:moms_ai/models/conversation_models.dart';
import 'package:moms_ai/models/life_context/life_context_domains.dart';
import 'package:moms_ai/models/life_context/life_context_graph.dart';
import 'package:moms_ai/models/life_context/life_context_projection.dart';
import 'package:moms_ai/models/reasoning/reasoning_input.dart';
import 'package:moms_ai/models/reasoning/reasoning_observation.dart';
import 'package:moms_ai/services/reasoning/reasoning_observation_engine.dart';

void main() {
  final now = DateTime.utc(2026, 8, 4, 16);

  test('observes multi-domain evidence without copying fact values', () {
    final input = _input(
      now,
      sections: [
        _section(LifeContextProjectionSectionType.task, 'private-task-value'),
        _section(LifeContextProjectionSectionType.event, 'private-event-value'),
      ],
    );
    final first = const ReasoningObservationEngine().observe(input);
    final second = const ReasoningObservationEngine().observe(input);

    expect(first.state, ReasoningObservationSetState.observed);
    expect(first.toJson(), second.toJson());
    expect(first.observations, hasLength(1));
    expect(
      first.observations.single.type,
      ReasoningObservationType.multiDomainEvidence,
    );
    final serialized = first.toJson().toString();
    expect(serialized, isNot(contains('private-task-value')));
    expect(serialized, isNot(contains('private-event-value')));
  });

  test('marks partial and unavailable context with bounded evidence', () {
    final input = _input(
      now,
      state: ReasoningInputState.partial,
      projectionState: LifeContextProjectionState.partial,
      warnings: const ['projection_truncated'],
      sections: [
        _section(
          LifeContextProjectionSectionType.memory,
          'hidden-memory',
          truncated: true,
        ),
        _section(
          LifeContextProjectionSectionType.routine,
          'hidden-routine',
          availability: LifeContextAvailability.unavailable,
        ),
      ],
    );
    final output = const ReasoningObservationEngine().observe(input);

    expect(output.state, ReasoningObservationSetState.limited);
    expect(
      output.observations.map((item) => item.type),
      containsAll([
        ReasoningObservationType.multiDomainEvidence,
        ReasoningObservationType.limitedContext,
        ReasoningObservationType.unavailableContextSection,
      ]),
    );
    expect(
      output.observations.length,
      lessThanOrEqualTo(ReasoningObservationSet.maximumObservations),
    );
  });

  test('returns empty when no cross-domain or workflow observation exists', () {
    final output = const ReasoningObservationEngine().observe(
      _input(
        now,
        sections: [_section(LifeContextProjectionSectionType.task, 'hidden')],
      ),
    );

    expect(output.state, ReasoningObservationSetState.empty);
    expect(output.observations, isEmpty);
  });

  test('observes an active workflow even when context has no facts', () {
    final input = _input(
      now,
      sections: [
        _section(
          LifeContextProjectionSectionType.task,
          'unused',
          includeItem: false,
        ),
      ],
    );
    final activeInput = ReasoningInput(
      inputId: input.inputId,
      accountScopeId: input.accountScopeId,
      purpose: input.purpose,
      generatedAt: input.generatedAt,
      state: input.state,
      conversation: const ReasoningConversationState(
        phase: ConversationPhase.awaitingActionConfirmation,
        hasCurrentInstruction: true,
        pendingActionType: PendingConversationActionType.eventConfirmation,
        pendingActionRisk: ActionRiskLevel.mutation,
        hasCanonicalConfirmation: true,
        sessionGeneration: 1,
      ),
      lifeContext: input.lifeContext,
      warningCodes: input.warningCodes,
    );

    final output = const ReasoningObservationEngine().observe(activeInput);

    expect(output.state, ReasoningObservationSetState.observed);
    expect(
      output.observations.single.type,
      ReasoningObservationType.activeWorkflow,
    );
    expect(
      output.observations.single.evidence.sectionTypes,
      [LifeContextProjectionSectionType.task],
    );
  });
}

ReasoningInput _input(
  DateTime now, {
  required List<LifeContextProjectionSection> sections,
  ReasoningInputState state = ReasoningInputState.complete,
  LifeContextProjectionState projectionState =
      LifeContextProjectionState.complete,
  List<String> warnings = const [],
}) =>
    ReasoningInput(
      inputId: 'input-1',
      accountScopeId: 'account-a',
      purpose: ReasoningPurpose.organizeAcrossDomains,
      generatedAt: now,
      state: state,
      conversation: const ReasoningConversationState(
        phase: ConversationPhase.idle,
        hasCurrentInstruction: false,
        pendingActionType: null,
        pendingActionRisk: null,
        hasCanonicalConfirmation: false,
        sessionGeneration: 0,
      ),
      lifeContext: LifeContextProjection(
        projectionId: 'projection-1',
        sourceSnapshotId: 'snapshot-1',
        accountScopeId: 'account-a',
        purpose: LifeContextConsumerPurpose.conversation,
        generatedAt: now,
        state: projectionState,
        budgetRequested: 40,
        budgetUsed:
            sections.fold(0, (sum, section) => sum + section.budgetUsed),
        sections: sections,
        omittedCount:
            projectionState == LifeContextProjectionState.partial ? 1 : 0,
        warningCodes: warnings,
      ),
      warningCodes: warnings,
    );

LifeContextProjectionSection _section(
  LifeContextProjectionSectionType type,
  String privateValue, {
  bool truncated = false,
  bool includeItem = true,
  LifeContextAvailability availability = LifeContextAvailability.available,
}) =>
    LifeContextProjectionSection(
      type: type,
      availability: availability,
      freshness: LifeContextFreshness.current,
      items: includeItem
          ? [
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
                  sourceSnapshotId: 'snapshot-1',
                  sourceKind: _sourceKind(type),
                ),
              ),
            ]
          : const [],
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
      LifeContextProjectionSectionType.human => LifeContextDomain.human,
      LifeContextProjectionSectionType.identity => LifeContextDomain.identity,
      LifeContextProjectionSectionType.relation => LifeContextDomain.human,
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
      LifeContextProjectionSectionType.human =>
        LifeContextSourceKind.humanModelLocal,
      LifeContextProjectionSectionType.identity =>
        LifeContextSourceKind.identityLinks,
      LifeContextProjectionSectionType.relation =>
        LifeContextSourceKind.humanModelLocal,
    };
