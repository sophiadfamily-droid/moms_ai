import 'dart:collection';

import '../core/identity/entity_identity.dart';
import '../core/identity/entity_reference.dart';
import '../core/identity/entity_types.dart';
import 'chat_backend_request.dart';
import 'conversation_epistemic_models.dart';
import 'conversation_reference_resolution.dart';
import 'event_model.dart';
import 'event_mutation_models.dart';
import 'event_participant.dart';
import 'memory_lifecycle_state.dart';
import 'memory_contradiction.dart';
import 'action_autonomy_policy.dart';
import 'action_confirmation.dart';
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
  final int sessionGeneration;
  final String? logicalRequestId;
  final String? correlationId;

  const ConversationInput({
    required this.message,
    required this.profile,
    this.sessionGeneration = 0,
    this.logicalRequestId,
    this.correlationId,
  });
}

enum PendingConversationActionType {
  taskClarification,
  shoppingClarification,
  eventConfirmation,
  identityClarification,
  identityCreation,
  memoryConfirmation,
  eventTargetClarification,
  eventMutationConfirmation,
  autonomyConfirmation,
}

enum ShoppingClarificationType { moreOrNoMore }

final class PendingShoppingClarification {
  const PendingShoppingClarification({
    required this.clarificationId,
    required this.logicalRequestId,
    required this.sessionGeneration,
    required this.article,
    required this.type,
    required this.createdAt,
    required this.expiresAt,
  });

  final String clarificationId;
  final String logicalRequestId;
  final int sessionGeneration;
  final String article;
  final ShoppingClarificationType type;
  final DateTime createdAt;
  final DateTime expiresAt;

  bool isExpiredAt(DateTime value) => !value.isBefore(expiresAt);
}

final class PendingTaskClarificationDraft {
  const PendingTaskClarificationDraft({
    required this.draftId,
    required this.logicalRequestId,
    required this.sessionGeneration,
    required this.dueDate,
    required this.priority,
    required this.isImportant,
    required this.originalInstruction,
    required this.createdAt,
    required this.expiresAt,
  });

  final String draftId;
  final String logicalRequestId;
  final int sessionGeneration;
  final String dueDate;
  final String priority;
  final bool isImportant;
  final String originalInstruction;
  final DateTime createdAt;
  final DateTime expiresAt;

  bool isExpiredAt(DateTime value) => !value.isBefore(expiresAt);
}

final class PendingEventTargetClarification {
  final String clarificationId;
  final EventMutationRequest request;
  final List<EventModel> _candidates;
  final DateTime createdAt;
  final DateTime expiresAt;

  PendingEventTargetClarification({
    required this.clarificationId,
    required this.request,
    required List<EventModel> candidates,
    required this.createdAt,
    required this.expiresAt,
  }) : _candidates = List.unmodifiable(candidates) {
    if (!EntityIdentity.isValid(clarificationId) ||
        _candidates.length < 2 ||
        _candidates.length > 10 ||
        _candidates.any((event) => !EntityIdentity.isValid(event.id)) ||
        !expiresAt.isAfter(createdAt)) {
      throw const FormatException('invalid_event_target_clarification');
    }
  }

  List<EventModel> get candidates => UnmodifiableListView(_candidates);

  bool isExpiredAt(DateTime value) => !value.isBefore(expiresAt);
}

final class PendingEventMutationConfirmation {
  final String mutationId;
  final EventMutationRequest request;
  final EventModel original;
  final EventModel proposed;
  final String? participantIdentityEntityId;
  final String confirmationMessage;
  final DateTime createdAt;
  final DateTime expiresAt;

  PendingEventMutationConfirmation({
    required this.mutationId,
    required this.request,
    required this.original,
    required this.proposed,
    this.participantIdentityEntityId,
    required String confirmationMessage,
    required this.createdAt,
    required this.expiresAt,
  }) : confirmationMessage = confirmationMessage.trim() {
    if (!EntityIdentity.isValid(mutationId) ||
        !EntityIdentity.isValid(original.id) ||
        original.id != proposed.id ||
        (request.operation == EventMutationOperation.replaceParticipant &&
            !EntityIdentity.isValid(participantIdentityEntityId)) ||
        (request.operation != EventMutationOperation.replaceParticipant &&
            participantIdentityEntityId != null) ||
        this.confirmationMessage.isEmpty ||
        !expiresAt.isAfter(createdAt)) {
      throw const FormatException('invalid_event_mutation_confirmation');
    }
  }

  bool isExpiredAt(DateTime value) => !value.isBefore(expiresAt);
}

final class PendingEventParticipantMutationDraft {
  final String actionDraftId;
  final EventMutationRequest request;
  final EventModel original;

  PendingEventParticipantMutationDraft({
    required this.actionDraftId,
    required this.request,
    required this.original,
  }) {
    if (!EntityIdentity.isValid(actionDraftId) ||
        !EntityIdentity.isValid(original.id) ||
        request.operation != EventMutationOperation.replaceParticipant ||
        request.participant == null) {
      throw const ConversationIdentityException(
        'invalid_event_participant_mutation_draft',
      );
    }
  }
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

enum IdentityActionKind { event }

enum IdentityActionTarget { eventParticipant }

final class IdentityActionContinuation {
  final IdentityActionKind actionKind;
  final String actionDraftId;
  final IdentityActionTarget target;

  IdentityActionContinuation({
    required this.actionKind,
    required this.actionDraftId,
    required this.target,
  }) {
    if (!EntityIdentity.isValid(actionDraftId)) {
      throw const ConversationIdentityException('invalid_action_draft_id');
    }
    if (actionKind == IdentityActionKind.event &&
        target != IdentityActionTarget.eventParticipant) {
      throw const ConversationIdentityException('incompatible_action_target');
    }
  }
}

final class PendingIdentityActionBinding {
  final String bindingId;
  final String accountScopeId;
  final IdentityActionContinuation continuation;
  final String? clarificationId;
  final String? resolvedEntityId;
  final ActionType actionType;
  final ActionOrigin origin;
  final ActionRiskLevel riskLevel;
  final ActionAutonomyMode policyModeAtCreation;
  final int policyVersionAtCreation;
  final int sessionGeneration;
  final bool hasExplicitConfirmation;

  PendingIdentityActionBinding({
    required this.bindingId,
    required String accountScopeId,
    required this.continuation,
    this.clarificationId,
    this.resolvedEntityId,
    this.actionType = ActionType.linkIdentity,
    this.origin = ActionOrigin.structuredContinuation,
    this.riskLevel = ActionRiskLevel.sensitiveMutation,
    this.policyModeAtCreation = ActionAutonomyMode.suggestions,
    this.policyVersionAtCreation = ActionAutonomyPolicy.currentSchemaVersion,
    this.sessionGeneration = 0,
    this.hasExplicitConfirmation = false,
  }) : accountScopeId = accountScopeId.trim() {
    if (!EntityIdentity.isValid(bindingId)) {
      throw const ConversationIdentityException('invalid_binding_id');
    }
    if (this.accountScopeId.isEmpty) {
      throw const ConversationIdentityException('invalid_account_scope');
    }
    if (clarificationId != null && !EntityIdentity.isValid(clarificationId)) {
      throw const ConversationIdentityException('invalid_clarification_id');
    }
    if (resolvedEntityId != null && !EntityIdentity.isValid(resolvedEntityId)) {
      throw const ConversationIdentityException('invalid_resolved_entity_id');
    }
    if (riskLevel != ActionRiskLevel.sensitiveMutation ||
        sessionGeneration < 0) {
      throw const ConversationIdentityException(
        'invalid_identity_autonomy_metadata',
      );
    }
  }

  bool get isApplied => resolvedEntityId != null;

  PendingIdentityActionBinding copyWith({
    String? clarificationId,
    String? resolvedEntityId,
    bool? hasExplicitConfirmation,
  }) {
    return PendingIdentityActionBinding(
      bindingId: bindingId,
      accountScopeId: accountScopeId,
      continuation: continuation,
      clarificationId: clarificationId ?? this.clarificationId,
      resolvedEntityId: resolvedEntityId ?? this.resolvedEntityId,
      actionType: actionType,
      origin: origin,
      riskLevel: riskLevel,
      policyModeAtCreation: policyModeAtCreation,
      policyVersionAtCreation: policyVersionAtCreation,
      sessionGeneration: sessionGeneration,
      hasExplicitConfirmation:
          hasExplicitConfirmation ?? this.hasExplicitConfirmation,
    );
  }
}

final class PendingEventIdentityDraft {
  final String actionDraftId;
  final EventModel event;
  final EventParticipant participant;
  final String confirmationMessage;

  PendingEventIdentityDraft({
    required this.actionDraftId,
    required this.event,
    required this.participant,
    required String confirmationMessage,
  }) : confirmationMessage = confirmationMessage.trim() {
    if (!EntityIdentity.isValid(actionDraftId) ||
        this.confirmationMessage.isEmpty) {
      throw const ConversationIdentityException('invalid_event_identity_draft');
    }
  }
}

enum IdentityActionBindingStatus {
  attached,
  pendingClarification,
  pendingCreation,
  cancelled,
  expired,
  invalid,
  alreadyApplied,
}

final class IdentityActionBindingResult {
  final IdentityActionBindingStatus status;
  final String bindingId;
  final String actionDraftId;
  final IdentityActionTarget target;
  final String? resolvedEntityId;
  final String diagnosticCode;
  final PendingIdentityActionBinding binding;

  IdentityActionBindingResult({
    required this.status,
    required this.bindingId,
    required this.actionDraftId,
    required this.target,
    this.resolvedEntityId,
    required this.diagnosticCode,
    required this.binding,
  }) {
    final hasResolvedId = EntityIdentity.isValid(resolvedEntityId);
    if (status == IdentityActionBindingStatus.attached && !hasResolvedId) {
      throw const ConversationIdentityException(
        'attached_binding_requires_entity',
      );
    }
    if (status == IdentityActionBindingStatus.attached &&
        binding.resolvedEntityId != resolvedEntityId) {
      throw const ConversationIdentityException(
        'attached_result_binding_mismatch',
      );
    }
    if (status != IdentityActionBindingStatus.attached &&
        resolvedEntityId != null) {
      throw const ConversationIdentityException(
        'unattached_binding_cannot_contain_entity',
      );
    }
    if (bindingId != binding.bindingId ||
        actionDraftId != binding.continuation.actionDraftId ||
        target != binding.continuation.target ||
        diagnosticCode.trim().isEmpty) {
      throw const ConversationIdentityException('invalid_binding_result');
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
  final PendingIdentityActionBinding? actionBinding;

  PendingIdentityClarification({
    required this.clarificationId,
    required this.reference,
    required List<IdentityClarificationChoice> candidateChoices,
    required this.createdAt,
    required this.expiresAt,
    required String accountScopeId,
    this.actionBinding,
  })  : _candidateChoices = List.unmodifiable(candidateChoices),
        accountScopeId = accountScopeId.trim() {
    if (!EntityIdentity.isValid(clarificationId)) {
      throw const ConversationIdentityException('invalid_clarification_id');
    }
    if (this.accountScopeId.isEmpty) {
      throw const ConversationIdentityException('invalid_account_scope');
    }
    if (actionBinding != null &&
        actionBinding!.accountScopeId != this.accountScopeId) {
      throw const ConversationIdentityException('binding_scope_mismatch');
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

  PendingIdentityClarification withActionBinding(
    PendingIdentityActionBinding binding,
  ) {
    return PendingIdentityClarification(
      clarificationId: clarificationId,
      reference: reference,
      candidateChoices: _candidateChoices,
      createdAt: createdAt,
      expiresAt: expiresAt,
      accountScopeId: accountScopeId,
      actionBinding: binding,
    );
  }
}

enum IdentityClarificationStatus {
  resolved,
  stillAmbiguous,
  cancelled,
  expired,
  invalid,
}

final class PendingIdentityCreation {
  final String proposalId;
  final String entityId;
  final EntityType entityType;
  final String canonicalLabel;
  final EntitySource source;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String accountScopeId;
  final PendingIdentityActionBinding? actionBinding;

  PendingIdentityCreation({
    required this.proposalId,
    required this.entityId,
    required this.entityType,
    required String canonicalLabel,
    required this.source,
    required this.createdAt,
    required this.expiresAt,
    required String accountScopeId,
    this.actionBinding,
  })  : canonicalLabel = canonicalLabel.trim(),
        accountScopeId = accountScopeId.trim() {
    if (!EntityIdentity.isValid(proposalId) ||
        !EntityIdentity.isValid(entityId)) {
      throw const ConversationIdentityException('invalid_creation_id');
    }
    if (entityType == EntityType.unknown ||
        source.type == EntitySourceType.unknown ||
        this.canonicalLabel.isEmpty) {
      throw const ConversationIdentityException('invalid_creation_data');
    }
    if (this.accountScopeId.isEmpty) {
      throw const ConversationIdentityException('invalid_account_scope');
    }
    if (actionBinding != null &&
        actionBinding!.accountScopeId != this.accountScopeId) {
      throw const ConversationIdentityException('binding_scope_mismatch');
    }
    if (!expiresAt.isAfter(createdAt)) {
      throw const ConversationIdentityException('invalid_expiration_date');
    }
  }

  bool isExpiredAt(DateTime referenceDate) =>
      !referenceDate.isBefore(expiresAt);
}

enum IdentityCreationStatus {
  created,
  stillPending,
  cancelled,
  expired,
  alreadyExists,
  invalid,
  repositoryFailure,
}

final class IdentityCreationResult {
  final IdentityCreationStatus status;
  final String proposalId;
  final String? createdEntityId;
  final String diagnosticCode;
  final String followUpMessage;

  IdentityCreationResult({
    required this.status,
    required this.proposalId,
    this.createdEntityId,
    required this.diagnosticCode,
    required this.followUpMessage,
  }) {
    final hasEntityId = EntityIdentity.isValid(createdEntityId);
    if (status == IdentityCreationStatus.created && !hasEntityId) {
      throw const ConversationIdentityException(
        'created_result_requires_entity',
      );
    }
    if (status != IdentityCreationStatus.created && createdEntityId != null) {
      throw const ConversationIdentityException(
        'uncreated_result_cannot_contain_entity',
      );
    }
    if (!EntityIdentity.isValid(proposalId) ||
        diagnosticCode.trim().isEmpty ||
        followUpMessage.trim().isEmpty) {
      throw const ConversationIdentityException('invalid_creation_result');
    }
  }
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
  final EventParticipant? eventParticipant;
  final String? participantIdentityEntityId;
  final String? proposalId;
  final MemoryLifecycleAction? expectedMemoryAction;
  final DateTime? createdAt;
  final PendingIdentityClarification? identityClarification;
  final PendingIdentityCreation? identityCreation;
  final PendingEventTargetClarification? eventTargetClarification;
  final PendingEventMutationConfirmation? eventMutationConfirmation;
  final ActionPending? autonomyPending;
  final ActionConfirmation? canonicalConfirmation;
  final ActionPendingMetadata autonomyMetadata;
  final MemoryContradictionCandidate? memoryContradiction;
  final MemoryReplacementPendingAction? memoryReplacementAction;
  final PendingTaskClarificationDraft? taskClarification;
  final PendingShoppingClarification? shoppingClarification;

  const PendingConversationAction.taskClarification(
    this.taskClarification,
  )   : type = PendingConversationActionType.taskClarification,
        _event = null,
        eventParticipant = null,
        participantIdentityEntityId = null,
        proposalId = null,
        expectedMemoryAction = null,
        createdAt = null,
        identityClarification = null,
        identityCreation = null,
        eventTargetClarification = null,
        eventMutationConfirmation = null,
        shoppingClarification = null,
        autonomyPending = null,
        canonicalConfirmation = null,
        memoryContradiction = null,
        memoryReplacementAction = null,
        autonomyMetadata = const ActionPendingMetadata(
          actionType: ActionType.createTask,
          origin: ActionOrigin.structuredContinuation,
          riskLevel: ActionRiskLevel.mutation,
          policyModeAtCreation: ActionAutonomyMode.suggestions,
          policyVersionAtCreation: 1,
          sessionGeneration: 0,
        );

  const PendingConversationAction.eventConfirmation(
    EventModel this._event, {
    this.eventParticipant,
    this.participantIdentityEntityId,
    this.canonicalConfirmation,
    this.autonomyMetadata = const ActionPendingMetadata(
      actionType: ActionType.createEvent,
      origin: ActionOrigin.structuredContinuation,
      riskLevel: ActionRiskLevel.mutation,
      policyModeAtCreation: ActionAutonomyMode.suggestions,
      policyVersionAtCreation: 1,
      sessionGeneration: 0,
    ),
  })  : type = PendingConversationActionType.eventConfirmation,
        proposalId = null,
        expectedMemoryAction = null,
        createdAt = null,
        identityClarification = null,
        identityCreation = null,
        eventTargetClarification = null,
        eventMutationConfirmation = null,
        shoppingClarification = null,
        autonomyPending = null,
        taskClarification = null,
        memoryContradiction = null,
        memoryReplacementAction = null;

  const PendingConversationAction.memoryConfirmation({
    required this.proposalId,
    required this.createdAt,
    required this.expectedMemoryAction,
    this.memoryContradiction,
    this.memoryReplacementAction,
    this.canonicalConfirmation,
    this.autonomyMetadata = const ActionPendingMetadata(
      actionType: ActionType.confirmMemory,
      origin: ActionOrigin.structuredContinuation,
      riskLevel: ActionRiskLevel.sensitiveMutation,
      policyModeAtCreation: ActionAutonomyMode.suggestions,
      policyVersionAtCreation: 1,
      sessionGeneration: 0,
    ),
  })  : type = PendingConversationActionType.memoryConfirmation,
        _event = null,
        eventParticipant = null,
        participantIdentityEntityId = null,
        identityClarification = null,
        identityCreation = null,
        eventTargetClarification = null,
        eventMutationConfirmation = null,
        shoppingClarification = null,
        taskClarification = null,
        autonomyPending = null;

  const PendingConversationAction.identityClarification(
    PendingIdentityClarification this.identityClarification, {
    this.canonicalConfirmation,
    this.autonomyMetadata = const ActionPendingMetadata(
      actionType: ActionType.linkIdentity,
      origin: ActionOrigin.structuredContinuation,
      riskLevel: ActionRiskLevel.sensitiveMutation,
      policyModeAtCreation: ActionAutonomyMode.suggestions,
      policyVersionAtCreation: 1,
      sessionGeneration: 0,
    ),
  })  : type = PendingConversationActionType.identityClarification,
        _event = null,
        eventParticipant = null,
        participantIdentityEntityId = null,
        proposalId = null,
        expectedMemoryAction = null,
        createdAt = null,
        identityCreation = null,
        eventTargetClarification = null,
        eventMutationConfirmation = null,
        shoppingClarification = null,
        taskClarification = null,
        autonomyPending = null,
        memoryContradiction = null,
        memoryReplacementAction = null;

  const PendingConversationAction.identityCreation(
    PendingIdentityCreation this.identityCreation, {
    this.canonicalConfirmation,
    this.autonomyMetadata = const ActionPendingMetadata(
      actionType: ActionType.createIdentity,
      origin: ActionOrigin.structuredContinuation,
      riskLevel: ActionRiskLevel.sensitiveMutation,
      policyModeAtCreation: ActionAutonomyMode.suggestions,
      policyVersionAtCreation: 1,
      sessionGeneration: 0,
    ),
  })  : type = PendingConversationActionType.identityCreation,
        _event = null,
        eventParticipant = null,
        participantIdentityEntityId = null,
        proposalId = null,
        expectedMemoryAction = null,
        createdAt = null,
        identityClarification = null,
        eventTargetClarification = null,
        eventMutationConfirmation = null,
        shoppingClarification = null,
        taskClarification = null,
        autonomyPending = null,
        memoryContradiction = null,
        memoryReplacementAction = null;

  const PendingConversationAction.eventTargetClarification(
    PendingEventTargetClarification this.eventTargetClarification, {
    this.canonicalConfirmation,
    this.autonomyMetadata = const ActionPendingMetadata(
      actionType: ActionType.updateEvent,
      origin: ActionOrigin.structuredContinuation,
      riskLevel: ActionRiskLevel.mutation,
      policyModeAtCreation: ActionAutonomyMode.suggestions,
      policyVersionAtCreation: 1,
      sessionGeneration: 0,
    ),
  })  : type = PendingConversationActionType.eventTargetClarification,
        _event = null,
        eventParticipant = null,
        participantIdentityEntityId = null,
        proposalId = null,
        expectedMemoryAction = null,
        createdAt = null,
        identityClarification = null,
        identityCreation = null,
        eventMutationConfirmation = null,
        shoppingClarification = null,
        taskClarification = null,
        autonomyPending = null,
        memoryContradiction = null,
        memoryReplacementAction = null;

  const PendingConversationAction.eventMutationConfirmation(
    PendingEventMutationConfirmation this.eventMutationConfirmation, {
    this.canonicalConfirmation,
    this.autonomyMetadata = const ActionPendingMetadata(
      actionType: ActionType.updateEvent,
      origin: ActionOrigin.structuredContinuation,
      riskLevel: ActionRiskLevel.mutation,
      policyModeAtCreation: ActionAutonomyMode.suggestions,
      policyVersionAtCreation: 1,
      sessionGeneration: 0,
    ),
  })  : type = PendingConversationActionType.eventMutationConfirmation,
        _event = null,
        eventParticipant = null,
        participantIdentityEntityId = null,
        proposalId = null,
        expectedMemoryAction = null,
        createdAt = null,
        identityClarification = null,
        identityCreation = null,
        eventTargetClarification = null,
        shoppingClarification = null,
        taskClarification = null,
        autonomyPending = null,
        memoryContradiction = null,
        memoryReplacementAction = null;

  PendingConversationAction.autonomyConfirmation(
    ActionPending this.autonomyPending,
    this.canonicalConfirmation,
  )   : autonomyMetadata = ActionPendingMetadata(
          actionType: autonomyPending.actionType,
          origin: autonomyPending.origin,
          riskLevel: autonomyPending.riskLevel,
          policyModeAtCreation: autonomyPending.policyModeAtCreation,
          policyVersionAtCreation: autonomyPending.policyVersionAtCreation,
          sessionGeneration: autonomyPending.sessionGeneration,
        ),
        type = PendingConversationActionType.autonomyConfirmation,
        _event = null,
        eventParticipant = null,
        participantIdentityEntityId = null,
        proposalId = null,
        expectedMemoryAction = null,
        createdAt = null,
        identityClarification = null,
        identityCreation = null,
        eventTargetClarification = null,
        eventMutationConfirmation = null,
        shoppingClarification = null,
        taskClarification = null,
        memoryContradiction = null,
        memoryReplacementAction = null;

  const PendingConversationAction.shoppingClarification(
    PendingShoppingClarification this.shoppingClarification,
  )   : type = PendingConversationActionType.shoppingClarification,
        _event = null,
        eventParticipant = null,
        participantIdentityEntityId = null,
        proposalId = null,
        expectedMemoryAction = null,
        createdAt = null,
        identityClarification = null,
        identityCreation = null,
        eventTargetClarification = null,
        eventMutationConfirmation = null,
        autonomyPending = null,
        canonicalConfirmation = null,
        taskClarification = null,
        memoryContradiction = null,
        memoryReplacementAction = null,
        autonomyMetadata = const ActionPendingMetadata(
          actionType: ActionType.addShoppingItem,
          origin: ActionOrigin.structuredContinuation,
          riskLevel: ActionRiskLevel.mutation,
          policyModeAtCreation: ActionAutonomyMode.suggestions,
          policyVersionAtCreation: 1,
          sessionGeneration: 0,
        );

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
  final IdentityActionBindingResult? identityActionBindingResult;
  final IdentityCreationResult? identityCreationResult;
  final ConversationResponseKind? responseKind;
  final ConversationClarification? epistemicClarification;
  final ConversationReferenceResolution? referenceResolution;

  const ConversationOutcome({
    required this.reply,
    this.request,
    this.identityClarificationResult,
    this.identityActionBindingResult,
    this.identityCreationResult,
    this.responseKind,
    this.epistemicClarification,
    this.referenceResolution,
  });
}

class PendingConversationResolution {
  final String message;
  final String? diagnosticCode;
  final IdentityClarificationResult? identityClarificationResult;
  final IdentityActionBindingResult? identityActionBindingResult;
  final IdentityCreationResult? identityCreationResult;
  final ConversationReferenceResolution? referenceResolution;

  const PendingConversationResolution(
    this.message, {
    this.diagnosticCode,
    this.identityClarificationResult,
    this.identityActionBindingResult,
    this.identityCreationResult,
    this.referenceResolution,
  });
}
