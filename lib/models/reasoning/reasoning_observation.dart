import 'dart:collection';

import '../life_context/life_context_projection.dart';

enum ReasoningObservationType {
  multiDomainEvidence,
  activeWorkflow,
  limitedContext,
  unavailableContextSection,
}

enum ReasoningObservationReliability { confirmed, limited }

enum ReasoningObservationSetState { empty, observed, limited }

final class ReasoningObservationException implements Exception {
  const ReasoningObservationException(this.code);

  final String code;

  @override
  String toString() => 'ReasoningObservationException($code)';
}

/// Technical evidence only. No fact value or display text may cross RE.2.
final class ReasoningObservationEvidence {
  ReasoningObservationEvidence({
    required this.sourceProjectionId,
    required List<LifeContextProjectionSectionType> sectionTypes,
    required List<String> sourceItemIds,
  })  : sectionTypes = UnmodifiableListView(
          List<LifeContextProjectionSectionType>.of(sectionTypes)
            ..sort((a, b) => a.index.compareTo(b.index)),
        ),
        sourceItemIds = UnmodifiableListView(
          List<String>.of(sourceItemIds)..sort(),
        ) {
    if (sourceProjectionId.trim().isEmpty ||
        this.sectionTypes.isEmpty ||
        this.sectionTypes.toSet().length != this.sectionTypes.length ||
        this.sourceItemIds.length > 20 ||
        this.sourceItemIds.toSet().length != this.sourceItemIds.length ||
        this.sourceItemIds.any((id) => id.trim().isEmpty || id.length > 120)) {
      throw const ReasoningObservationException(
        'invalid_reasoning_observation_evidence',
      );
    }
  }

  final String sourceProjectionId;
  final List<LifeContextProjectionSectionType> sectionTypes;
  final List<String> sourceItemIds;

  Map<String, Object?> toJson() => {
        'sourceProjectionId': sourceProjectionId,
        'sectionTypes': sectionTypes.map((type) => type.name).toList(),
        'sourceItemIds': sourceItemIds,
      };
}

final class ReasoningObservation {
  ReasoningObservation({
    required this.observationId,
    required this.type,
    required this.reliability,
    required this.evidence,
  }) {
    if (observationId.trim().isEmpty || observationId.length > 160) {
      throw const ReasoningObservationException(
        'invalid_reasoning_observation',
      );
    }
  }

  final String observationId;
  final ReasoningObservationType type;
  final ReasoningObservationReliability reliability;
  final ReasoningObservationEvidence evidence;

  String get reasonCode => switch (type) {
        ReasoningObservationType.multiDomainEvidence =>
          'multi_domain_evidence_available',
        ReasoningObservationType.activeWorkflow => 'active_workflow_present',
        ReasoningObservationType.limitedContext => 'context_is_limited',
        ReasoningObservationType.unavailableContextSection =>
          'context_section_unavailable',
      };

  Map<String, Object?> toJson() => {
        'observationId': observationId,
        'type': type.name,
        'reasonCode': reasonCode,
        'reliability': reliability.name,
        'evidence': evidence.toJson(),
      };
}

final class ReasoningObservationSet {
  static const int currentSchemaVersion = 1;
  static const int maximumObservations = 12;

  ReasoningObservationSet({
    this.schemaVersion = currentSchemaVersion,
    required this.inputId,
    required this.accountScopeId,
    required this.generatedAt,
    required this.state,
    required List<ReasoningObservation> observations,
  }) : observations = UnmodifiableListView(observations) {
    if (schemaVersion != currentSchemaVersion ||
        inputId.trim().isEmpty ||
        accountScopeId.trim().isEmpty ||
        observations.length > maximumObservations ||
        observations.map((item) => item.observationId).toSet().length !=
            observations.length ||
        (state == ReasoningObservationSetState.empty) != observations.isEmpty ||
        (state == ReasoningObservationSetState.limited &&
            observations.every(
              (item) =>
                  item.reliability != ReasoningObservationReliability.limited,
            ))) {
      throw const ReasoningObservationException(
        'invalid_reasoning_observation_set',
      );
    }
  }

  final int schemaVersion;
  final String inputId;
  final String accountScopeId;
  final DateTime generatedAt;
  final ReasoningObservationSetState state;
  final List<ReasoningObservation> observations;

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'inputId': inputId,
        'accountScopeId': accountScopeId,
        'generatedAt': generatedAt.toUtc().toIso8601String(),
        'state': state.name,
        'observations': observations.map((item) => item.toJson()).toList(),
      };
}
