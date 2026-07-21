import 'dart:collection';

import '../../core/identity/entity_candidate.dart';
import '../../core/identity/entity_identity.dart';
import '../../core/identity/entity_reference.dart';
import '../../core/identity/entity_resolution.dart';
import '../../core/identity/entity_types.dart';
import '../../core/identity/life_entity.dart';
import '../../repositories/identity/identity_repository.dart';

enum IdentityApplicationStatus {
  resolved,
  ambiguous,
  notFound,
  needsConfirmation,
  invalid,
  repositoryFailure,
}

final class IdentityApplicationException implements Exception {
  final String code;

  const IdentityApplicationException(this.code);

  @override
  String toString() => 'IdentityApplicationException($code)';
}

final class IdentityCandidateEvidence {
  final String entityId;
  final List<EntityRelationSignal> _relationSignals;
  final bool isExplicitConversationTarget;

  IdentityCandidateEvidence({
    required this.entityId,
    List<EntityRelationSignal> relationSignals = const [],
    this.isExplicitConversationTarget = false,
  }) : _relationSignals = List.unmodifiable(relationSignals) {
    if (!EntityIdentity.isValid(entityId)) {
      throw const IdentityApplicationException('invalid_evidence_entity_id');
    }
    final relationStates = <String, bool>{};
    for (final signal in _relationSignals) {
      final key = signal.relationKey.trim();
      final previous = relationStates[key];
      if (previous != null && previous != signal.isVerified) {
        throw const IdentityApplicationException(
          'contradictory_relation_evidence',
        );
      }
      relationStates[key] = signal.isVerified;
    }
  }

  List<EntityRelationSignal> get relationSignals =>
      UnmodifiableListView(_relationSignals);
}

final class IdentityResolutionRequest {
  final IdentityAccountScope scope;
  final EntityReference reference;
  final Map<String, IdentityCandidateEvidence> _relationEvidenceByEntityId;
  final String? explicitConversationTargetEntityId;
  final DateTime? referenceDate;
  final int candidateLimit;

  IdentityResolutionRequest({
    required this.scope,
    required this.reference,
    Map<String, IdentityCandidateEvidence> relationEvidenceByEntityId =
        const {},
    this.explicitConversationTargetEntityId,
    this.referenceDate,
    this.candidateLimit = 20,
  }) : _relationEvidenceByEntityId = Map.unmodifiable(
          Map<String, IdentityCandidateEvidence>.of(
            relationEvidenceByEntityId,
          ),
        ) {
    if (candidateLimit < 1 || candidateLimit > 20) {
      throw const IdentityApplicationException('invalid_candidate_limit');
    }
    if (explicitConversationTargetEntityId != null &&
        !EntityIdentity.isValid(explicitConversationTargetEntityId)) {
      throw const IdentityApplicationException(
        'invalid_conversation_target_id',
      );
    }
    if (reference.conversationTargetEntityId != null &&
        explicitConversationTargetEntityId != null &&
        reference.conversationTargetEntityId !=
            explicitConversationTargetEntityId) {
      throw const IdentityApplicationException(
        'contradictory_conversation_target',
      );
    }
    for (final entry in _relationEvidenceByEntityId.entries) {
      if (!EntityIdentity.isValid(entry.key) ||
          entry.key != entry.value.entityId) {
        throw const IdentityApplicationException(
          'invalid_evidence_entity_id',
        );
      }
    }
  }

  Map<String, IdentityCandidateEvidence> get relationEvidenceByEntityId =>
      UnmodifiableMapView(_relationEvidenceByEntityId);

  DateTime resolveReferenceDate(DateTime Function() now) =>
      (referenceDate ?? now()).toUtc();
}

final class IdentityApplicationResult {
  final IdentityApplicationStatus status;
  final EntityResolution? resolution;
  final LifeEntity? resolvedEntity;
  final List<EntityCandidate> _candidates;
  final List<String> _diagnosticCodes;

  IdentityApplicationResult._({
    required this.status,
    required this.resolution,
    required this.resolvedEntity,
    required List<EntityCandidate> candidates,
    required List<String> diagnosticCodes,
  })  : _candidates = List.unmodifiable(candidates),
        _diagnosticCodes = List.unmodifiable(
          diagnosticCodes.toSet().toList(growable: false),
        ) {
    if (status == IdentityApplicationStatus.resolved &&
        (resolution == null || resolvedEntity == null)) {
      throw const IdentityApplicationException(
        'resolved_result_requires_entity',
      );
    }
    if (status != IdentityApplicationStatus.resolved &&
        resolvedEntity != null) {
      throw const IdentityApplicationException(
        'unresolved_result_cannot_contain_entity',
      );
    }
    if (status == IdentityApplicationStatus.repositoryFailure &&
        (resolution != null || _diagnosticCodes.isEmpty)) {
      throw const IdentityApplicationException(
        'invalid_repository_failure_result',
      );
    }
  }

  factory IdentityApplicationResult.fromResolution(EntityResolution value) {
    final status = switch (value.status) {
      EntityResolutionStatus.resolved => IdentityApplicationStatus.resolved,
      EntityResolutionStatus.ambiguous => IdentityApplicationStatus.ambiguous,
      EntityResolutionStatus.notFound => IdentityApplicationStatus.notFound,
      EntityResolutionStatus.needsConfirmation =>
        IdentityApplicationStatus.needsConfirmation,
      EntityResolutionStatus.invalid => IdentityApplicationStatus.invalid,
    };
    return IdentityApplicationResult._(
      status: status,
      resolution: value,
      resolvedEntity: value.resolvedEntity,
      candidates: value.candidates,
      diagnosticCodes: value.reasonCodes,
    );
  }

  factory IdentityApplicationResult.repositoryFailure() =>
      IdentityApplicationResult._(
        status: IdentityApplicationStatus.repositoryFailure,
        resolution: null,
        resolvedEntity: null,
        candidates: const [],
        diagnosticCodes: const ['repository_failure'],
      );

  List<EntityCandidate> get candidates => UnmodifiableListView(_candidates);
  List<String> get diagnosticCodes => UnmodifiableListView(_diagnosticCodes);
}
