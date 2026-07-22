import '../../core/identity/entity_types.dart';
import '../../core/identity/entity_normalizer.dart';
import '../../core/identity/life_entity.dart';
import '../../core/identity/persisted_identity_link.dart';
import '../../models/event_participant.dart';
import '../../models/event_participant_identity_link.dart';
import '../../repositories/identity/identity_read_repository.dart';

enum EventParticipantIdentityValidationStatus {
  valid,
  invalid,
  repositoryFailure,
}

final class EventParticipantIdentityValidationResult {
  final EventParticipantIdentityValidationStatus status;
  final EventParticipantIdentityLink? link;
  final String diagnosticCode;

  const EventParticipantIdentityValidationResult.valid(
    EventParticipantIdentityLink this.link,
  )   : status = EventParticipantIdentityValidationStatus.valid,
        diagnosticCode = 'event_participant_identity_valid';

  const EventParticipantIdentityValidationResult.invalid(String diagnostic)
      : status = EventParticipantIdentityValidationStatus.invalid,
        link = null,
        diagnosticCode = diagnostic;

  const EventParticipantIdentityValidationResult.repositoryFailure()
      : status = EventParticipantIdentityValidationStatus.repositoryFailure,
        link = null,
        diagnosticCode = 'event_participant_identity_repository_failure';
}

final class EventParticipantIdentityValidationService {
  static const int _maximumMergeDepth = 5;
  final IdentityReadRepository repository;

  const EventParticipantIdentityValidationService({required this.repository});

  Future<EventParticipantIdentityValidationResult> validate({
    required IdentityAccountScope scope,
    required String entityId,
    required EventParticipant participant,
  }) async {
    if (participant.entityType != EventParticipantEntityType.person ||
        participant.evidence != EventParticipantEvidence.explicitUserInput) {
      return const EventParticipantIdentityValidationResult.invalid(
        'event_participant_identity_invalid_participant',
      );
    }
    try {
      var currentId = entityId;
      final visited = <String>{};
      for (var depth = 0; depth <= _maximumMergeDepth; depth++) {
        if (!visited.add(currentId)) {
          return const EventParticipantIdentityValidationResult.invalid(
            'event_participant_identity_merge_cycle',
          );
        }
        final entity = await repository.findById(
          scope: scope,
          entityId: currentId,
        );
        if (entity == null || entity.type != EntityType.person) {
          return const EventParticipantIdentityValidationResult.invalid(
            'event_participant_identity_not_referenceable',
          );
        }
        if (depth == 0 && !_matchesParticipant(entity, participant)) {
          return const EventParticipantIdentityValidationResult.invalid(
            'event_participant_identity_binding_mismatch',
          );
        }
        if (entity.status == EntityStatus.active) {
          return EventParticipantIdentityValidationResult.valid(
            EventParticipantIdentityLink(
              identity: PersistedIdentityLink(
                entityId: entity.id,
                entityType: EntityType.person,
              ),
              accountScopeId: scope.accountId,
            ),
          );
        }
        if (entity.status != EntityStatus.merged ||
            entity.mergedIntoEntityId == null ||
            depth == _maximumMergeDepth) {
          return const EventParticipantIdentityValidationResult.invalid(
            'event_participant_identity_not_referenceable',
          );
        }
        currentId = entity.mergedIntoEntityId!;
      }
      return const EventParticipantIdentityValidationResult.invalid(
        'event_participant_identity_not_referenceable',
      );
    } catch (_) {
      return const EventParticipantIdentityValidationResult.repositoryFailure();
    }
  }

  bool _matchesParticipant(LifeEntity entity, EventParticipant participant) {
    final key = EntityNormalizer.comparisonKey(participant.label);
    if (entity.comparisonKey == key) return true;
    return entity.aliases.any(
      (alias) =>
          alias.comparisonKey == key && alias.isActiveAt(entity.updatedAt),
    );
  }
}
