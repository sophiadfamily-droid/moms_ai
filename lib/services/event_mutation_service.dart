import '../core/identity/entity_identity.dart';
import '../models/event_model.dart';
import '../models/event_participant_identity_link.dart';

sealed class EventParticipantMutationIntent {
  const EventParticipantMutationIntent();
}

final class PreserveEventParticipant extends EventParticipantMutationIntent {
  const PreserveEventParticipant();
}

final class ReplaceEventParticipant extends EventParticipantMutationIntent {
  final EventParticipantIdentityLink replacement;

  const ReplaceEventParticipant(this.replacement);
}

final class RemoveEventParticipant extends EventParticipantMutationIntent {
  const RemoveEventParticipant();
}

abstract final class EventMutationService {
  static EventModel apply({
    required EventModel existing,
    required EventModel proposed,
    EventParticipantMutationIntent participantIntent =
        const PreserveEventParticipant(),
  }) {
    if (EntityIdentity.isValid(existing.id) && existing.id != proposed.id) {
      throw const FormatException('event_mutation_id_mismatch');
    }
    if (participantIntent case ReplaceEventParticipant(:final replacement)) {
      final currentScope = existing.participantIdentity?.accountScopeId;
      if (currentScope != null && replacement.accountScopeId != currentScope) {
        throw const FormatException('event_participant_scope_mismatch');
      }
    }
    return switch (participantIntent) {
      PreserveEventParticipant() => proposed.copyWith(
          participantIdentity: existing.participantIdentity,
          clearParticipantIdentity: existing.participantIdentity == null,
          participantIdentityRevision: existing.participantIdentityRevision,
        ),
      ReplaceEventParticipant(:final replacement) => proposed.copyWith(
          participantIdentity: replacement,
          participantIdentityRevision: existing.participantIdentityRevision == 0
              ? 1
              : existing.participantIdentityRevision + 1,
        ),
      RemoveEventParticipant() => proposed.copyWith(
          clearParticipantIdentity: true,
          participantIdentityRevision: existing.participantIdentity == null
              ? existing.participantIdentityRevision
              : existing.participantIdentityRevision + 1,
        ),
    };
  }

  static EventModel duplicate(EventModel source) => source.copyWith(
        clearId: true,
        clearParticipantIdentity: true,
        participantIdentityRevision: 0,
      );

  static List<EventModel> reconcileFullRewrite({
    required List<EventModel> existing,
    required List<EventModel> proposed,
  }) {
    final existingById = {
      for (final event in existing)
        if (EntityIdentity.isValid(event.id)) event.id!: event,
    };
    return proposed.map((event) {
      final current = existingById[event.id];
      if (current == null) return event;
      if (_hasExplicitParticipantMutation(current, event)) return event;
      return apply(existing: current, proposed: event);
    }).toList(growable: false);
  }

  static bool _hasExplicitParticipantMutation(
    EventModel existing,
    EventModel proposed,
  ) {
    if (proposed.participantIdentityRevision <=
        existing.participantIdentityRevision) {
      return false;
    }
    if (proposed.participantIdentityRevision !=
        existing.participantIdentityRevision + 1) {
      throw const FormatException('invalid_participant_identity_revision');
    }
    return true;
  }
}
