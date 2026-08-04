import '../../models/life_context/life_context_domains.dart';
import '../../models/life_context/life_context_projection.dart';
import '../../models/reasoning/reasoning_input.dart';
import '../../models/reasoning/reasoning_observation.dart';

/// V1-RE.2 derives bounded structural observations from one RE.1 input.
///
/// It never interprets fact values and never returns a recommendation, score,
/// domain mutation, confirmation or user-facing message.
final class ReasoningObservationEngine {
  const ReasoningObservationEngine();

  ReasoningObservationSet observe(ReasoningInput input) {
    final projection = input.lifeContext;
    final observations = <ReasoningObservation>[];
    final businessSections = projection.sections
        .where((section) => const {
              LifeContextProjectionSectionType.event,
              LifeContextProjectionSectionType.task,
              LifeContextProjectionSectionType.routine,
              LifeContextProjectionSectionType.memory,
            }.contains(section.type))
        .where((section) => section.items.isNotEmpty)
        .toList();

    if (businessSections.length >= 2) {
      observations.add(
        _observation(
          input: input,
          type: ReasoningObservationType.multiDomainEvidence,
          reliability: input.state == ReasoningInputState.complete
              ? ReasoningObservationReliability.confirmed
              : ReasoningObservationReliability.limited,
          sections: businessSections,
        ),
      );
    }

    if (input.conversation.pendingActionType != null) {
      observations.add(
        _observation(
          input: input,
          type: ReasoningObservationType.activeWorkflow,
          reliability: ReasoningObservationReliability.confirmed,
          sections: projection.sections.take(1).toList(),
        ),
      );
    }

    final limitedSections = projection.sections
        .where(
          (section) =>
              section.truncated ||
              section.warningCode != null ||
              section.sourceWarningCodes.isNotEmpty,
        )
        .toList();
    if (input.state == ReasoningInputState.partial) {
      observations.add(
        _observation(
          input: input,
          type: ReasoningObservationType.limitedContext,
          reliability: ReasoningObservationReliability.limited,
          sections: limitedSections.isEmpty
              ? projection.sections.take(1).toList()
              : limitedSections,
        ),
      );
    }

    for (final section in projection.sections.where(
      (section) => const {
        LifeContextAvailability.unavailable,
        LifeContextAvailability.unsupported,
        LifeContextAvailability.corrupted,
        LifeContextAvailability.accountMismatch,
      }.contains(section.availability),
    )) {
      observations.add(
        _observation(
          input: input,
          type: ReasoningObservationType.unavailableContextSection,
          reliability: ReasoningObservationReliability.limited,
          sections: [section],
          suffix: section.type.name,
        ),
      );
    }

    observations.sort(
      (left, right) => left.observationId.compareTo(right.observationId),
    );
    final hasLimited = observations.any(
      (item) => item.reliability == ReasoningObservationReliability.limited,
    );
    return ReasoningObservationSet(
      inputId: input.inputId,
      accountScopeId: input.accountScopeId,
      generatedAt: input.generatedAt,
      state: observations.isEmpty
          ? ReasoningObservationSetState.empty
          : hasLimited
              ? ReasoningObservationSetState.limited
              : ReasoningObservationSetState.observed,
      observations: observations,
    );
  }

  ReasoningObservation _observation({
    required ReasoningInput input,
    required ReasoningObservationType type,
    required ReasoningObservationReliability reliability,
    required List<LifeContextProjectionSection> sections,
    String? suffix,
  }) {
    final boundedSections = sections.take(7).toList();
    final sectionTypes = boundedSections.map((section) => section.type).toSet();
    final itemIds = boundedSections
        .expand((section) => section.items)
        .map((item) => item.id)
        .toSet()
        .take(20)
        .toList();
    return ReasoningObservation(
      observationId:
          '${input.inputId}:${type.name}${suffix == null ? '' : ':$suffix'}',
      type: type,
      reliability: reliability,
      evidence: ReasoningObservationEvidence(
        sourceProjectionId: input.lifeContext.projectionId,
        sectionTypes: sectionTypes.toList(),
        sourceItemIds: itemIds,
      ),
    );
  }
}
