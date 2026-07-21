import 'dart:collection';

import 'entity_candidate.dart';
import 'entity_types.dart';
import 'life_entity.dart';

final class EntityResolution {
  final EntityResolutionStatus status;
  final LifeEntity? resolvedEntity;
  final List<EntityCandidate> _candidates;
  final EntityResolutionConfidence confidence;
  final List<EntityMatchSignal> _signals;
  final List<String> _reasonCodes;

  EntityResolution._({
    required this.status,
    required this.resolvedEntity,
    required List<EntityCandidate> candidates,
    required this.confidence,
    required List<EntityMatchSignal> signals,
    required List<String> reasonCodes,
  })  : _candidates = List.unmodifiable(candidates),
        _signals = List.unmodifiable(_unique(signals)),
        _reasonCodes = List.unmodifiable(_unique(reasonCodes)) {
    if (status == EntityResolutionStatus.resolved && resolvedEntity == null) {
      throw const EntityDomainException('resolved_requires_entity');
    }
    if (status != EntityResolutionStatus.resolved && resolvedEntity != null) {
      throw const EntityDomainException('unresolved_cannot_contain_entity');
    }
    if (status == EntityResolutionStatus.ambiguous && _candidates.length < 2) {
      throw const EntityDomainException('ambiguous_requires_candidates');
    }
    if (status == EntityResolutionStatus.invalid && _reasonCodes.isEmpty) {
      throw const EntityDomainException('invalid_requires_reason');
    }
    if (status != EntityResolutionStatus.resolved &&
        confidence != EntityResolutionConfidence.insufficient) {
      throw const EntityDomainException(
          'unresolved_confidence_must_be_insufficient');
    }
  }

  factory EntityResolution.resolved({
    required LifeEntity entity,
    required EntityResolutionConfidence confidence,
    required List<EntityMatchSignal> signals,
    required String reasonCode,
  }) {
    if (confidence == EntityResolutionConfidence.insufficient) {
      throw const EntityDomainException(
          'resolved_requires_sufficient_confidence');
    }
    return EntityResolution._(
      status: EntityResolutionStatus.resolved,
      resolvedEntity: entity,
      candidates: [EntityCandidate(entity: entity)],
      confidence: confidence,
      signals: signals,
      reasonCodes: [reasonCode],
    );
  }

  factory EntityResolution.ambiguous({
    required List<EntityCandidate> candidates,
    required List<EntityMatchSignal> signals,
    required String reasonCode,
  }) =>
      EntityResolution._(
        status: EntityResolutionStatus.ambiguous,
        resolvedEntity: null,
        candidates: candidates,
        confidence: EntityResolutionConfidence.insufficient,
        signals: signals,
        reasonCodes: [reasonCode],
      );

  factory EntityResolution.notFound({
    List<EntityMatchSignal> signals = const [],
    required String reasonCode,
  }) =>
      EntityResolution._(
        status: EntityResolutionStatus.notFound,
        resolvedEntity: null,
        candidates: const [],
        confidence: EntityResolutionConfidence.insufficient,
        signals: signals,
        reasonCodes: [reasonCode],
      );

  factory EntityResolution.needsConfirmation({
    required List<EntityCandidate> candidates,
    required List<EntityMatchSignal> signals,
    required String reasonCode,
  }) =>
      EntityResolution._(
        status: EntityResolutionStatus.needsConfirmation,
        resolvedEntity: null,
        candidates: candidates,
        confidence: EntityResolutionConfidence.insufficient,
        signals: signals,
        reasonCodes: [reasonCode],
      );

  factory EntityResolution.invalid({
    required List<EntityMatchSignal> signals,
    required String reasonCode,
  }) =>
      EntityResolution._(
        status: EntityResolutionStatus.invalid,
        resolvedEntity: null,
        candidates: const [],
        confidence: EntityResolutionConfidence.insufficient,
        signals: signals,
        reasonCodes: [reasonCode],
      );

  List<EntityCandidate> get candidates => UnmodifiableListView(_candidates);
  List<EntityMatchSignal> get signals => UnmodifiableListView(_signals);
  List<String> get reasonCodes => UnmodifiableListView(_reasonCodes);
}

List<T> _unique<T>(Iterable<T> values) =>
    values.toSet().toList(growable: false);
