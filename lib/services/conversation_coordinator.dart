import '../models/conversation_models.dart';
import '../models/event_model.dart';
import '../models/event_participant.dart';
import '../models/event_mutation_models.dart';
import '../core/identity/entity_id_generator.dart';
import '../core/identity/entity_reference.dart';
import '../core/identity/entity_types.dart';
import '../models/life_context/memory_context.dart';
import '../models/memory_lifecycle.dart';
import '../models/memory_lifecycle_state.dart';
import '../core/identity/uuid_v7_entity_id_generator.dart';
import 'chat_backend_client.dart';
import 'conversation_answer_classifier.dart';
import 'conversation_context_service.dart';
import 'conversation_grounding_policy.dart';
import 'memory_confirmation_copy.dart';
import 'memory_lifecycle_engine.dart';
import 'memory_lifecycle_repository.dart';
import 'identity/identity_application_models.dart';
import 'identity/identity_application_service.dart';
import 'identity/identity_action_binding_service.dart';
import 'identity/identity_clarification_service.dart';
import 'identity/identity_creation_service.dart';
import 'identity/event_participant_identity_validation_service.dart';
import 'event_conversation_mutation_service.dart';
import 'event_mutation_service.dart';
import 'event_target_selector.dart';
import '../repositories/identity/identity_read_repository.dart';
import 'zelia_action_guard_service.dart';
import 'zelia_response_builder.dart';

typedef ConversationActionExecutor = Future<ConversationActionOutcome> Function(
  Map<String, dynamic> action,
);

typedef PendingEventExecutor = Future<String> Function(EventModel event);

class ConversationCoordinator {
  final ChatBackendClient backend;
  final ConversationContextProvider contextProvider;
  final MemoryLifecycleEngine memoryLifecycleEngine;
  final MemoryLifecycleRepository? _memoryLifecycleRepository;
  final ConversationAnswerClassifier answerClassifier;
  final MemoryConfirmationCopy memoryCopy;
  final IdentityClarificationService identityClarificationService;
  final IdentityActionBindingService identityActionBindingService;
  final IdentityApplicationService? identityApplicationService;
  final IdentityCreationService? identityCreationService;
  final IdentityAccountScope? identityAccountScope;
  final EventParticipantIdentityValidationService?
      eventParticipantIdentityValidationService;
  final EntityIdGenerator _actionDraftIdGenerator;
  final EventConversationMutationService eventConversationMutationService;
  final DateTime Function() _clock;

  ConversationState _state = const ConversationState();
  bool _isSending = false;
  bool _isResolvingPendingAction = false;
  final Map<String, PendingIdentityActionBinding> _identityActionBindings = {};
  final Map<String, PendingEventIdentityDraft> _eventIdentityDrafts = {};
  final Map<String, PendingEventParticipantMutationDraft>
      _eventParticipantMutationDrafts = {};

  ConversationCoordinator({
    required this.backend,
    required this.contextProvider,
    this.memoryLifecycleEngine = const MemoryLifecycleEngine(),
    MemoryLifecycleRepository? memoryLifecycleRepository,
    this.answerClassifier = const ConversationAnswerClassifier(),
    this.memoryCopy = const MemoryConfirmationCopy(),
    IdentityClarificationService? identityClarificationService,
    IdentityActionBindingService? identityActionBindingService,
    this.identityApplicationService,
    this.identityCreationService,
    this.identityAccountScope,
    this.eventParticipantIdentityValidationService,
    EntityIdGenerator? actionDraftIdGenerator,
    EventConversationMutationService? eventConversationMutationService,
    DateTime Function()? clock,
  })  : _memoryLifecycleRepository = memoryLifecycleRepository,
        identityClarificationService = identityClarificationService ??
            IdentityClarificationService(
              idGenerator: UuidV7EntityIdGenerator(),
            ),
        identityActionBindingService = identityActionBindingService ??
            IdentityActionBindingService(
              idGenerator: UuidV7EntityIdGenerator(),
            ),
        _actionDraftIdGenerator =
            actionDraftIdGenerator ?? UuidV7EntityIdGenerator(),
        eventConversationMutationService = eventConversationMutationService ??
            EventConversationMutationService(),
        _clock = clock ?? DateTime.now;

  ConversationState get state => _state;

  void setPendingEventConfirmation(
    EventModel? event, {
    EventParticipant? participant,
    String? participantIdentityEntityId,
  }) {
    if (event == null) {
      _state = _state.copyWith(
        phase: ConversationPhase.idle,
        clearPendingAction: true,
      );
      return;
    }

    _state = _state.copyWith(
      phase: ConversationPhase.awaitingActionConfirmation,
      pendingAction: PendingConversationAction.eventConfirmation(
        event,
        eventParticipant: participant,
        participantIdentityEntityId: participantIdentityEntityId,
      ),
    );
  }

  Future<PendingConversationResolution> beginEventParticipantIdentity({
    required EventModel event,
    required EventParticipant participant,
    required String confirmationMessage,
  }) async {
    final scope = identityAccountScope;
    if (scope == null ||
        participant.entityType != EventParticipantEntityType.person ||
        participant.evidence != EventParticipantEvidence.explicitUserInput) {
      return const PendingConversationResolution(
        'L’identité du participant ne peut pas être vérifiée pour le moment.',
      );
    }
    final draftId = _actionDraftIdGenerator.generate();
    final draft = PendingEventIdentityDraft(
      actionDraftId: draftId,
      event: event,
      participant: participant,
      confirmationMessage: confirmationMessage,
    );
    _eventIdentityDrafts[draftId] = draft;
    const source = EntitySource(type: EntitySourceType.user);
    final reference = EntityReference.text(
      value: participant.label,
      kind: EntityReferenceKind.genericLabel,
      expectedType: EntityType.person,
      source: source,
    );
    final request = IdentityResolutionRequest(
      scope: scope,
      reference: reference,
    );
    final resolution = await beginIdentityActionBinding(
      request: request,
      continuation: IdentityActionContinuation(
        actionKind: IdentityActionKind.event,
        actionDraftId: draftId,
        target: IdentityActionTarget.eventParticipant,
      ),
      creationRequest: IdentityCreationRequest(
        scope: scope,
        entityType: EntityType.person,
        canonicalLabel: participant.label,
        source: source,
      ),
    );
    return _resumeIdentityContinuation(resolution);
  }

  void setPendingMemoryConfirmation(
    MemoryConfirmationRequest? request, {
    required DateTime createdAt,
  }) {
    final proposalId = request?.proposalId?.trim() ?? '';
    if (request == null || proposalId.isEmpty) return;
    if (_state.pendingAction?.type ==
            PendingConversationActionType.eventConfirmation ||
        _state.pendingAction?.type ==
            PendingConversationActionType.identityClarification ||
        _state.pendingAction?.type ==
            PendingConversationActionType.identityCreation) {
      return;
    }
    _state = _state.copyWith(
      phase: ConversationPhase.awaitingActionConfirmation,
      pendingAction: PendingConversationAction.memoryConfirmation(
        proposalId: proposalId,
        createdAt: createdAt,
        expectedMemoryAction: request.action,
      ),
    );
  }

  PendingConversationResolution? beginIdentityClarification({
    required IdentityApplicationResult applicationResult,
    required IdentityResolutionRequest request,
  }) {
    if (_state.pendingAction != null) return null;
    final pending = identityClarificationService.create(
      applicationResult: applicationResult,
      request: request,
    );
    _state = _state.copyWith(
      phase: ConversationPhase.awaitingActionConfirmation,
      pendingAction: PendingConversationAction.identityClarification(pending),
    );
    return PendingConversationResolution(
      identityClarificationService.question(pending),
    );
  }

  PendingConversationResolution? beginIdentityCreation({
    required IdentityApplicationResult applicationResult,
    required IdentityCreationRequest request,
  }) {
    final service = identityCreationService;
    if (_state.pendingAction != null || service == null) return null;
    final pending = service.propose(
      applicationResult: applicationResult,
      request: request,
    );
    _state = _state.copyWith(
      phase: ConversationPhase.awaitingActionConfirmation,
      pendingAction: PendingConversationAction.identityCreation(pending),
    );
    return PendingConversationResolution(service.question(pending));
  }

  Future<PendingConversationResolution> beginIdentityActionBinding({
    required IdentityResolutionRequest request,
    required IdentityActionContinuation continuation,
    IdentityCreationRequest? creationRequest,
  }) async {
    final bindingKey = _identityBindingKey(
      accountScopeId: request.scope.accountId,
      continuation: continuation,
    );
    final existingBinding = _identityActionBindings[bindingKey];
    if (existingBinding?.isApplied == true) {
      final result =
          identityActionBindingService.alreadyApplied(existingBinding!);
      return PendingConversationResolution(
        _bindingMessage(result.status),
        identityActionBindingResult: result,
      );
    }
    final binding = identityActionBindingService.create(
      accountScopeId: request.scope.accountId,
      continuation: continuation,
    );
    if (_state.pendingAction != null) {
      final result = identityActionBindingService.invalid(
        binding: binding,
        diagnosticCode: 'pending_action_exists',
      );
      return PendingConversationResolution(
        'Une autre confirmation est déjà en attente.',
        identityActionBindingResult: result,
      );
    }
    final applicationService = identityApplicationService;
    if (applicationService == null) {
      final result = identityActionBindingService.invalid(
        binding: binding,
        diagnosticCode: 'identity_service_unavailable',
      );
      return PendingConversationResolution(
        'L’identité ne peut pas être vérifiée pour le moment.',
        identityActionBindingResult: result,
      );
    }

    final applicationResult = await applicationService.resolve(request);
    final creationService = identityCreationService;
    if (applicationResult.status == IdentityApplicationStatus.notFound &&
        creationRequest != null &&
        creationService != null &&
        creationRequest.supports(request)) {
      final pending = creationService.propose(
        applicationResult: applicationResult,
        request: creationRequest,
        actionBinding: binding,
      );
      final bindingResult =
          identityActionBindingService.pendingCreation(binding);
      _state = _state.copyWith(
        phase: ConversationPhase.awaitingActionConfirmation,
        pendingAction: PendingConversationAction.identityCreation(pending),
      );
      return PendingConversationResolution(
        creationService.question(pending),
        identityActionBindingResult: bindingResult,
      );
    }
    var bindingResult = identityActionBindingService.fromApplicationResult(
      binding: binding,
      applicationResult: applicationResult,
    );
    if (bindingResult.status !=
        IdentityActionBindingStatus.pendingClarification) {
      if (bindingResult.status == IdentityActionBindingStatus.attached) {
        _identityActionBindings[bindingKey] = bindingResult.binding;
      }
      return PendingConversationResolution(
        _bindingMessage(bindingResult.status),
        identityActionBindingResult: bindingResult,
      );
    }

    var pending = identityClarificationService.create(
      applicationResult: applicationResult,
      request: request,
      actionBinding: binding,
    );
    final linkedBinding = identityActionBindingService.linkClarification(
      binding: binding,
      clarificationId: pending.clarificationId,
    );
    pending = pending.withActionBinding(linkedBinding);
    bindingResult = identityActionBindingService.fromApplicationResult(
      binding: linkedBinding,
      applicationResult: applicationResult,
    );
    _state = _state.copyWith(
      phase: ConversationPhase.awaitingActionConfirmation,
      pendingAction: PendingConversationAction.identityClarification(pending),
    );
    return PendingConversationResolution(
      identityClarificationService.question(pending),
      identityActionBindingResult: bindingResult,
    );
  }

  Future<PendingConversationResolution?> resolvePendingIdentityClarification({
    required String answer,
    DateTime? referenceDate,
  }) async {
    final pendingAction = _state.pendingAction;
    if (pendingAction == null ||
        pendingAction.type !=
            PendingConversationActionType.identityClarification) {
      return null;
    }
    final pending = pendingAction.identityClarification!;
    final result = identityClarificationService.process(
      pending: pending,
      answer: answer,
      referenceDate: referenceDate,
    );
    final actionBinding = pending.actionBinding;
    final bindingResult = actionBinding == null
        ? null
        : identityActionBindingService.applyClarification(
            binding: actionBinding,
            clarificationResult: result,
            bindingId: actionBinding.bindingId,
            clarificationId: pending.clarificationId,
          );
    if (bindingResult?.status == IdentityActionBindingStatus.attached) {
      _identityActionBindings[_identityBindingKey(
        accountScopeId: actionBinding!.accountScopeId,
        continuation: actionBinding.continuation,
      )] = bindingResult!.binding;
    }
    if (result.status != IdentityClarificationStatus.stillAmbiguous) {
      _clearPendingAction();
    }
    return _resumeIdentityContinuation(PendingConversationResolution(
      result.followUpMessage,
      identityClarificationResult: result,
      identityActionBindingResult: bindingResult,
    ));
  }

  Future<PendingConversationResolution?> resolvePendingIdentityCreation({
    required String answer,
    DateTime? referenceDate,
  }) async {
    final pendingAction = _state.pendingAction;
    final service = identityCreationService;
    if (pendingAction == null ||
        pendingAction.type != PendingConversationActionType.identityCreation ||
        service == null) {
      return null;
    }
    if (_isResolvingPendingAction) return null;
    _isResolvingPendingAction = true;
    _state = _state.copyWith(phase: ConversationPhase.executingAction);
    try {
      final result = await service.process(
        pending: pendingAction.identityCreation!,
        answer: answer,
        referenceDate: referenceDate,
      );
      final actionBinding = pendingAction.identityCreation!.actionBinding;
      final bindingResult = actionBinding == null
          ? null
          : identityActionBindingService.applyCreation(
              binding: actionBinding,
              creationResult: result,
            );
      if (bindingResult?.status == IdentityActionBindingStatus.attached) {
        _identityActionBindings[_identityBindingKey(
          accountScopeId: actionBinding!.accountScopeId,
          continuation: actionBinding.continuation,
        )] = bindingResult!.binding;
      }
      if (result.status != IdentityCreationStatus.stillPending &&
          result.status != IdentityCreationStatus.repositoryFailure) {
        _clearPendingAction();
      } else {
        _state = _state.copyWith(
          phase: ConversationPhase.awaitingActionConfirmation,
        );
      }
      return _resumeIdentityContinuation(PendingConversationResolution(
        result.followUpMessage,
        identityCreationResult: result,
        identityActionBindingResult: bindingResult,
      ));
    } finally {
      _isResolvingPendingAction = false;
    }
  }

  PendingConversationResolution _resumeIdentityContinuation(
    PendingConversationResolution resolution,
  ) {
    final bindingResult = resolution.identityActionBindingResult;
    if (bindingResult == null) return resolution;
    final draft = _eventIdentityDrafts[bindingResult.actionDraftId];
    if (draft == null) {
      return _resumeEventParticipantMutation(resolution, bindingResult);
    }

    if (bindingResult.status == IdentityActionBindingStatus.attached) {
      _eventIdentityDrafts.remove(bindingResult.actionDraftId);
      setPendingEventConfirmation(
        draft.event,
        participant: draft.participant,
        participantIdentityEntityId: bindingResult.resolvedEntityId,
      );
      final prefix = resolution.identityCreationResult?.status ==
                  IdentityCreationStatus.created ||
              resolution.identityClarificationResult?.status ==
                  IdentityClarificationStatus.resolved
          ? '${resolution.message}\n\n'
          : '';
      return PendingConversationResolution(
        '$prefix${draft.confirmationMessage}',
        identityCreationResult: resolution.identityCreationResult,
        identityClarificationResult: resolution.identityClarificationResult,
        identityActionBindingResult: bindingResult,
      );
    }

    if (bindingResult.status == IdentityActionBindingStatus.cancelled ||
        bindingResult.status == IdentityActionBindingStatus.expired ||
        bindingResult.status == IdentityActionBindingStatus.invalid ||
        bindingResult.status == IdentityActionBindingStatus.alreadyApplied) {
      _eventIdentityDrafts.remove(bindingResult.actionDraftId);
    }
    return resolution;
  }

  PendingConversationResolution _resumeEventParticipantMutation(
    PendingConversationResolution resolution,
    IdentityActionBindingResult bindingResult,
  ) {
    final draft = _eventParticipantMutationDrafts[bindingResult.actionDraftId];
    if (draft == null) return resolution;
    if (bindingResult.status == IdentityActionBindingStatus.attached) {
      _eventParticipantMutationDrafts.remove(bindingResult.actionDraftId);
      final confirmation = _beginEventMutationConfirmation(
        request: draft.request,
        original: draft.original,
        participantIdentityEntityId: bindingResult.resolvedEntityId,
      );
      final prefix = resolution.identityCreationResult?.status ==
                  IdentityCreationStatus.created ||
              resolution.identityClarificationResult?.status ==
                  IdentityClarificationStatus.resolved
          ? '${resolution.message}\n\n'
          : '';
      return PendingConversationResolution(
        '$prefix${confirmation.message}',
        diagnosticCode: confirmation.diagnosticCode,
        identityCreationResult: resolution.identityCreationResult,
        identityClarificationResult: resolution.identityClarificationResult,
        identityActionBindingResult: bindingResult,
      );
    }
    if (bindingResult.status == IdentityActionBindingStatus.cancelled ||
        bindingResult.status == IdentityActionBindingStatus.expired ||
        bindingResult.status == IdentityActionBindingStatus.invalid ||
        bindingResult.status == IdentityActionBindingStatus.alreadyApplied) {
      _eventParticipantMutationDrafts.remove(bindingResult.actionDraftId);
    }
    return resolution;
  }

  Future<PendingConversationResolution> beginEventMutation(
    EventMutationRequest request,
  ) async {
    if (_state.pendingAction != null) {
      return const PendingConversationResolution(
        'Une autre confirmation est déjà en attente.',
        diagnosticCode: 'pending_action_exists',
      );
    }
    final selection = await eventConversationMutationService.select(request);
    switch (selection.status) {
      case EventTargetSelectionStatus.notFound:
        return const PendingConversationResolution(
          'Je ne trouve pas cet événement. Peux-tu préciser le titre, '
          'la date ou l’heure ?',
          diagnosticCode: 'event_target_not_found',
        );
      case EventTargetSelectionStatus.invalid:
        return const PendingConversationResolution(
          'Cet événement ne peut pas être modifié de façon sûre.',
          diagnosticCode: 'event_target_invalid',
        );
      case EventTargetSelectionStatus.ambiguous:
        final now = _clock().toUtc();
        final pending = PendingEventTargetClarification(
          clarificationId: _actionDraftIdGenerator.generate(),
          request: request,
          candidates: selection.candidates,
          createdAt: now,
          expiresAt: now.add(const Duration(minutes: 15)),
        );
        _state = _state.copyWith(
          phase: ConversationPhase.awaitingActionConfirmation,
          pendingAction:
              PendingConversationAction.eventTargetClarification(pending),
        );
        return PendingConversationResolution(
          _eventTargetQuestion(pending),
          diagnosticCode: selection.diagnosticCode,
        );
      case EventTargetSelectionStatus.selected:
        return _continueSelectedEventMutation(
          request: request,
          original: selection.selected!,
        );
    }
  }

  Future<PendingConversationResolution?> resolvePendingEventMutation({
    required String answer,
  }) async {
    final pending = _state.pendingAction;
    if (pending == null) return null;
    if (pending.type ==
        PendingConversationActionType.eventTargetClarification) {
      final clarification = pending.eventTargetClarification!;
      if (clarification.isExpiredAt(_clock().toUtc())) {
        _clearPendingAction();
        return const PendingConversationResolution(
          'Cette sélection a expiré. Reformule ta demande.',
          diagnosticCode: 'event_target_clarification_expired',
        );
      }
      final classified = answerClassifier.classify(answer);
      if (classified == ConversationAnswer.negative) {
        _clearPendingAction();
        return const PendingConversationResolution(
          'D’accord, je ne modifie aucun événement.',
          diagnosticCode: 'event_target_clarification_cancelled',
        );
      }
      final index = _choiceIndex(answer, clarification.candidates.length);
      if (index == null) {
        return const PendingConversationResolution(
          'Indique simplement le numéro de l’événement, ou réponds non.',
          diagnosticCode: 'event_target_clarification_ambiguous',
        );
      }
      _clearPendingAction();
      return await _continueSelectedEventMutation(
        request: clarification.request,
        original: clarification.candidates[index],
      );
    }
    if (pending.type !=
        PendingConversationActionType.eventMutationConfirmation) {
      return null;
    }
    final confirmation = pending.eventMutationConfirmation!;
    if (confirmation.isExpiredAt(_clock().toUtc())) {
      _clearPendingAction();
      return const PendingConversationResolution(
        'Cette modification a expiré. Aucun événement n’a été modifié.',
        diagnosticCode: 'event_mutation_expired',
      );
    }
    final classified = answerClassifier.classify(answer);
    if (classified == ConversationAnswer.ambiguous) {
      return const PendingConversationResolution(
        'Réponds simplement oui pour modifier cet événement, ou non pour annuler.',
        diagnosticCode: 'event_mutation_confirmation_ambiguous',
      );
    }
    if (classified == ConversationAnswer.negative) {
      _clearPendingAction();
      return const PendingConversationResolution(
        'D’accord, je ne modifie pas cet événement.',
        diagnosticCode: 'event_mutation_cancelled',
      );
    }
    if (_isResolvingPendingAction) return null;
    _isResolvingPendingAction = true;
    _state = _state.copyWith(phase: ConversationPhase.executingAction);
    try {
      EventParticipantMutationIntent participantIntent =
          const PreserveEventParticipant();
      if (confirmation.request.operation ==
          EventMutationOperation.removeParticipant) {
        participantIntent = const RemoveEventParticipant();
      } else if (confirmation.request.operation ==
          EventMutationOperation.replaceParticipant) {
        final scope = identityAccountScope;
        final validator = eventParticipantIdentityValidationService;
        final entityId = confirmation.participantIdentityEntityId;
        final participant = confirmation.request.participant;
        if (scope == null ||
            validator == null ||
            entityId == null ||
            participant == null) {
          _state = _state.copyWith(
            phase: ConversationPhase.awaitingActionConfirmation,
          );
          return const PendingConversationResolution(
            'Le nouveau participant ne peut pas être vérifié. '
            'L’événement reste inchangé.',
            diagnosticCode: 'event_participant_revalidation_unavailable',
          );
        }
        final validation = await validator.validate(
          scope: scope,
          entityId: entityId,
          participant: participant,
        );
        if (validation.status !=
            EventParticipantIdentityValidationStatus.valid) {
          _state = _state.copyWith(
            phase: ConversationPhase.awaitingActionConfirmation,
          );
          return PendingConversationResolution(
            'Le nouveau participant ne peut pas être vérifié. '
            'L’événement reste inchangé.',
            diagnosticCode: validation.diagnosticCode,
          );
        }
        participantIntent = ReplaceEventParticipant(validation.link!);
      }
      final result = await eventConversationMutationService.execute(
        original: confirmation.original,
        proposed: confirmation.proposed,
        participantIntent: participantIntent,
      );
      if (result.status == EventMutationExecutionStatus.updated) {
        _clearPendingAction();
        return const PendingConversationResolution(
          'C’est fait, l’événement a été modifié.',
          diagnosticCode: 'event_mutation_updated',
        );
      }
      _clearPendingAction();
      final message = result.status == EventMutationExecutionStatus.conflict
          ? 'Je n’ai pas modifié l’événement, car le nouveau créneau est en conflit.'
          : 'L’événement a changé ou n’est plus disponible. Je ne l’ai pas modifié.';
      return PendingConversationResolution(
        message,
        diagnosticCode: result.diagnosticCode,
      );
    } finally {
      _isResolvingPendingAction = false;
    }
  }

  Future<PendingConversationResolution> _continueSelectedEventMutation({
    required EventMutationRequest request,
    required EventModel original,
  }) async {
    if (request.operation != EventMutationOperation.update) {
      if (original.participantIdentity == null) {
        return const PendingConversationResolution(
          'Cet événement n’a pas de participant lié. '
          'L’ajout d’un participant n’est pas disponible dans ce parcours.',
          diagnosticCode: 'event_participant_mutation_requires_existing_link',
        );
      }
      final scope = identityAccountScope;
      if (scope == null ||
          original.participantIdentity!.accountScopeId != scope.accountId) {
        return const PendingConversationResolution(
          'Le participant ne peut pas être vérifié pour le moment.',
          diagnosticCode: 'event_participant_identity_scope_mismatch',
        );
      }
    }
    if (request.operation == EventMutationOperation.replaceParticipant) {
      final participant = request.participant!;
      final scope = identityAccountScope!;
      final draftId = _actionDraftIdGenerator.generate();
      _eventParticipantMutationDrafts[draftId] =
          PendingEventParticipantMutationDraft(
        actionDraftId: draftId,
        request: request,
        original: original,
      );
      const source = EntitySource(type: EntitySourceType.user);
      final resolution = await beginIdentityActionBinding(
        request: IdentityResolutionRequest(
          scope: scope,
          reference: EntityReference.text(
            value: participant.label,
            kind: EntityReferenceKind.genericLabel,
            expectedType: EntityType.person,
            source: source,
          ),
        ),
        continuation: IdentityActionContinuation(
          actionKind: IdentityActionKind.event,
          actionDraftId: draftId,
          target: IdentityActionTarget.eventParticipant,
        ),
        creationRequest: IdentityCreationRequest(
          scope: scope,
          entityType: EntityType.person,
          canonicalLabel: participant.label,
          source: source,
        ),
      );
      return _resumeIdentityContinuation(resolution);
    }
    return _beginEventMutationConfirmation(
      request: request,
      original: original,
    );
  }

  PendingConversationResolution _beginEventMutationConfirmation({
    required EventMutationRequest request,
    required EventModel original,
    String? participantIdentityEntityId,
  }) {
    final proposed = request.operation == EventMutationOperation.update
        ? eventConversationMutationService.propose(
            original,
            request.changes!,
          )
        : original;
    final now = _clock().toUtc();
    final message =
        _eventMutationConfirmationMessage(original, proposed, request);
    _state = _state.copyWith(
      phase: ConversationPhase.awaitingActionConfirmation,
      pendingAction: PendingConversationAction.eventMutationConfirmation(
        PendingEventMutationConfirmation(
          mutationId: _actionDraftIdGenerator.generate(),
          request: request,
          original: original,
          proposed: proposed,
          participantIdentityEntityId: participantIdentityEntityId,
          confirmationMessage: message,
          createdAt: now,
          expiresAt: now.add(const Duration(minutes: 15)),
        ),
      ),
    );
    return PendingConversationResolution(
      message,
      diagnosticCode: 'event_mutation_confirmation_required',
    );
  }

  String _eventTargetQuestion(PendingEventTargetClarification pending) {
    final lines = <String>[
      'J’ai trouvé plusieurs événements. Lequel veux-tu modifier ?'
    ];
    for (var index = 0; index < pending.candidates.length; index++) {
      final event = pending.candidates[index];
      lines.add('${index + 1}. ${event.title} — ${event.date} à ${event.time}');
    }
    return lines.join('\n');
  }

  static int? _choiceIndex(String answer, int length) {
    final match = RegExp(r'\d+').firstMatch(answer.trim());
    if (match == null) return null;
    final value = int.tryParse(match.group(0) ?? '');
    if (value == null || value < 1 || value > length) return null;
    return value - 1;
  }

  static String _eventMutationConfirmationMessage(
      EventModel original, EventModel proposed,
      [EventMutationRequest? request]) {
    if (request?.operation == EventMutationOperation.replaceParticipant) {
      return 'Je vais remplacer le participant de « ${original.title} » '
          'par ${request!.participant!.label}. Confirmer ?';
    }
    if (request?.operation == EventMutationOperation.removeParticipant) {
      return 'Je vais retirer le participant de « ${original.title} ». '
          'L’identité restera enregistrée dans Zelia. Confirmer ?';
    }
    return 'Je vais modifier « ${original.title} » du ${original.date} à '
        '${original.time} vers le ${proposed.date} à ${proposed.time}. '
        'Confirmer ?';
  }

  Future<PendingConversationResolution?> resolvePendingEventConfirmation({
    required String answer,
    required bool Function(String value) isPositiveAnswer,
    required bool Function(String value) isNegativeAnswer,
    required String Function(EventModel event) cancellationMessage,
    required String Function() expectedAnswerMessage,
    required PendingEventExecutor execute,
  }) async {
    final pending = _state.pendingAction;
    if (pending == null ||
        pending.type != PendingConversationActionType.eventConfirmation) {
      return null;
    }

    if (isNegativeAnswer(answer)) {
      _state = _state.copyWith(
        phase: ConversationPhase.idle,
        clearPendingAction: true,
      );
      return PendingConversationResolution(cancellationMessage(pending.event));
    }

    if (!isPositiveAnswer(answer)) {
      return PendingConversationResolution(expectedAnswerMessage());
    }

    if (_isResolvingPendingAction) return null;
    _isResolvingPendingAction = true;
    _state = _state.copyWith(phase: ConversationPhase.executingAction);

    try {
      var event = pending.event;
      final participant = pending.eventParticipant;
      final entityId = pending.participantIdentityEntityId;
      if (participant != null) {
        final scope = identityAccountScope;
        final validator = eventParticipantIdentityValidationService;
        if (scope == null || validator == null || entityId == null) {
          _state = _state.copyWith(
            phase: ConversationPhase.awaitingActionConfirmation,
          );
          return const PendingConversationResolution(
            'Je ne peux pas vérifier le participant pour le moment. '
            'Je n’ai pas ajouté l’événement.',
          );
        }
        final validation = await validator.validate(
          scope: scope,
          entityId: entityId,
          participant: participant,
        );
        if (validation.status !=
            EventParticipantIdentityValidationStatus.valid) {
          _state = _state.copyWith(
            phase: ConversationPhase.awaitingActionConfirmation,
          );
          return PendingConversationResolution(
            'Je ne peux pas vérifier le participant pour le moment. '
            'Je n’ai pas ajouté l’événement.',
            diagnosticCode: validation.diagnosticCode,
          );
        }
        event = event.copyWith(participantIdentity: validation.link);
      }
      final message = await execute(event);
      _state = _state.copyWith(
        phase: ConversationPhase.idle,
        clearPendingAction: true,
      );
      return PendingConversationResolution(message);
    } catch (_) {
      _state = _state.copyWith(
        phase: ConversationPhase.awaitingActionConfirmation,
      );
      rethrow;
    } finally {
      _isResolvingPendingAction = false;
    }
  }

  Future<PendingConversationResolution?> resolvePendingMemoryConfirmation({
    required String answer,
    required DateTime referenceDate,
  }) async {
    final pending = _state.pendingAction;
    if (pending == null ||
        pending.type != PendingConversationActionType.memoryConfirmation) {
      return null;
    }
    final proposalId = pending.proposalId?.trim() ?? '';
    final repository = _repository;
    if (proposalId.isEmpty || repository == null) {
      _clearPendingAction();
      return PendingConversationResolution(memoryCopy.unavailable);
    }
    final answerType = answerClassifier.classify(answer);
    if (answerType == ConversationAnswer.ambiguous) {
      return PendingConversationResolution(memoryCopy.clarification);
    }
    if (_isResolvingPendingAction) return null;
    _isResolvingPendingAction = true;
    _state = _state.copyWith(phase: ConversationPhase.executingAction);

    try {
      final memory = await repository.getById(proposalId);
      if (memory == null) {
        _clearPendingAction();
        return PendingConversationResolution(memoryCopy.unavailable);
      }
      if (memory.validUntil?.isBefore(referenceDate) == true) {
        _clearPendingAction();
        return PendingConversationResolution(memoryCopy.unavailable);
      }
      if (answerType == ConversationAnswer.negative) {
        return await _rejectMemory(
          repository: repository,
          memory: memory,
          referenceDate: referenceDate,
        );
      }
      return await _confirmMemory(
        repository: repository,
        memory: memory,
        referenceDate: referenceDate,
      );
    } catch (_) {
      _state = _state.copyWith(
        phase: ConversationPhase.awaitingActionConfirmation,
      );
      return PendingConversationResolution(memoryCopy.persistenceFailure);
    } finally {
      _isResolvingPendingAction = false;
    }
  }

  Future<ConversationOutcome?> send({
    required ConversationInput input,
    required ConversationActionExecutor executeAction,
  }) async {
    final eventMutationResolution = await resolvePendingEventMutation(
      answer: input.message,
    );
    if (eventMutationResolution != null) {
      return ConversationOutcome(reply: eventMutationResolution.message);
    }
    final creationResolution = await resolvePendingIdentityCreation(
      answer: input.message,
    );
    if (creationResolution != null) {
      return ConversationOutcome(
        reply: creationResolution.message,
        identityCreationResult: creationResolution.identityCreationResult,
        identityActionBindingResult:
            creationResolution.identityActionBindingResult,
      );
    }
    final identityResolution = await resolvePendingIdentityClarification(
      answer: input.message,
    );
    if (identityResolution != null) {
      return ConversationOutcome(
        reply: identityResolution.message,
        identityClarificationResult:
            identityResolution.identityClarificationResult,
        identityActionBindingResult:
            identityResolution.identityActionBindingResult,
      );
    }
    if (_isSending) return null;
    _isSending = true;
    _state = _state.copyWith(
      phase: ConversationPhase.sending,
      currentInstruction: input.message,
    );

    try {
      final builtRequest = await contextProvider.buildRequest(
        message: input.message,
        profile: input.profile,
      );
      final request =
          builtRequest.withSessionGeneration(input.sessionGeneration);
      final memoryContext = contextProvider is MemoryConversationContextProvider
          ? contextProvider as MemoryConversationContextProvider
          : null;
      final userProposal =
          await memoryContext?.proposeUserMemory(input.message);
      if (userProposal != null && _state.pendingAction == null) {
        setPendingMemoryConfirmation(
          userProposal,
          createdAt: DateTime.now(),
        );
        return ConversationOutcome(
          reply: memoryCopy.proposal(userProposal),
          request: request,
        );
      }
      final response = await backend.send(request);
      final epistemic = response.epistemic;
      if (epistemic != null) {
        final envelope = request.context;
        if (envelope == null ||
            !const ConversationGroundingPolicy()
                .validate(
                  contract: epistemic,
                  envelope: envelope,
                  actions: response.actions,
                  sessionGeneration: input.sessionGeneration,
                )
                .isValid) {
          throw ChatBackendMalformedResponseException();
        }
      }
      var reply = response.reply;
      final actionMessages = <String>[];
      final shoppingTitles = <String>[];
      final taskTitles = <String>[];
      final eventTitles = <String>[];
      String? planningTitle;

      for (final rawAction in response.actions) {
        final guarded = ZeliaActionGuardService.guard(rawAction);
        if (!guarded.isAccepted || guarded.action == null) continue;

        final action = guarded.action!;
        final type = action['type']?.toString() ?? '';
        if (type == 'event_mutation' &&
            action['eventMutation'] is EventMutationRequest) {
          final mutation = await beginEventMutation(
            action['eventMutation'] as EventMutationRequest,
          );
          actionMessages.add(mutation.message);
          continue;
        }
        final title = action['title']?.toString() ?? '';
        if (type == 'shopping' && title.isNotEmpty) shoppingTitles.add(title);
        if (type == 'task' && title.isNotEmpty) taskTitles.add(title);
        if (type == 'event' && title.isNotEmpty) eventTitles.add(title);

        final outcome = await executeAction(action);
        if (outcome.message.isNotEmpty) actionMessages.add(outcome.message);
        planningTitle = outcome.planningTitle ?? planningTitle;
      }

      MemoryConfirmationRequest? memoryConfirmation;
      for (final memory in response.memories) {
        final request = memoryContext == null
            ? null
            : await memoryContext.proposeResponseMemory(memory);
        if (memoryContext == null) {
          await contextProvider.saveResponseMemory(memory);
        } else if (memoryConfirmation == null && request != null) {
          memoryConfirmation = request;
        }
      }

      if (actionMessages.isNotEmpty) {
        reply = actionMessages.join('\n\n');
      } else if (response.actions.isNotEmpty) {
        reply = ZeliaResponseBuilder.buildGroupedActionReply(
          shoppingTitles: shoppingTitles,
          taskTitles: taskTitles,
          eventTitles: eventTitles,
          planningTitle: planningTitle,
        );
      }

      if (memoryConfirmation != null &&
          response.actions.isEmpty &&
          _state.pendingAction == null) {
        setPendingMemoryConfirmation(
          memoryConfirmation,
          createdAt: DateTime.now(),
        );
        reply = memoryCopy.proposal(memoryConfirmation);
      }

      return ConversationOutcome(
        reply: reply,
        request: request,
        responseKind: epistemic?.responseKind,
        epistemicClarification: epistemic?.clarification,
      );
    } finally {
      _isSending = false;
      _state = _state.copyWith(
        phase: _state.pendingAction == null
            ? ConversationPhase.idle
            : ConversationPhase.awaitingActionConfirmation,
      );
    }
  }

  MemoryLifecycleRepository? get _repository {
    if (_memoryLifecycleRepository != null) return _memoryLifecycleRepository;
    final provider = contextProvider;
    if (provider is! MemoryConversationContextProvider) return null;
    return (provider as MemoryConversationContextProvider)
        .memoryLifecycleRepository;
  }

  Future<PendingConversationResolution> _confirmMemory({
    required MemoryLifecycleRepository repository,
    required LifeMemoryFact memory,
    required DateTime referenceDate,
  }) async {
    if (memory.lifecycleState == MemoryLifecycleState.active) {
      _clearPendingAction();
      return PendingConversationResolution(memoryCopy.alreadyActive);
    }
    if (memory.lifecycleState != MemoryLifecycleState.proposed &&
        memory.lifecycleState != MemoryLifecycleState.confirmed) {
      _clearPendingAction();
      return PendingConversationResolution(memoryCopy.unavailable);
    }
    final mutations = <MemoryLifecycleMutation>[];
    if (memory.lifecycleState == MemoryLifecycleState.proposed) {
      final confirmation = memoryLifecycleEngine.evaluate(
        MemoryLifecycleCommand(
          action: MemoryLifecycleAction.confirm,
          referenceDate: referenceDate,
          actor: MemoryLifecycleActor.user,
          source: 'conversation_confirmation',
          target: memory,
          targetState: MemoryLifecycleState.proposed,
          reason: 'user_confirmed_memory',
        ),
      );
      if (confirmation.type !=
              MemoryLifecycleDecisionType.confirmExistingProposal ||
          confirmation.mutations.isEmpty) {
        _clearPendingAction();
        return PendingConversationResolution(memoryCopy.unavailable);
      }
      mutations.addAll(confirmation.mutations);
    }
    final activation = memoryLifecycleEngine.evaluate(
      MemoryLifecycleCommand(
        action: MemoryLifecycleAction.activate,
        referenceDate: referenceDate,
        actor: MemoryLifecycleActor.user,
        source: 'conversation_confirmation',
        target: memory,
        targetState: MemoryLifecycleState.confirmed,
        reason: 'confirmed_memory_activated',
      ),
    );
    if (activation.type != MemoryLifecycleDecisionType.createNewMemory ||
        activation.mutations.isEmpty) {
      _clearPendingAction();
      return PendingConversationResolution(memoryCopy.unavailable);
    }
    mutations.addAll(activation.mutations);
    await repository.applyMutations(mutations);
    _clearPendingAction();
    return PendingConversationResolution(memoryCopy.confirmed);
  }

  Future<PendingConversationResolution> _rejectMemory({
    required MemoryLifecycleRepository repository,
    required LifeMemoryFact memory,
    required DateTime referenceDate,
  }) async {
    if (memory.lifecycleState == MemoryLifecycleState.rejected) {
      _clearPendingAction();
      return PendingConversationResolution(memoryCopy.rejected);
    }
    if (memory.lifecycleState != MemoryLifecycleState.proposed) {
      _clearPendingAction();
      return PendingConversationResolution(memoryCopy.unavailable);
    }
    final rejection = memoryLifecycleEngine.evaluate(
      MemoryLifecycleCommand(
        action: MemoryLifecycleAction.reject,
        referenceDate: referenceDate,
        actor: MemoryLifecycleActor.user,
        source: 'conversation_confirmation',
        target: memory,
        targetState: MemoryLifecycleState.proposed,
        reason: 'user_rejected_memory',
      ),
    );
    if (rejection.type != MemoryLifecycleDecisionType.rejectProposal ||
        rejection.mutations.isEmpty) {
      _clearPendingAction();
      return PendingConversationResolution(memoryCopy.unavailable);
    }
    await repository.applyMutations(rejection.mutations);
    _clearPendingAction();
    return PendingConversationResolution(memoryCopy.rejected);
  }

  void _clearPendingAction() {
    _state = _state.copyWith(
      phase: ConversationPhase.idle,
      clearPendingAction: true,
    );
  }

  String _bindingMessage(IdentityActionBindingStatus status) {
    return switch (status) {
      IdentityActionBindingStatus.attached =>
        'L’identité est rattachée au brouillon de l’événement.',
      IdentityActionBindingStatus.pendingClarification =>
        'Une clarification est nécessaire.',
      IdentityActionBindingStatus.pendingCreation =>
        'Une confirmation de création est nécessaire.',
      IdentityActionBindingStatus.cancelled =>
        'Le rattachement de l’identité est annulé.',
      IdentityActionBindingStatus.expired =>
        'Le rattachement de l’identité a expiré.',
      IdentityActionBindingStatus.invalid =>
        'L’identité ne peut pas être rattachée à ce brouillon.',
      IdentityActionBindingStatus.alreadyApplied =>
        'L’identité est déjà rattachée à ce brouillon.',
    };
  }

  String _identityBindingKey({
    required String accountScopeId,
    required IdentityActionContinuation continuation,
  }) {
    return [
      accountScopeId,
      continuation.actionKind.name,
      continuation.actionDraftId,
      continuation.target.name,
    ].join('|');
  }
}
