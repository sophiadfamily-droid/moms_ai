import 'dart:collection';

import '../core/identity/entity_identity.dart';
import '../core/identity/entity_reference.dart';
import '../core/identity/entity_types.dart';
import 'chat_backend_request.dart';
import 'event_model.dart';
import 'memory_lifecycle_state.dart';
import 'user_profile.dart';

enum ConversationPhase {
  idle,
  sending,
  awaitingActionConfirmation,
  executingAction,
}

class ConversationInput {
  final String message;
  final UserProfile profile;

  const ConversationInput({
    required this.message,
    required this.profile,
  });
}

enum PendingConversationActionType {
  eventConfirmation,
  identityClarification,
  memoryConfirmation,
}

final class ConversationIdentityException implements Exception {
  final String code;

  const ConversationIdentityException(this.code);
}

final class IdentityClarificationChoice {
  final String entityId;
  final EntityType type;
  final String displayLabel;

  IdentityClarificationChoice({
    required this.entityId,
    required this.type,
    required this.displayLabel,
  }) {
    if (!EntityIdentity.isValid(entityId)) {
      throw const ConversationIdentityException('invalid_choice_entity_id');
    }
    if (displayLabel.trim().isEmpty) {
      throw const ConversationIdentityException('empty_choice_label');
    }
  }
}

final class PendingIdentityClarification {
  final String clarificationId;
  final EntityReference reference;
  final List<IdentityClarificationChoice> _candidateChoices;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String accountScopeId;

  PendingIdentityClarification({
    required this.clarificationId,
    required this.reference,
    required List<IdentityClarificationChoice> candidateChoices,
    required this.createdAt,
    required this.expiresAt,
    required String accountScopeId,
  })  : _candidateChoices = List.unmodifiable(candidateChoices),
        accountScopeId = accountScopeId.trim() {
    if (!EntityIdentity.isValid(clarificationId)) {
      throw const ConversationIdentityException('invalid_clarification_id');
    }
    if (this.accountScopeId.isEmpty) {
      throw const ConversationIdentityException('invalid_account_scope');
    }
    if (!expiresAt.isAfter(createdAt)) {
      throw const ConversationIdentityException('invalid_expiration_date');
    }
    if (_candidateChoices.isEmpty || _candidateChoices.length > 20) {
      throw const ConversationIdentityException('invalid_choice_count');
    }
    final ids = _candidateChoices.map((choice) => choice.entityId).toSet();
    if (ids.length != _candidateChoices.length) {
      throw const ConversationIdentityException('duplicate_choice_entity_id');
    }
  }

  List<IdentityClarificationChoice> get candidateChoices =>
      UnmodifiableListView(_candidateChoices);

  bool isExpiredAt(DateTime referenceDate) =>
      !referenceDate.isBefore(expiresAt);
}

enum IdentityClarificationStatus {
  resolved,
  stillAmbiguous,
  cancelled,
  expired,
  invalid,
}

final class IdentityClarificationResult {
  final IdentityClarificationStatus status;
  final String? resolvedEntityId;
  final String clarificationId;
  final String diagnosticCode;
  final String followUpMessage;

  IdentityClarificationResult({
    required this.status,
    this.resolvedEntityId,
    required this.clarificationId,
    required this.diagnosticCode,
    required this.followUpMessage,
  }) {
    final hasResolvedId = EntityIdentity.isValid(resolvedEntityId);
    if (status == IdentityClarificationStatus.resolved && !hasResolvedId) {
      throw const ConversationIdentityException(
        'resolved_clarification_requires_entity',
      );
    }
    if (status != IdentityClarificationStatus.resolved &&
        resolvedEntityId != null) {
      throw const ConversationIdentityException(
        'unresolved_clarification_cannot_contain_entity',
      );
    }
    if (!EntityIdentity.isValid(clarificationId) ||
        diagnosticCode.trim().isEmpty ||
        followUpMessage.trim().isEmpty) {
      throw const ConversationIdentityException(
        'invalid_clarification_result',
      );
    }
  }
}

class PendingConversationAction {
  final PendingConversationActionType type;
  final EventModel? _event;
  final String? proposalId;
  final MemoryLifecycleAction? expectedMemoryAction;
  final DateTime? createdAt;
  final PendingIdentityClarification? identityClarification;

  const PendingConversationAction.eventConfirmation(EventModel this._event)
      : type = PendingConversationActionType.eventConfirmation,
        proposalId = null,
        expectedMemoryAction = null,
        createdAt = null,
        identityClarification = null;

  const PendingConversationAction.memoryConfirmation({
    required this.proposalId,
    required this.createdAt,
    required this.expectedMemoryAction,
  })  : type = PendingConversationActionType.memoryConfirmation,
        _event = null,
        identityClarification = null;

  const PendingConversationAction.identityClarification(
    PendingIdentityClarification this.identityClarification,
  )   : type = PendingConversationActionType.identityClarification,
        _event = null,
        proposalId = null,
        expectedMemoryAction = null,
        createdAt = null;

  EventModel get event => _event!;
}

class ConversationState {
  final ConversationPhase phase;
  final String currentInstruction;
  final PendingConversationAction? pendingAction;

  const ConversationState({
    this.phase = ConversationPhase.idle,
    this.currentInstruction = '',
    this.pendingAction,
  });

  ConversationState copyWith({
    ConversationPhase? phase,
    String? currentInstruction,
    PendingConversationAction? pendingAction,
    bool clearPendingAction = false,
  }) {
    return ConversationState(
      phase: phase ?? this.phase,
      currentInstruction: currentInstruction ?? this.currentInstruction,
      pendingAction:
          clearPendingAction ? null : pendingAction ?? this.pendingAction,
    );
  }
}

class ConversationActionOutcome {
  final String message;
  final String? planningTitle;

  const ConversationActionOutcome({
    this.message = '',
    this.planningTitle,
  });
}

class ConversationOutcome {
  final String reply;
  final ChatBackendRequest? request;
  final IdentityClarificationResult? identityClarificationResult;

  const ConversationOutcome({
    required this.reply,
    this.request,
    this.identityClarificationResult,
  });
}

class PendingConversationResolution {
  final String message;
  final IdentityClarificationResult? identityClarificationResult;

  const PendingConversationResolution(
    this.message, {
    this.identityClarificationResult,
  });
}
