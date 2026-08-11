import '../models/conversation_models.dart';
import '../models/conversation_reference_resolution.dart';
import '../models/conversation_epistemic_models.dart';
import '../models/action_autonomy_policy.dart';
import '../models/action_confirmation.dart';
import '../models/action_ledger.dart';
import '../models/event_model.dart';
import '../models/event_participant.dart';
import '../models/event_mutation_models.dart';
import '../core/identity/entity_id_generator.dart';
import '../core/identity/entity_reference.dart';
import '../core/identity/entity_types.dart';
import '../models/life_context/memory_context.dart';
import '../models/life_context/life_context_provenance.dart';
import '../models/memory_lifecycle.dart';
import '../models/memory_contradiction.dart';
import '../models/memory_lifecycle_state.dart';
import '../core/identity/uuid_v7_entity_id_generator.dart';
import 'chat_backend_client.dart';
import 'conversation_answer_classifier.dart';
import 'conversation_context_service.dart';
import 'conversation_reference_resolver.dart';
import 'conversation_grounding_policy.dart';
import 'action_autonomy_policy_engine.dart';
import 'action_confirmation_coordinator.dart';
import 'memory_confirmation_copy.dart';
import 'memory_lifecycle_engine.dart';
import 'memory_lifecycle_repository.dart';
import 'memory_pipeline_service.dart';
import 'routine_conversation_service.dart';
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
import 'priority/priority_consultation_intent_detector.dart';
import 'priority/priority_consultation_service.dart';
import 'task_creation_draft_service.dart';
import 'shopping_conversation_intent_detector.dart';
import 'shopping_service.dart';

typedef ConversationActionExecutor = Future<ConversationActionOutcome> Function(
  Map<String, dynamic> action,
);

final class ConversationTaskPersistenceException implements Exception {
  const ConversationTaskPersistenceException();
}

final class ConversationShoppingPersistenceException implements Exception {
  const ConversationShoppingPersistenceException(this.code);

  final String code;
}

typedef PendingEventExecutor = Future<String> Function(EventModel event);
typedef ConversationAutonomyPolicyLoader = Future<ActionAutonomyPolicy>
    Function();

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
  final ConversationReferenceResolver conversationReferenceResolver;
  final DateTime Function() _clock;
  final ConversationAutonomyPolicyLoader? _loadAutonomyPolicy;
  final ActionAutonomyPolicyEngine _autonomyEngine;
  final RoutineConversationService? routineConversationService;
  final PriorityConsultationIntentDetector priorityConsultationIntentDetector;
  final PriorityConsultationService? priorityConsultationService;
  final TaskCreationDraftService taskCreationDraftService;
  final ShoppingConversationIntentDetector shoppingIntentDetector;
  late final ActionConfirmationCoordinator _confirmationCoordinator;

  ConversationState _state = const ConversationState();
  bool _isSending = false;
  bool _isResolvingPendingAction = false;
  ActionAutonomyPolicy? _lastAutonomyPolicy;
  String? _observedAccountScopeId;
  int _confirmationSequence = 0;
  int _sessionGeneration = 0;
  final Map<String, PendingIdentityActionBinding> _identityActionBindings = {};
  final Map<String, PendingEventIdentityDraft> _eventIdentityDrafts = {};
  final Map<String, PendingEventParticipantMutationDraft>
      _eventParticipantMutationDrafts = {};
  final List<ValidatedConversationReference> _validatedReferenceHistory;

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
    this.conversationReferenceResolver = const ConversationReferenceResolver(),
    List<ValidatedConversationReference> validatedReferenceHistory = const [],
    DateTime Function()? clock,
    ConversationAutonomyPolicyLoader? loadAutonomyPolicy,
    ActionAutonomyPolicyEngine autonomyEngine =
        const ActionAutonomyPolicyEngine(),
    this.routineConversationService,
    this.priorityConsultationIntentDetector =
        const PriorityConsultationIntentDetector(),
    PriorityConsultationService? priorityConsultationService,
    this.taskCreationDraftService = const TaskCreationDraftService(),
    this.shoppingIntentDetector = const ShoppingConversationIntentDetector(),
    ActionConfirmationCoordinator? confirmationCoordinator,
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
        _validatedReferenceHistory =
            List<ValidatedConversationReference>.of(validatedReferenceHistory),
        _loadAutonomyPolicy = loadAutonomyPolicy,
        _autonomyEngine = autonomyEngine,
        _clock = clock ?? DateTime.now,
        priorityConsultationService = priorityConsultationService ??
            (contextProvider is PriorityConversationContextProvider
                ? PriorityConsultationService(
                    loadProjection:
                        (contextProvider as PriorityConversationContextProvider)
                            .loadPriorityProjection,
                    clock: clock,
                  )
                : null) {
    _confirmationCoordinator = confirmationCoordinator ??
        ActionConfirmationCoordinator(
          idGenerator: _nextConfirmationId,
          policyLoader: _canonicalPolicy,
          currentAccountScopeId: _confirmationAccountScope,
          now: _clock,
        );
  }

  ConversationState get state => _state;
  List<ValidatedConversationReference> get validatedReferenceHistory =>
      List.unmodifiable(_validatedReferenceHistory);

  void restoreValidatedReferenceHistory(
    List<ValidatedConversationReference> references, {
    required String accountScopeId,
    required DateTime referenceDate,
  }) {
    _validatedReferenceHistory
      ..clear()
      ..addAll(
        references
            .where((item) => item.accountScopeId == accountScopeId)
            .where((item) => item.isValidAt(referenceDate.toUtc()))
            .take(ConversationReferenceResolution.maximumCandidateIds),
      );
  }

  ActionConfirmation? get activeConfirmation =>
      _state.pendingAction?.canonicalConfirmation;
  ActionAutonomyPolicy? get lastAutonomyPolicy => _lastAutonomyPolicy;

  Future<PendingConversationResolution> beginSuggestedEventMove({
    required String eventId,
    required String dateIso,
    required String time,
  }) async {
    final selection =
        await eventConversationMutationService.selectVerifiedIds([eventId]);
    if (selection.status != EventTargetSelectionStatus.selected) {
      return const PendingConversationResolution(
        'Ce rendez-vous n’est plus disponible. Je n’ai rien modifié.',
        diagnosticCode: 'suggested_event_move_target_unavailable',
      );
    }
    final original = selection.selected!;
    return _continueSelectedEventMutation(
      request: EventMutationRequest.update(
        target: EventMutationTarget(
          title: original.title,
          date: original.date,
          time: original.time,
        ),
        changes: EventMutationChanges(date: dateIso, time: time),
      ),
      original: original,
    );
  }

  String _nextConfirmationId() =>
      'confirmation-$_sessionGeneration-${++_confirmationSequence}';

  void invalidateSession() {
    _confirmationCoordinator.invalidateSession(_sessionGeneration + 1);
    _state = const ConversationState();
    _identityActionBindings.clear();
    _eventIdentityDrafts.clear();
    _eventParticipantMutationDrafts.clear();
    _observedAccountScopeId = null;
    _isSending = false;
    _isResolvingPendingAction = false;
  }

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
    final metadata = _pendingMetadata(ActionType.createEvent);
    final mutationId = _actionDraftIdGenerator.generate();
    final targetId =
        event.id?.trim().isNotEmpty == true ? event.id!.trim() : mutationId;
    final scope = ActionConfirmationScope(
      type: ActionConfirmationScopeType.executeExactMutation,
      targetId: targetId,
      operation: 'createEvent',
      expectedRevision: 0,
      fields: [
        ActionConfirmationField(
          key: ActionConfirmationFieldKey.title,
          value: event.title,
        ),
        ActionConfirmationField(
          key: ActionConfirmationFieldKey.date,
          value: event.date,
        ),
        ActionConfirmationField(
          key: ActionConfirmationFieldKey.time,
          value: event.time,
        ),
        ActionConfirmationField(
          key: ActionConfirmationFieldKey.durationMinutes,
          value: event.durationMinutes,
        ),
        ActionConfirmationField(
          key: ActionConfirmationFieldKey.travelGoMinutes,
          value: event.resolvedTravelGoMinutes,
        ),
        ActionConfirmationField(
          key: ActionConfirmationFieldKey.travelBackMinutes,
          value: event.resolvedTravelBackMinutes,
        ),
        ActionConfirmationField(
          key: ActionConfirmationFieldKey.marginMinutes,
          value: event.marginMinutes,
        ),
        ActionConfirmationField(
          key: ActionConfirmationFieldKey.participantId,
          value: participantIdentityEntityId,
        ),
        ActionConfirmationField(
          key: ActionConfirmationFieldKey.recurrenceType,
          value: event.isRecurring ? event.recurringType : null,
        ),
        ActionConfirmationField(
          key: ActionConfirmationFieldKey.recurrenceWeekday,
          value: event.isRecurring ? event.recurringWeekday : null,
        ),
        ActionConfirmationField(
          key: ActionConfirmationFieldKey.recurrenceUntil,
          value: event.isRecurring && event.recurringUntil.isNotEmpty
              ? event.recurringUntil
              : null,
        ),
      ],
    );
    final policy = _lastAutonomyPolicy ??
        ActionAutonomyPolicy.restrictiveDefault(
          accountScopeId: _confirmationAccountScope()!,
          changedAt: _clock().toUtc(),
        );
    final canonical = _confirmationCoordinator.issueWithPolicy(
      ActionConfirmationProposal(
        accountScopeId: policy.accountScopeId,
        sessionGeneration: _sessionGeneration,
        actionPendingId: targetId,
        actionType: ActionType.createEvent,
        actionDomain: ActionLedgerDomain.event,
        actionOrigin: ActionOrigin.structuredContinuation,
        riskLevel: ActionRiskLevel.mutation,
        scope: scope,
        requirements: [
          ActionConfirmationRequirement(
            source: ActionConfirmationRequirementSource.domainRequired,
            code: 'event_creation_confirmation',
            scope: scope.type,
            requiresFreshConfirmation: true,
            requiresSeparateConfirmation: false,
            policyVersionObserved: policy.schemaVersion,
          ),
          if (policy.mode == ActionAutonomyMode.suggestions)
            ActionConfirmationRequirement(
              source:
                  ActionConfirmationRequirementSource.autonomySuggestionsMode,
              code: 'autonomy_suggestions_confirmation',
              scope: scope.type,
              requiresFreshConfirmation: true,
              requiresSeparateConfirmation: false,
              policyVersionObserved: policy.schemaVersion,
            ),
        ],
        mutationId: mutationId,
        policyMode: policy.mode,
        policyVersion: policy.schemaVersion,
        presentation: ActionConfirmationPresentation(
          title: 'Confirmer le rendez-vous',
          summary: 'Ajouter « ${event.title} » à l’agenda.',
          consequence: 'L’agenda sera modifié après une dernière vérification.',
        ),
        provenance: 'conversation_event_creation',
      ),
      policy: policy,
    );
    _state = _state.copyWith(
      phase: ConversationPhase.awaitingActionConfirmation,
      pendingAction: PendingConversationAction.eventConfirmation(
        event,
        eventParticipant: participant,
        participantIdentityEntityId: participantIdentityEntityId,
        canonicalConfirmation: canonical.confirmation,
        autonomyMetadata: metadata,
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
    final policy = _lastAutonomyPolicy ??
        ActionAutonomyPolicy.restrictiveDefault(
          accountScopeId: _confirmationAccountScope()!,
          changedAt: _clock().toUtc(),
        );
    final scope = ActionConfirmationScope(
      type: ActionConfirmationScopeType.confirmMemoryConsent,
      targetId: request.memoryId?.trim().isNotEmpty == true
          ? request.memoryId!.trim()
          : proposalId,
      operation: request.action.name,
      expectedRevision: 0,
      fields: const [],
    );
    final canonical = _confirmationCoordinator.issueWithPolicy(
      ActionConfirmationProposal(
        accountScopeId: policy.accountScopeId,
        sessionGeneration: _sessionGeneration,
        actionPendingId: proposalId,
        actionType: ActionType.confirmMemory,
        actionDomain: ActionLedgerDomain.memory,
        actionOrigin: ActionOrigin.structuredContinuation,
        riskLevel: ActionRiskLevel.sensitiveMutation,
        scope: scope,
        requirements: [
          ActionConfirmationRequirement(
            source: ActionConfirmationRequirementSource.memoryPolicy,
            code: 'memory_policy_confirmation',
            scope: scope.type,
            requiresFreshConfirmation: true,
            requiresSeparateConfirmation: false,
            policyVersionObserved: policy.schemaVersion,
          ),
          if (request.sensitivity.name == 'sensitive')
            ActionConfirmationRequirement(
              source: ActionConfirmationRequirementSource.healthPolicy,
              code: 'sensitive_memory_confirmation',
              scope: scope.type,
              requiresFreshConfirmation: true,
              requiresSeparateConfirmation: true,
              policyVersionObserved: policy.schemaVersion,
            ),
        ],
        mutationId: proposalId,
        policyMode: policy.mode,
        policyVersion: policy.schemaVersion,
        presentation: ActionConfirmationPresentation(
          title: 'Confirmer la mémoire',
          summary: request.prompt.trim().isEmpty
              ? 'Confirmer cette proposition de mémoire.'
              : request.prompt.trim(),
          consequence: request.consequence.trim().isEmpty
              ? 'La mémoire ne sera modifiée qu’après confirmation.'
              : request.consequence.trim(),
          allowPostpone: true,
        ),
        provenance: 'conversation_memory_confirmation',
      ),
      policy: policy,
    );
    _state = _state.copyWith(
      phase: ConversationPhase.awaitingActionConfirmation,
      pendingAction: PendingConversationAction.memoryConfirmation(
        proposalId: proposalId,
        createdAt: createdAt,
        expectedMemoryAction: request.action,
        memoryContradiction: request.contradictionCandidate,
        memoryReplacementAction: request.replacementPendingAction,
        canonicalConfirmation: canonical.confirmation,
        autonomyMetadata: _pendingMetadata(ActionType.confirmMemory),
      ),
    );
  }

  Future<bool> restorePendingMemoryReplacement({
    required String accountScopeId,
    required String logicalRequestId,
    required DateTime restoredAt,
  }) async {
    if (_state.pendingAction != null) return false;
    final repository = _repository;
    if (repository is! MemoryReplacementPendingRepository) return false;
    final action = await (repository as MemoryReplacementPendingRepository)
        .findPendingReplacement(
      accountScopeId: accountScopeId,
      logicalRequestId: logicalRequestId,
    );
    if (action == null ||
        action.state == MemoryReplacementActionState.declined ||
        action.state == MemoryReplacementActionState.conflict ||
        action.state == MemoryReplacementActionState.cancelled) {
      return false;
    }
    if (action.state == MemoryReplacementActionState.executed) return true;
    if (action.state == MemoryReplacementActionState.acceptedPendingExecution) {
      final result = await (repository as MemoryReplacementPendingRepository)
          .executeAcceptedMemoryReplacement(
        action: action,
        accountScopeId: accountScopeId,
        referenceDate: restoredAt,
      );
      return result.isSuccess;
    }
    setPendingMemoryConfirmation(
      MemoryConfirmationRequest(
        action: MemoryLifecycleAction.replace,
        proposalId: action.proposedMemoryId,
        memoryId: action.existingMemoryId,
        prompt: 'Une information déjà mémorisée semble différente de celle que '
            'tu viens d’indiquer. Veux-tu enregistrer la nouvelle '
            'information à la place de l’ancienne ?',
        changeType: 'memoryReplacementConfirmation',
        sensitivity: LifeContextSensitivity.standard,
        consequence:
            'Aucune mémoire ne sera remplacée avant exécution sécurisée.',
        replacementPendingAction: action,
      ),
      createdAt: restoredAt,
    );
    return _state.pendingAction != null;
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
      pendingAction: PendingConversationAction.identityClarification(
        pending,
        autonomyMetadata: _pendingMetadata(ActionType.linkIdentity),
      ),
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
    _observedAccountScopeId = request.scope.accountId;
    final pending = service.propose(
      applicationResult: applicationResult,
      request: request,
    );
    final canonical = _issueIdentityCreationConfirmation(
      pending: pending,
      accountScopeId: request.scope.accountId,
    );
    _state = _state.copyWith(
      phase: ConversationPhase.awaitingActionConfirmation,
      pendingAction: PendingConversationAction.identityCreation(
        pending,
        canonicalConfirmation: canonical,
        autonomyMetadata: _pendingMetadata(ActionType.createIdentity),
      ),
    );
    return PendingConversationResolution(service.question(pending));
  }

  ActionConfirmation _issueIdentityCreationConfirmation({
    required PendingIdentityCreation pending,
    required String accountScopeId,
  }) {
    final service = identityCreationService!;
    _observedAccountScopeId = accountScopeId;
    final policy = _lastAutonomyPolicy ??
        ActionAutonomyPolicy.restrictiveDefault(
          accountScopeId: accountScopeId,
          changedAt: _clock().toUtc(),
        );
    final scope = ActionConfirmationScope(
      type: ActionConfirmationScopeType.confirmIdentityLink,
      targetId: pending.entityId,
      operation: 'createIdentity',
      expectedRevision: 0,
      fields: const [],
    );
    final canonical = _confirmationCoordinator.issueWithPolicy(
      ActionConfirmationProposal(
        accountScopeId: accountScopeId,
        sessionGeneration: _sessionGeneration,
        actionPendingId: pending.proposalId,
        actionType: ActionType.createIdentity,
        actionDomain: ActionLedgerDomain.identity,
        actionOrigin: ActionOrigin.structuredContinuation,
        riskLevel: ActionRiskLevel.sensitiveMutation,
        scope: scope,
        requirements: [
          ActionConfirmationRequirement(
            source: ActionConfirmationRequirementSource.identityPolicy,
            code: 'identity_creation_confirmation',
            scope: scope.type,
            requiresFreshConfirmation: true,
            requiresSeparateConfirmation: true,
            policyVersionObserved: policy.schemaVersion,
          ),
          ActionConfirmationRequirement(
            source: ActionConfirmationRequirementSource.sensitiveMutation,
            code: 'sensitive_identity_confirmation',
            scope: scope.type,
            requiresFreshConfirmation: true,
            requiresSeparateConfirmation: true,
            policyVersionObserved: policy.schemaVersion,
          ),
        ],
        mutationId: pending.proposalId,
        policyMode: policy.mode,
        policyVersion: policy.schemaVersion,
        presentation: ActionConfirmationPresentation(
          title: 'Confirmer l’identité',
          summary: service.question(pending),
          consequence: 'Une identité distincte sera créée.',
        ),
        provenance: 'conversation_identity_creation',
      ),
      policy: policy,
    );
    return canonical.confirmation;
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
    final referenceResolution =
        conversationReferenceResolver.fromIdentityApplication(
      application: applicationResult,
      referenceType: _identityReferenceType(request.reference),
      source: _identityReferenceSource(request.reference),
      expectedType: request.reference.expectedType,
    );
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
      final canonical = _issueIdentityCreationConfirmation(
        pending: pending,
        accountScopeId: request.scope.accountId,
      );
      _state = _state.copyWith(
        phase: ConversationPhase.awaitingActionConfirmation,
        pendingAction: PendingConversationAction.identityCreation(
          pending,
          canonicalConfirmation: canonical,
          autonomyMetadata: _pendingMetadata(ActionType.createIdentity),
        ),
      );
      return PendingConversationResolution(
        creationService.question(pending),
        identityActionBindingResult: bindingResult,
        referenceResolution: referenceResolution,
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
        referenceResolution: referenceResolution,
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
      pendingAction: PendingConversationAction.identityClarification(
        pending,
        autonomyMetadata: _pendingMetadata(ActionType.linkIdentity),
      ),
    );
    return PendingConversationResolution(
      identityClarificationService.question(pending),
      identityActionBindingResult: bindingResult,
      referenceResolution: referenceResolution,
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
    if (answerClassifier.classify(answer) != ConversationAnswer.negative) {
      final authorization = await _authorizeConfirmed(ActionType.linkIdentity);
      if (authorization != null) {
        return PendingConversationResolution(
          authorization,
          diagnosticCode: 'identity_blocked_by_autonomy',
        );
      }
    }
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
    final canonical = pendingAction.canonicalConfirmation;
    if (canonical == null) {
      _clearPendingAction();
      return const PendingConversationResolution(
        'Cette confirmation n’est plus valide. Reformule ta demande.',
        diagnosticCode: 'canonical_identity_confirmation_missing',
      );
    }
    final answerType = answerClassifier.classify(answer);
    _isResolvingPendingAction = true;
    _state = _state.copyWith(phase: ConversationPhase.executingAction);
    try {
      if (answerType != ConversationAnswer.negative) {
        final authorization =
            await _authorizeConfirmed(ActionType.createIdentity);
        if (authorization != null) {
          _state = _state.copyWith(
            phase: ConversationPhase.awaitingActionConfirmation,
          );
          return PendingConversationResolution(
            authorization,
            diagnosticCode: 'identity_blocked_by_autonomy',
          );
        }
      }
      if (answerType == ConversationAnswer.positive) {
        final consumed = await _confirmationCoordinator.respond(
          response: ActionConfirmationResponse(
            responseId: _confirmationResponseId(
              canonical,
              ActionConfirmationResponseChoice.accept,
            ),
            confirmationId: canonical.confirmationId,
            sessionGeneration: _sessionGeneration,
            respondedAt: (referenceDate ?? _clock()).toUtc(),
            choice: ActionConfirmationResponseChoice.accept,
            actionFingerprint: canonical.actionFingerprint,
          ),
          currentSessionGeneration: _sessionGeneration,
          c3Validator: (_) => true,
          domainValidator: (_) => true,
          revisionValidator: (_) => true,
        );
        if (!consumed.dispatchAllowed) {
          _state = _state.copyWith(
            phase: ConversationPhase.awaitingActionConfirmation,
          );
          return PendingConversationResolution(
            consumed.type == ActionConfirmationResultType.blockedByPolicy
                ? 'Les actions sont actuellement en pause.'
                : 'Cette confirmation n’est plus valide. Reformule ta demande.',
            diagnosticCode: consumed.reasonCode,
          );
        }
      } else if (answerType == ConversationAnswer.negative) {
        await _confirmationCoordinator.respond(
          response: ActionConfirmationResponse(
            responseId: _confirmationResponseId(
              canonical,
              ActionConfirmationResponseChoice.reject,
            ),
            confirmationId: canonical.confirmationId,
            sessionGeneration: _sessionGeneration,
            respondedAt: (referenceDate ?? _clock()).toUtc(),
            choice: ActionConfirmationResponseChoice.reject,
            actionFingerprint: canonical.actionFingerprint,
          ),
          currentSessionGeneration: _sessionGeneration,
          c3Validator: (_) => true,
          domainValidator: (_) => true,
          revisionValidator: (_) => true,
        );
      }
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
      if (result.status == IdentityCreationStatus.created) {
        _confirmationCoordinator.complete(
          canonical.confirmationId,
          completedAt: (referenceDate ?? _clock()).toUtc(),
        );
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
    var referenceSource = ConversationReferenceSource.currentMessage;
    EventTargetSelectionResult selection;
    if (_eventTargetIsImplicit(request)) {
      final historyResolution = conversationReferenceResolver.resolve(
        ConversationReferenceRequest(
          accountScopeId: _confirmationAccountScope()!,
          referenceType: _eventReferenceType(request),
          entityType: ConversationReferenceEntityType.event,
          validatedHistory: _validatedReferenceHistory,
        ),
        referenceDate: _clock().toUtc(),
      );
      if (historyResolution.status ==
              ConversationReferenceResolutionStatus.resolved ||
          historyResolution.status ==
              ConversationReferenceResolutionStatus.ambiguous) {
        selection = await eventConversationMutationService.selectVerifiedIds(
          historyResolution.status ==
                  ConversationReferenceResolutionStatus.resolved
              ? [historyResolution.entityId!]
              : historyResolution.candidateIds,
        );
        referenceSource =
            ConversationReferenceSource.validatedConversationHistory;
      } else {
        return PendingConversationResolution(
          'De quel événement parles-tu ?',
          diagnosticCode: 'event_reference_missing_antecedent',
          referenceResolution: historyResolution,
        );
      }
    } else {
      selection = await eventConversationMutationService.select(request);
    }
    final referenceResolution =
        conversationReferenceResolver.fromEventSelection(
      selection: selection,
      accountScopeId: _confirmationAccountScope()!,
      referenceType: _eventReferenceType(request),
      source: referenceSource,
    );
    switch (selection.status) {
      case EventTargetSelectionStatus.notFound:
        return PendingConversationResolution(
          'Je ne trouve pas cet événement. Peux-tu préciser le titre, '
          'la date ou l’heure ?',
          diagnosticCode: 'event_target_not_found',
          referenceResolution: referenceResolution,
        );
      case EventTargetSelectionStatus.invalid:
        return PendingConversationResolution(
          'Cet événement ne peut pas être modifié de façon sûre.',
          diagnosticCode: 'event_target_invalid',
          referenceResolution: referenceResolution,
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
          pendingAction: PendingConversationAction.eventTargetClarification(
            pending,
            autonomyMetadata: _pendingMetadata(ActionType.updateEvent),
          ),
        );
        return PendingConversationResolution(
          _eventTargetQuestion(pending),
          diagnosticCode: selection.diagnosticCode,
          referenceResolution: referenceResolution,
        );
      case EventTargetSelectionStatus.selected:
        _rememberValidatedEvent(selection.selected!.id!);
        return _withReferenceResolution(
          await _continueSelectedEventMutation(
            request: request,
            original: selection.selected!,
          ),
          referenceResolution,
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
      final presented = clarification.candidates[index];
      final selection = await eventConversationMutationService
          .revalidateClarificationCandidate(
        eventId: presented.id!,
        presented: presented,
        request: clarification.request,
      );
      if (selection.status != EventTargetSelectionStatus.selected) {
        _clearPendingAction();
        return PendingConversationResolution(
          'Cet événement n’est plus disponible. Reformule ta demande.',
          diagnosticCode: selection.diagnosticCode,
          referenceResolution: ConversationReferenceResolution(
            status: ConversationReferenceResolutionStatus.unresolved,
            referenceType: _eventReferenceType(clarification.request),
            entityType: ConversationReferenceEntityType.event,
            source: ConversationReferenceSource.pendingAction,
            reasonCode: ConversationReferenceReasonCode.inactiveOrDeletedEntity,
          ),
        );
      }
      _clearPendingAction();
      final selected = selection.selected!;
      _rememberValidatedEvent(selected.id!);
      final resolution = conversationReferenceResolver.fromEventSelection(
        selection: EventTargetSelectionResult(
          status: EventTargetSelectionStatus.selected,
          selected: selected,
          diagnosticCode: 'event_target_selected_after_clarification',
        ),
        accountScopeId: _confirmationAccountScope()!,
        referenceType: _eventReferenceType(clarification.request),
        source: ConversationReferenceSource.pendingAction,
      );
      return _withReferenceResolution(
        await _continueSelectedEventMutation(
          request: clarification.request,
          original: selected,
        ),
        resolution,
      );
    }
    if (pending.type !=
        PendingConversationActionType.eventMutationConfirmation) {
      return null;
    }
    final confirmation = pending.eventMutationConfirmation!;
    final canonical = pending.canonicalConfirmation;
    if (canonical == null) {
      _clearPendingAction();
      return const PendingConversationResolution(
        'Cette confirmation n’est plus valide. Reformule ta demande.',
        diagnosticCode: 'canonical_event_mutation_confirmation_missing',
      );
    }
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
      await _confirmationCoordinator.respond(
        response: ActionConfirmationResponse(
          responseId: _confirmationResponseId(
            canonical,
            ActionConfirmationResponseChoice.reject,
          ),
          confirmationId: canonical.confirmationId,
          sessionGeneration: _sessionGeneration,
          respondedAt: _clock().toUtc(),
          choice: ActionConfirmationResponseChoice.reject,
          actionFingerprint: canonical.actionFingerprint,
        ),
        currentSessionGeneration: _sessionGeneration,
        c3Validator: (_) => true,
        domainValidator: (_) => true,
        revisionValidator: (_) => true,
      );
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
      final authorization = await _authorizeConfirmed(ActionType.updateEvent);
      if (authorization != null) {
        _state = _state.copyWith(
          phase: ConversationPhase.awaitingActionConfirmation,
        );
        return PendingConversationResolution(authorization);
      }
      final consumed = await _confirmationCoordinator.respond(
        response: ActionConfirmationResponse(
          responseId: _confirmationResponseId(
            canonical,
            ActionConfirmationResponseChoice.accept,
          ),
          confirmationId: canonical.confirmationId,
          sessionGeneration: _sessionGeneration,
          respondedAt: _clock().toUtc(),
          choice: ActionConfirmationResponseChoice.accept,
          actionFingerprint: canonical.actionFingerprint,
        ),
        currentSessionGeneration: _sessionGeneration,
        c3Validator: (_) => true,
        domainValidator: (_) => true,
        revisionValidator: (_) =>
            confirmation.original.eventRevision ==
            canonical.confirmationScope.expectedRevision,
      );
      if (!consumed.dispatchAllowed) {
        _state = _state.copyWith(
          phase: ConversationPhase.awaitingActionConfirmation,
        );
        return PendingConversationResolution(
          consumed.type == ActionConfirmationResultType.blockedByPolicy
              ? 'Les actions sont actuellement en pause.'
              : 'Cette modification a changé. Je dois la préparer à nouveau.',
          diagnosticCode: consumed.reasonCode,
        );
      }
      final result = await eventConversationMutationService.execute(
        original: confirmation.original,
        proposed: confirmation.proposed,
        participantIntent: participantIntent,
      );
      if (result.status == EventMutationExecutionStatus.updated) {
        _confirmationCoordinator.complete(
          canonical.confirmationId,
          completedAt: _clock().toUtc(),
        );
        _clearPendingAction();
        return const PendingConversationResolution(
          'C’est fait, l’événement a été modifié.',
          diagnosticCode: 'event_mutation_updated',
        );
      }
      _clearPendingAction();
      final message = switch (result.status) {
        EventMutationExecutionStatus.conflict =>
          'Je n’ai pas modifié le rendez-vous, car ce créneau n’est plus libre.',
        EventMutationExecutionStatus.verificationUnavailable =>
          'Je n’arrive pas à revérifier ton planning pour le moment. '
              'Je n’ai rien modifié.',
        _ =>
          'L’événement a changé ou n’est plus disponible. Je ne l’ai pas modifié.',
      };
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
    final mutationId = _actionDraftIdGenerator.generate();
    final targetId = original.id?.trim().isNotEmpty == true
        ? original.id!.trim()
        : 'event-${original.date}-${original.time}';
    final scope = ActionConfirmationScope(
      type: ActionConfirmationScopeType.executeExactMutation,
      targetId: targetId,
      operation: request.operation.name,
      expectedRevision: original.eventRevision,
      fields: [
        ActionConfirmationField(
          key: ActionConfirmationFieldKey.date,
          value: proposed.date,
        ),
        ActionConfirmationField(
          key: ActionConfirmationFieldKey.time,
          value: proposed.time,
        ),
        ActionConfirmationField(
          key: ActionConfirmationFieldKey.durationMinutes,
          value: proposed.durationMinutes,
        ),
        ActionConfirmationField(
          key: ActionConfirmationFieldKey.travelGoMinutes,
          value: proposed.resolvedTravelGoMinutes,
        ),
        ActionConfirmationField(
          key: ActionConfirmationFieldKey.travelBackMinutes,
          value: proposed.resolvedTravelBackMinutes,
        ),
        ActionConfirmationField(
          key: ActionConfirmationFieldKey.marginMinutes,
          value: proposed.marginMinutes,
        ),
        ActionConfirmationField(
          key: ActionConfirmationFieldKey.participantId,
          value: participantIdentityEntityId,
        ),
        ActionConfirmationField(
          key: ActionConfirmationFieldKey.recurrenceType,
          value: proposed.isRecurring ? proposed.recurringType : null,
        ),
      ],
    );
    final policy = _lastAutonomyPolicy ??
        ActionAutonomyPolicy.restrictiveDefault(
          accountScopeId: _confirmationAccountScope()!,
          changedAt: now,
        );
    final canonical = _confirmationCoordinator.issueWithPolicy(
      ActionConfirmationProposal(
        accountScopeId: policy.accountScopeId,
        sessionGeneration: _sessionGeneration,
        actionPendingId: mutationId,
        actionType: request.operation ==
                    EventMutationOperation.replaceParticipant ||
                request.operation == EventMutationOperation.removeParticipant
            ? ActionType.modifyParticipant
            : ActionType.updateEvent,
        actionDomain: ActionLedgerDomain.event,
        actionOrigin: ActionOrigin.structuredContinuation,
        riskLevel: request.operation ==
                    EventMutationOperation.replaceParticipant ||
                request.operation == EventMutationOperation.removeParticipant
            ? ActionRiskLevel.sensitiveMutation
            : ActionRiskLevel.mutation,
        scope: scope,
        requirements: [
          ActionConfirmationRequirement(
            source: ActionConfirmationRequirementSource.domainRequired,
            code: 'event_mutation_confirmation',
            scope: scope.type,
            requiresFreshConfirmation: true,
            requiresSeparateConfirmation: false,
            policyVersionObserved: policy.schemaVersion,
          ),
        ],
        mutationId: mutationId,
        policyMode: policy.mode,
        policyVersion: policy.schemaVersion,
        presentation: ActionConfirmationPresentation(
          title: 'Confirmer la modification',
          summary: message,
          consequence:
              'L’événement sera modifié après une dernière vérification.',
        ),
        provenance: 'conversation_event_mutation',
      ),
      policy: policy,
    );
    _state = _state.copyWith(
      phase: ConversationPhase.awaitingActionConfirmation,
      pendingAction: PendingConversationAction.eventMutationConfirmation(
        PendingEventMutationConfirmation(
          mutationId: mutationId,
          request: request,
          original: original,
          proposed: proposed,
          participantIdentityEntityId: participantIdentityEntityId,
          confirmationMessage: message,
          createdAt: now,
          expiresAt: now.add(const Duration(minutes: 15)),
        ),
        canonicalConfirmation: canonical.confirmation,
        autonomyMetadata: _pendingMetadata(ActionType.updateEvent),
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

  static ConversationReferenceType _eventReferenceType(
    EventMutationRequest request,
  ) {
    if (_eventTargetIsImplicit(request)) {
      return ConversationReferenceType.demonstrative;
    }
    final target = request.target;
    if (target.title?.trim().isNotEmpty == true) {
      return ConversationReferenceType.explicitMention;
    }
    if (target.date != null || target.time != null) {
      return ConversationReferenceType.temporalTarget;
    }
    return ConversationReferenceType.demonstrative;
  }

  static bool _eventTargetIsImplicit(EventMutationRequest request) {
    final target = request.target;
    final title = target.title?.trim().toLowerCase();
    return (title == null ||
            const {
              'le',
              'la',
              'lui',
              'celui-ci',
              'celle-ci',
              'celui',
              'celle',
            }.contains(title)) &&
        target.date == null &&
        target.time == null &&
        target.category == null;
  }

  void _rememberValidatedEvent(String eventId) {
    final now = _clock().toUtc();
    _validatedReferenceHistory.removeWhere(
      (item) =>
          !item.isValidAt(now) ||
          item.entityType == ConversationReferenceEntityType.event,
    );
    _validatedReferenceHistory.add(
      ValidatedConversationReference(
        entityId: eventId,
        entityType: ConversationReferenceEntityType.event,
        accountScopeId: _confirmationAccountScope()!,
        validatedAt: now,
        expiresAt: now.add(const Duration(minutes: 15)),
      ),
    );
  }

  static ConversationReferenceType _identityReferenceType(
    EntityReference reference,
  ) =>
      switch (reference.kind) {
        EntityReferenceKind.pronoun => ConversationReferenceType.pronoun,
        EntityReferenceKind.relationalExpression =>
          ConversationReferenceType.possessive,
        _ => ConversationReferenceType.explicitMention,
      };

  static ConversationReferenceSource _identityReferenceSource(
    EntityReference reference,
  ) =>
      reference.kind == EntityReferenceKind.pronoun ||
              reference.conversationTargetEntityId != null
          ? ConversationReferenceSource.pendingAction
          : ConversationReferenceSource.explicitEntityMention;

  static PendingConversationResolution _withReferenceResolution(
    PendingConversationResolution value,
    ConversationReferenceResolution referenceResolution,
  ) =>
      PendingConversationResolution(
        value.message,
        diagnosticCode: value.diagnosticCode,
        identityClarificationResult: value.identityClarificationResult,
        identityActionBindingResult: value.identityActionBindingResult,
        identityCreationResult: value.identityCreationResult,
        referenceResolution: referenceResolution,
      );

  static int? _choiceIndex(String answer, int length) {
    final match = RegExp(r'\d+').firstMatch(answer.trim());
    if (match == null) return null;
    final value = int.tryParse(match.group(0) ?? '');
    if (value == null || value < 1 || value > length) return null;
    return value - 1;
  }

  String _eventMutationConfirmationMessage(
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
    return 'Je te propose de déplacer « ${original.title} » '
        '${_humanEventDate(proposed.date)} à '
        '${_humanEventTime(proposed.time)}. Est-ce que ça te va ?';
  }

  String _humanEventDate(String dateIso) {
    final date = DateTime.tryParse(dateIso);
    if (date == null) return 'le $dateIso';
    final now = _clock().toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final difference = target.difference(today).inDays;
    if (difference == 0) return 'aujourd’hui';
    if (difference == 1) return 'demain';
    return 'le ${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  static String _humanEventTime(String time) {
    final parts = time.split(':');
    if (parts.length != 2) return time;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return time;
    return minute == 0
        ? '$hour h'
        : '$hour h ${minute.toString().padLeft(2, '0')}';
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
    final canonical = pending.canonicalConfirmation;
    if (canonical == null) {
      _clearPendingAction();
      return const PendingConversationResolution(
        'Cette confirmation n’est plus valide. Reformule ta demande.',
        diagnosticCode: 'canonical_event_confirmation_missing',
      );
    }

    if (isNegativeAnswer(answer)) {
      await _confirmationCoordinator.respond(
        response: ActionConfirmationResponse(
          responseId: _confirmationResponseId(
            canonical,
            ActionConfirmationResponseChoice.reject,
          ),
          confirmationId: canonical.confirmationId,
          sessionGeneration: _sessionGeneration,
          respondedAt: _clock().toUtc(),
          choice: ActionConfirmationResponseChoice.reject,
          actionFingerprint: canonical.actionFingerprint,
        ),
        currentSessionGeneration: _sessionGeneration,
        c3Validator: (_) => true,
        domainValidator: (_) => true,
        revisionValidator: (_) => true,
      );
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
      final authorization = await _authorizeConfirmed(ActionType.createEvent);
      if (authorization != null) {
        _state = _state.copyWith(
          phase: ConversationPhase.awaitingActionConfirmation,
        );
        return PendingConversationResolution(authorization);
      }
      final consumed = await _confirmationCoordinator.respond(
        response: ActionConfirmationResponse(
          responseId: _confirmationResponseId(
            canonical,
            ActionConfirmationResponseChoice.accept,
          ),
          confirmationId: canonical.confirmationId,
          sessionGeneration: _sessionGeneration,
          respondedAt: _clock().toUtc(),
          choice: ActionConfirmationResponseChoice.accept,
          actionFingerprint: canonical.actionFingerprint,
        ),
        currentSessionGeneration: _sessionGeneration,
        c3Validator: (_) => true,
        domainValidator: (_) => true,
        revisionValidator: (_) => true,
      );
      if (!consumed.dispatchAllowed) {
        _state = _state.copyWith(
          phase: ConversationPhase.awaitingActionConfirmation,
        );
        return PendingConversationResolution(
          consumed.type == ActionConfirmationResultType.blockedByPolicy
              ? 'Les actions sont actuellement en pause.'
              : 'Cette confirmation n’est plus valide. Reformule ta demande.',
          diagnosticCode: consumed.reasonCode,
        );
      }
      final message = await execute(event);
      _confirmationCoordinator.complete(
        canonical.confirmationId,
        completedAt: _clock().toUtc(),
      );
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
    final canonical = pending.canonicalConfirmation;
    if (canonical == null) {
      _clearPendingAction();
      return PendingConversationResolution(memoryCopy.unavailable);
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
    if (pending.expectedMemoryAction == MemoryLifecycleAction.replace) {
      final durableAction = pending.memoryReplacementAction;
      final replacementRepository = repository;
      if (durableAction == null ||
          replacementRepository is! MemoryReplacementPendingRepository) {
        _clearPendingAction();
        return PendingConversationResolution(memoryCopy.unavailable);
      }
      if (answerType == ConversationAnswer.negative) {
        await (replacementRepository as MemoryReplacementPendingRepository)
            .updatePendingReplacementState(
          action: durableAction,
          state: MemoryReplacementActionState.declined,
          updatedAt: referenceDate,
        );
        _clearPendingAction();
        return const PendingConversationResolution(
          'D’accord, rien n’a été remplacé.',
          diagnosticCode: 'memoryReplacementDeclined',
        );
      }
      MemoryReplacementPendingAction accepted;
      try {
        accepted =
            await (replacementRepository as MemoryReplacementPendingRepository)
                .updatePendingReplacementState(
          action: durableAction,
          state: MemoryReplacementActionState.acceptedPendingExecution,
          updatedAt: referenceDate,
        );
      } catch (_) {
        _state = _state.copyWith(
          phase: ConversationPhase.awaitingActionConfirmation,
        );
        return const PendingConversationResolution(
          'Je n’ai pas pu vérifier le résultat pour le moment. Je réessaierai '
          'sans dupliquer la modification.',
          diagnosticCode: 'memoryReplacementUnavailable',
        );
      }
      final accountScopeId = _confirmationAccountScope();
      if (accountScopeId == null) {
        _state = _state.copyWith(
          phase: ConversationPhase.awaitingActionConfirmation,
        );
        return const PendingConversationResolution(
          'Je n’ai pas pu vérifier le résultat pour le moment. Je réessaierai '
          'sans dupliquer la modification.',
          diagnosticCode: 'memoryReplacementUnavailable',
        );
      }
      final execution =
          await (replacementRepository as MemoryReplacementPendingRepository)
              .executeAcceptedMemoryReplacement(
        action: accepted,
        accountScopeId: accountScopeId,
        referenceDate: referenceDate,
      );
      if (execution.isSuccess) {
        _clearPendingAction();
        return const PendingConversationResolution(
          'C’est mis à jour. Je prendrai désormais en compte la nouvelle '
          'information.',
          diagnosticCode: 'memoryReplacementExecuted',
        );
      }
      if (execution.retryable) {
        _state = _state.copyWith(
          phase: ConversationPhase.awaitingActionConfirmation,
          pendingAction: PendingConversationAction.memoryConfirmation(
            proposalId: accepted.proposedMemoryId,
            createdAt: accepted.createdAt,
            expectedMemoryAction: MemoryLifecycleAction.replace,
            memoryContradiction: pending.memoryContradiction,
            memoryReplacementAction: accepted,
            canonicalConfirmation: pending.canonicalConfirmation,
            autonomyMetadata: pending.autonomyMetadata,
          ),
        );
        return const PendingConversationResolution(
          'Je n’ai pas pu vérifier le résultat pour le moment. Je réessaierai '
          'sans dupliquer la modification.',
          diagnosticCode: 'memoryReplacementUnavailable',
        );
      }
      _clearPendingAction();
      return const PendingConversationResolution(
        'L’information a changé entre-temps. Je préfère la revérifier avec '
        'toi avant de la remplacer.',
        diagnosticCode: 'memoryReplacementConflict',
      );
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
        await _confirmationCoordinator.respond(
          response: ActionConfirmationResponse(
            responseId: _confirmationResponseId(
              canonical,
              ActionConfirmationResponseChoice.reject,
            ),
            confirmationId: canonical.confirmationId,
            sessionGeneration: _sessionGeneration,
            respondedAt: referenceDate.toUtc(),
            choice: ActionConfirmationResponseChoice.reject,
            actionFingerprint: canonical.actionFingerprint,
          ),
          currentSessionGeneration: _sessionGeneration,
          c3Validator: (_) => true,
          domainValidator: (_) => true,
          revisionValidator: (_) => true,
        );
        return await _rejectMemory(
          repository: repository,
          memory: memory,
          referenceDate: referenceDate,
        );
      }
      final authorization = await _authorizeConfirmed(ActionType.confirmMemory);
      if (authorization != null) {
        _state = _state.copyWith(
          phase: ConversationPhase.awaitingActionConfirmation,
        );
        return PendingConversationResolution(authorization);
      }
      final consumed = await _confirmationCoordinator.respond(
        response: ActionConfirmationResponse(
          responseId: _confirmationResponseId(
            canonical,
            ActionConfirmationResponseChoice.accept,
          ),
          confirmationId: canonical.confirmationId,
          sessionGeneration: _sessionGeneration,
          respondedAt: referenceDate.toUtc(),
          choice: ActionConfirmationResponseChoice.accept,
          actionFingerprint: canonical.actionFingerprint,
        ),
        currentSessionGeneration: _sessionGeneration,
        c3Validator: (_) => true,
        domainValidator: (_) =>
            memory.lifecycleState == MemoryLifecycleState.proposed ||
            memory.lifecycleState == MemoryLifecycleState.active,
        revisionValidator: (_) => memory.id == proposalId,
      );
      if (!consumed.dispatchAllowed) {
        return PendingConversationResolution(
          consumed.type == ActionConfirmationResultType.blockedByPolicy
              ? 'Les actions sont actuellement en pause.'
              : memoryCopy.unavailable,
          diagnosticCode: consumed.reasonCode,
        );
      }
      final result = await _confirmMemory(
        repository: repository,
        memory: memory,
        referenceDate: referenceDate,
      );
      _confirmationCoordinator.complete(
        canonical.confirmationId,
        completedAt: referenceDate.toUtc(),
      );
      return result;
    } catch (_) {
      _state = _state.copyWith(
        phase: ConversationPhase.awaitingActionConfirmation,
      );
      return PendingConversationResolution(memoryCopy.persistenceFailure);
    } finally {
      _isResolvingPendingAction = false;
    }
  }

  Future<PendingConversationResolution?> resolvePendingAutonomyConfirmation({
    required String answer,
    required int sessionGeneration,
    required ConversationActionExecutor executeAction,
  }) async {
    final wrapped = _state.pendingAction;
    if (wrapped?.type != PendingConversationActionType.autonomyConfirmation) {
      return null;
    }
    var pending = wrapped!.autonomyPending!;
    var canonical = wrapped.canonicalConfirmation;
    if (canonical == null) {
      _clearPendingAction();
      return const PendingConversationResolution(
        'Cette confirmation n’est plus valide. Reformule ta demande.',
        diagnosticCode: 'canonical_confirmation_missing',
      );
    }
    if (canonical.state == ActionConfirmationState.blockedByPolicy) {
      final currentPolicy = await _canonicalPolicy();
      if (currentPolicy.mode == ActionAutonomyMode.paused) {
        return const PendingConversationResolution(
          'Les actions sont actuellement en pause.',
          diagnosticCode: 'confirmation_blocked_paused',
        );
      }
      final renewed = _confirmationCoordinator.issueWithPolicy(
        _confirmationProposalForPending(pending),
        policy: currentPolicy,
      );
      canonical = renewed.confirmation;
      _state = _state.copyWith(
        phase: ConversationPhase.awaitingActionConfirmation,
        pendingAction: PendingConversationAction.autonomyConfirmation(
          pending.copyWith(
            state: ActionPendingState.awaitingConfirmation,
            hasFreshConfirmation: false,
          ),
          canonical,
        ),
      );
      return const PendingConversationResolution(
        'Le mode d’action a changé. Confirme à nouveau cette modification.',
        diagnosticCode: 'confirmation_reissued_after_policy_change',
      );
    }
    pending.validate();
    if (pending.sessionGeneration != sessionGeneration) {
      _clearPendingAction();
      return const PendingConversationResolution(
        'Cette proposition appartient à une ancienne session. Reformule ta demande.',
        diagnosticCode: 'autonomy_pending_stale_session',
      );
    }
    if (pending.isExpiredAt(_clock().toUtc())) {
      _clearPendingAction();
      return const PendingConversationResolution(
        'Cette proposition a expiré. Reformule ta demande.',
        diagnosticCode: 'autonomy_pending_expired',
      );
    }
    if (pending.state == ActionPendingState.executing ||
        pending.state == ActionPendingState.completed) {
      return const PendingConversationResolution(
        'Cette action a déjà été traitée.',
        diagnosticCode: 'autonomy_pending_duplicate_confirmation',
      );
    }
    final classified = answerClassifier.classify(answer);
    if (pending.state == ActionPendingState.pendingSync) {
      if (classified == ConversationAnswer.negative) {
        _clearPendingAction();
        return const PendingConversationResolution(
          'D’accord, je ne réessaie pas cette création.',
          diagnosticCode: 'autonomy_pending_retry_rejected',
        );
      }
      if (classified != ConversationAnswer.positive) {
        return const PendingConversationResolution(
          'Réponds simplement oui pour réessayer, ou non pour annuler.',
          diagnosticCode: 'autonomy_pending_retry_ambiguous',
        );
      }
      pending = pending.copyWith(
        state: ActionPendingState.executing,
        hasFreshConfirmation: true,
      );
      _state = _state.copyWith(
        phase: ConversationPhase.executingAction,
        pendingAction: PendingConversationAction.autonomyConfirmation(
          pending,
          canonical,
        ),
      );
      try {
        final outcome = await executeAction(_legacyAction(pending));
        _confirmationCoordinator.complete(
          canonical.confirmationId,
          completedAt: _clock().toUtc(),
        );
        _clearPendingAction();
        return PendingConversationResolution(
          outcome.message.isEmpty
              ? pending.actionType == ActionType.addShoppingItem
                  ? 'C’est ajouté à ta liste de courses.'
                  : 'C’est fait.'
              : outcome.message,
          diagnosticCode: 'autonomy_pending_retry_completed',
        );
      } catch (error) {
        _state = _state.copyWith(
          phase: ConversationPhase.awaitingActionConfirmation,
          pendingAction: PendingConversationAction.autonomyConfirmation(
            pending.copyWith(
              state: ActionPendingState.pendingSync,
              hasFreshConfirmation: true,
            ),
            canonical,
          ),
        );
        if (pending.actionType == ActionType.createTask) {
          throw const ConversationTaskPersistenceException();
        }
        if (pending.actionType == ActionType.addShoppingItem) {
          throw ConversationShoppingPersistenceException(
            error is ShoppingPersistenceException
                ? error.code
                : 'shopping_local_persist_failed',
          );
        }
        rethrow;
      }
    }
    if (classified == ConversationAnswer.negative) {
      await _confirmationCoordinator.respond(
        response: ActionConfirmationResponse(
          responseId: _confirmationResponseId(
            canonical,
            ActionConfirmationResponseChoice.reject,
          ),
          confirmationId: canonical.confirmationId,
          sessionGeneration: sessionGeneration,
          respondedAt: _clock().toUtc(),
          choice: ActionConfirmationResponseChoice.reject,
          actionFingerprint: canonical.actionFingerprint,
        ),
        currentSessionGeneration: sessionGeneration,
        c3Validator: (_) => true,
        domainValidator: (_) => true,
        revisionValidator: (_) => true,
      );
      _clearPendingAction();
      return PendingConversationResolution(
        pending.actionType == ActionType.addShoppingItem
            ? 'D’accord, je n’ajoute rien à la liste de courses.'
            : 'D’accord, je ne modifie rien.',
        diagnosticCode: 'autonomy_pending_rejected',
      );
    }
    if (classified != ConversationAnswer.positive) {
      final attempts = pending.attemptCount + 1;
      if (attempts >= ActionPending.maximumAttempts) {
        _clearPendingAction();
        return const PendingConversationResolution(
          'Je n’ai pas reçu de confirmation claire. La proposition est annulée.',
          diagnosticCode: 'autonomy_pending_attempts_exceeded',
        );
      }
      pending = pending.copyWith(attemptCount: attempts);
      _state = _state.copyWith(
        pendingAction: PendingConversationAction.autonomyConfirmation(
          pending,
          canonical,
        ),
      );
      return const PendingConversationResolution(
        'Réponds simplement oui pour confirmer, ou non pour annuler.',
        diagnosticCode: 'autonomy_pending_confirmation_ambiguous',
      );
    }
    final consumed = await _confirmationCoordinator.respond(
      response: ActionConfirmationResponse(
        responseId: _confirmationResponseId(
          canonical,
          ActionConfirmationResponseChoice.accept,
        ),
        confirmationId: canonical.confirmationId,
        sessionGeneration: sessionGeneration,
        respondedAt: _clock().toUtc(),
        choice: ActionConfirmationResponseChoice.accept,
        actionFingerprint: canonical.actionFingerprint,
      ),
      currentSessionGeneration: sessionGeneration,
      c3Validator: (_) => pending.wasGrounded && pending.wasComplete,
      domainValidator: (_) => true,
      revisionValidator: (_) => pending.state != ActionPendingState.completed,
    );
    if (!consumed.dispatchAllowed) {
      pending = pending.copyWith(
        state: consumed.type == ActionConfirmationResultType.blockedByPolicy
            ? ActionPendingState.blockedByPolicy
            : ActionPendingState.expired,
        hasFreshConfirmation: false,
      );
      _state = _state.copyWith(
        phase: ConversationPhase.awaitingActionConfirmation,
        pendingAction: PendingConversationAction.autonomyConfirmation(
          pending,
          consumed.confirmation,
        ),
      );
      return PendingConversationResolution(
        consumed.type == ActionConfirmationResultType.blockedByPolicy
            ? 'Les actions sont actuellement en pause.'
            : 'Cette confirmation n’est plus valide. Reformule ta demande.',
        diagnosticCode: consumed.reasonCode,
      );
    }
    final policy = _lastAutonomyPolicy;
    if (policy == null) {
      return const PendingConversationResolution(
        'Je ne peux pas vérifier le mode d’action pour le moment.',
        diagnosticCode: 'autonomy_policy_unavailable',
      );
    }
    _lastAutonomyPolicy = policy;
    final decision = _autonomyEngine.evaluate(
      policy: policy,
      request: ActionAuthorizationRequest(
        actionType: pending.actionType,
        origin: ActionOrigin.explicitUserConfirmation,
        riskLevel: pending.riskLevel,
        sessionGeneration: sessionGeneration,
        policyVersionObserved: policy.schemaVersion,
        isGrounded: pending.wasGrounded,
        isComplete: pending.wasComplete,
        hasFreshExplicitConfirmation: true,
      ),
      evaluatedAt: _clock(),
    );
    if (!decision.mayExecute) {
      pending = pending.copyWith(
        state: ActionPendingState.blockedByPolicy,
        hasFreshConfirmation: false,
      );
      _state = _state.copyWith(
        phase: ConversationPhase.awaitingActionConfirmation,
        pendingAction: PendingConversationAction.autonomyConfirmation(
          pending,
          consumed.confirmation,
        ),
      );
      return PendingConversationResolution(
        _autonomyMessage(decision),
        diagnosticCode: decision.reasonCode,
      );
    }
    pending = pending.copyWith(
      state: ActionPendingState.executing,
      hasFreshConfirmation: true,
      attemptCount: pending.attemptCount + 1,
    );
    _state = _state.copyWith(
      phase: ConversationPhase.executingAction,
      pendingAction: PendingConversationAction.autonomyConfirmation(
        pending,
        consumed.confirmation,
      ),
    );
    try {
      final outcome = await executeAction(_legacyAction(pending));
      _confirmationCoordinator.complete(
        canonical.confirmationId,
        completedAt: _clock().toUtc(),
      );
      _clearPendingAction();
      return PendingConversationResolution(
        outcome.message.isEmpty
            ? pending.actionType == ActionType.addShoppingItem
                ? 'C’est ajouté à ta liste de courses.'
                : 'C’est fait.'
            : outcome.message,
        diagnosticCode: 'autonomy_pending_completed',
      );
    } catch (error) {
      _state = _state.copyWith(
        phase: ConversationPhase.awaitingActionConfirmation,
        pendingAction: PendingConversationAction.autonomyConfirmation(
          pending.copyWith(
            state: ActionPendingState.pendingSync,
            hasFreshConfirmation: true,
          ),
          consumed.confirmation,
        ),
      );
      if (pending.actionType == ActionType.createTask) {
        throw const ConversationTaskPersistenceException();
      }
      if (pending.actionType == ActionType.addShoppingItem) {
        throw ConversationShoppingPersistenceException(
          error is ShoppingPersistenceException
              ? error.code
              : 'shopping_local_persist_failed',
        );
      }
      rethrow;
    }
  }

  Future<PendingConversationResolution?> resolvePendingShoppingClarification({
    required String answer,
    required int sessionGeneration,
  }) async {
    final wrapped = _state.pendingAction;
    if (wrapped?.type != PendingConversationActionType.shoppingClarification) {
      return null;
    }
    final pending = wrapped!.shoppingClarification!;
    final now = _clock().toUtc();
    if (pending.sessionGeneration != sessionGeneration ||
        pending.isExpiredAt(now)) {
      _clearPendingAction();
      return const PendingConversationResolution(
        'Cette clarification a expiré. Reformule ta demande.',
        diagnosticCode: 'shopping_clarification_expired',
      );
    }
    final resolution = _shoppingAmbiguityResolution(answer);
    if (resolution == _ShoppingAmbiguityResolution.refuse) {
      _clearPendingAction();
      return const PendingConversationResolution(
        'D’accord, je n’ajoute rien à la liste de courses.',
        diagnosticCode: 'shopping_clarification_refused',
      );
    }
    if (resolution != _ShoppingAmbiguityResolution.buyMore) {
      return PendingConversationResolution(
        _shoppingClarificationQuestion(pending.article),
        diagnosticCode: 'shopping_clarification_still_ambiguous',
      );
    }
    _clearPendingAction();
    final proposal = await _beginShoppingProposal(
      sessionGeneration: pending.sessionGeneration,
      logicalRequestId: pending.logicalRequestId,
      originalInstruction: pending.article,
      intent: ShoppingConversationIntent(
        items: [ShoppingConversationItem(title: pending.article)],
        isStockOut: false,
      ),
    );
    return PendingConversationResolution(
      proposal.reply,
      diagnosticCode: 'shopping_clarification_resolved_add',
    );
  }

  Future<PendingConversationResolution?> resolvePendingTaskClarification({
    required String answer,
    required int sessionGeneration,
  }) async {
    final wrapped = _state.pendingAction;
    if (wrapped?.type != PendingConversationActionType.taskClarification) {
      return null;
    }
    final draft = wrapped!.taskClarification!;
    if (draft.sessionGeneration != sessionGeneration ||
        draft.isExpiredAt(_clock().toUtc())) {
      _clearPendingAction();
      return const PendingConversationResolution(
        'Cette demande a expiré. Reformule-la pour créer la tâche.',
        diagnosticCode: 'task_clarification_expired',
      );
    }
    final classified = answerClassifier.classify(answer);
    if (classified == ConversationAnswer.negative) {
      _clearPendingAction();
      return const PendingConversationResolution(
        'D’accord, je ne crée aucune tâche.',
        diagnosticCode: 'task_clarification_rejected',
      );
    }
    final title = answer.trim();
    if (classified == ConversationAnswer.positive ||
        title.length < 3 ||
        title.length > 500 ||
        title.endsWith('?')) {
      return const PendingConversationResolution(
        'Quelle tâche veux-tu créer ?',
        diagnosticCode: 'task_clarification_still_required',
      );
    }
    final policy = await _canonicalPolicy();
    _lastAutonomyPolicy = policy;
    final now = _clock().toUtc();
    final pending = ActionPending(
      pendingActionId: draft.draftId,
      sessionGeneration: sessionGeneration,
      actionType: ActionType.createTask,
      origin: ActionOrigin.structuredContinuation,
      riskLevel: const ActionAutonomyActionRegistry().riskFor(
        ActionType.createTask,
      ),
      policyModeAtCreation: policy.mode,
      policyVersionAtCreation: policy.schemaVersion,
      wasGrounded: true,
      wasComplete: true,
      payload: PendingTaskPayload(
        title: title,
        dueDate: draft.dueDate,
        priority: draft.priority,
        isImportant: draft.isImportant,
      ),
      originalInstruction: draft.originalInstruction,
      mutationId: draft.logicalRequestId,
      createdAt: now,
      expiresAt: now.add(const Duration(minutes: 15)),
    )..validate();
    final issued = _confirmationCoordinator.issueWithPolicy(
      _confirmationProposalForPending(pending),
      policy: policy,
    );
    _state = _state.copyWith(
      phase: ConversationPhase.awaitingActionConfirmation,
      pendingAction: PendingConversationAction.autonomyConfirmation(
        pending,
        issued.confirmation,
      ),
    );
    final details = [
      'Tâche : $title',
      if (draft.dueDate.isNotEmpty) 'Échéance : ${draft.dueDate}',
      if (draft.priority.isNotEmpty) 'Priorité : ${draft.priority}',
    ].join('\n');
    return PendingConversationResolution(
      '$details\n\nVeux-tu confirmer la création de cette tâche ?',
      diagnosticCode: 'task_clarification_completed',
    );
  }

  Future<ConversationOutcome?> send({
    required ConversationInput input,
    required ConversationActionExecutor executeAction,
  }) async {
    _sessionGeneration = input.sessionGeneration;
    final eventMutationResolution = await resolvePendingEventMutation(
      answer: input.message,
    );
    if (eventMutationResolution != null) {
      return ConversationOutcome(
        reply: eventMutationResolution.message,
        referenceResolution: eventMutationResolution.referenceResolution,
      );
    }
    final routineResult = await routineConversationService?.process(
      input.message,
      logicalRequestId:
          input.logicalRequestId ?? _actionDraftIdGenerator.generate(),
    );
    if (routineResult != null &&
        routineResult.type != RoutineConversationResultType.notRoutine) {
      _state = _state.copyWith(
        phase: routineConversationService!.hasPending
            ? ConversationPhase.awaitingActionConfirmation
            : ConversationPhase.idle,
      );
      return ConversationOutcome(reply: routineResult.message);
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
    if (_state.pendingAction == null) {
      final shoppingClassification =
          shoppingIntentDetector.classify(input.message);
      if (shoppingClassification.kind ==
          ShoppingConversationIntentKind.ambiguousMoreOrNoMore) {
        return _beginShoppingClarification(
          input: input,
          article: shoppingClassification.items.single.title,
        );
      }
      if (shoppingClassification.isActionable) {
        return _beginShoppingIntent(
          input: input,
          intent: ShoppingConversationIntent(
            items: shoppingClassification.items,
            isStockOut: shoppingClassification.kind ==
                ShoppingConversationIntentKind.stockoutDetected,
          ),
        );
      }
    }
    if (priorityConsultationIntentDetector.matches(input.message)) {
      final consultation = await priorityConsultationService?.respond();
      if (consultation != null) {
        return ConversationOutcome(
          reply: consultation.reply,
          responseKind: ConversationResponseKind.answer,
        );
      }
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
      final autonomyPolicy = await _loadAutonomyPolicy?.call();
      if (autonomyPolicy != null) _lastAutonomyPolicy = autonomyPolicy;
      final policyRequest = (autonomyPolicy == null
              ? builtRequest
              : builtRequest.withAutonomyPolicy(autonomyPolicy))
          .withSessionGeneration(input.sessionGeneration);
      final request = input.correlationId == null
          ? policyRequest
          : policyRequest.withCorrelationId(input.correlationId!);
      final memoryContext = contextProvider is MemoryConversationContextProvider
          ? contextProvider as MemoryConversationContextProvider
          : null;
      final userProposal = await memoryContext?.proposeUserMemory(
        input.message,
        logicalRequestId: input.logicalRequestId,
      );
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
      final memoryAttemptStatus =
          contextProvider is MemoryConversationAttemptStatusProvider
              ? contextProvider as MemoryConversationAttemptStatusProvider
              : null;
      if (memoryContext != null &&
          (MemoryPipelineService.hasExplicitMemoryRequest(input.message) ||
              (memoryAttemptStatus?.lastMemoryProposalWasAttempted == true &&
                  memoryAttemptStatus
                          ?.lastMemoryProposalWasPersistedOrPending !=
                      true))) {
        return ConversationOutcome(
          reply: 'Je n’ai pas pu ajouter cette information à ma mémoire. '
              'Tu peux réessayer dans un instant.',
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
      final missingTaskTitle = epistemic?.responseKind ==
              ConversationResponseKind.clarificationRequired &&
          epistemic!.clarification?.missingFieldCodes.contains(
                ConversationMissingInformationCode.missingTaskTarget,
              ) ==
              true;
      if (missingTaskTitle &&
          response.actions.isEmpty &&
          response.memories.isEmpty &&
          _state.pendingAction == null) {
        final draft = taskCreationDraftService.extract(
          input.message,
          referenceDate: _clock(),
        );
        if (draft != null && draft.title.isEmpty) {
          final now = _clock().toUtc();
          final draftId = _actionDraftIdGenerator.generate();
          _state = _state.copyWith(
            phase: ConversationPhase.awaitingActionConfirmation,
            pendingAction: PendingConversationAction.taskClarification(
              PendingTaskClarificationDraft(
                draftId: draftId,
                logicalRequestId: input.logicalRequestId ?? draftId,
                sessionGeneration: input.sessionGeneration,
                dueDate: draft.dueDate,
                priority: draft.priority,
                isImportant: draft.isImportant,
                originalInstruction: input.message,
                createdAt: now,
                expiresAt: now.add(const Duration(minutes: 15)),
              ),
            ),
          );
        }
      }
      var reply = response.reply;
      final actionMessages = <String>[];
      final shoppingTitles = <String>[];
      final taskTitles = <String>[];
      final eventTitles = <String>[];
      String? planningTitle;
      ConversationReferenceResolution? referenceResolution;

      for (final rawAction in response.actions) {
        final guarded = ZeliaActionGuardService.guard(rawAction);
        if (!guarded.isAccepted || guarded.action == null) continue;

        final action = guarded.action!;
        final type = action['type']?.toString() ?? '';
        final latestPolicy = await _loadAutonomyPolicy?.call();
        if (latestPolicy != null) {
          _lastAutonomyPolicy = latestPolicy;
          final actionType = _actionType(action);
          final decision = _autonomyEngine.evaluate(
            policy: latestPolicy,
            request: ActionAuthorizationRequest(
              actionType: actionType,
              origin: ActionOrigin.explicitUserRequest,
              riskLevel:
                  const ActionAutonomyActionRegistry().riskFor(actionType),
              sessionGeneration: input.sessionGeneration,
              policyVersionObserved: latestPolicy.schemaVersion,
              domainConfirmationRequired: actionType == ActionType.proposeEvent,
            ),
            evaluatedAt: _clock(),
          );
          if (!decision.mayExecute && !decision.mayCreateProposal) {
            actionMessages.add(_autonomyMessage(decision));
            continue;
          }
          if (decision.requiresConfirmation &&
              actionType != ActionType.proposeEvent) {
            final payload = _pendingPayload(action);
            if (payload == null || _state.pendingAction != null) {
              actionMessages
                  .add('Cette modification ne peut pas être préparée.');
              continue;
            }
            final now = _clock().toUtc();
            final pending = ActionPending(
              pendingActionId: _actionDraftIdGenerator.generate(),
              sessionGeneration: input.sessionGeneration,
              actionType: actionType,
              origin: ActionOrigin.explicitUserRequest,
              riskLevel: decision.actionType == actionType
                  ? const ActionAutonomyActionRegistry().riskFor(actionType)
                  : ActionRiskLevel.mutation,
              policyModeAtCreation: latestPolicy.mode,
              policyVersionAtCreation: latestPolicy.schemaVersion,
              wasGrounded: epistemic != null,
              wasComplete: true,
              payload: payload,
              originalInstruction: input.message,
              mutationId: _actionDraftIdGenerator.generate(),
              createdAt: now,
              expiresAt: now.add(const Duration(minutes: 15)),
            )..validate();
            final confirmation = _confirmationCoordinator.issueWithPolicy(
              _confirmationProposalForPending(pending),
              policy: latestPolicy,
            );
            _state = _state.copyWith(
              phase: ConversationPhase.awaitingActionConfirmation,
              pendingAction: PendingConversationAction.autonomyConfirmation(
                pending,
                confirmation.confirmation,
              ),
            );
            actionMessages.add(
              'Je peux préparer cette modification. Veux-tu la confirmer ?',
            );
            continue;
          }
        }
        if (type == 'event_mutation' &&
            action['eventMutation'] is EventMutationRequest) {
          final mutation = await beginEventMutation(
            action['eventMutation'] as EventMutationRequest,
          );
          actionMessages.add(mutation.message);
          referenceResolution = mutation.referenceResolution;
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
        referenceResolution: referenceResolution,
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

  static ActionType _actionType(Map<String, dynamic> action) {
    return switch (action['type']?.toString()) {
      'event' || 'event_mutation' => ActionType.proposeEvent,
      'task' || 'todo' || 'to-do' => ActionType.createTask,
      'shopping' => ActionType.addShoppingItem,
      _ => ActionType.thirdPartyUnsupported,
    };
  }

  static ActionPendingPayload? _pendingPayload(Map<String, dynamic> action) {
    final title = action['title']?.toString().trim() ?? '';
    if (title.isEmpty || title.length > 500) return null;
    return switch (action['type']?.toString()) {
      'task' || 'todo' || 'to-do' => PendingTaskPayload(
          title: title,
          dueDate: action['dueDate']?.toString() ?? '',
          notes: action['notes']?.toString() ?? '',
          planning: action['planning']?.toString() ?? '',
          priority: action['priority']?.toString() ?? '',
          isImportant: action['isImportant'] == true,
        ),
      'shopping' => PendingShoppingPayload(
          title: title,
          category: action['category']?.toString() ?? '',
          notes: action['notes']?.toString() ?? '',
          section: action['section']?.toString() ?? '',
          isUrgent: action['isUrgent'] == true,
        ),
      _ => null,
    };
  }

  static Map<String, dynamic> _legacyAction(ActionPending pending) {
    final payload = pending.payload;
    return switch (payload) {
      PendingTaskPayload() => {
          'type': 'task',
          'actionId': pending.pendingActionId,
          'logicalRequestId': pending.mutationId,
          'mutationId': pending.mutationId,
          'title': payload.title,
          'dueDate': payload.dueDate,
          'notes': payload.notes,
          'planning': payload.planning,
          'priority': payload.priority,
          'isImportant': payload.isImportant,
          'originalMessage': pending.originalInstruction,
        },
      PendingShoppingPayload() => {
          'type': 'shopping',
          'actionId': pending.pendingActionId,
          'logicalRequestId': pending.mutationId,
          'mutationId': pending.mutationId,
          'title': payload.title,
          'items': [
            payload.title,
            ...payload.additionalTitles,
          ],
          'category': payload.category,
          'notes': payload.notes,
          'section': payload.section,
          'isUrgent': payload.isUrgent,
        },
    };
  }

  ActionConfirmationProposal _confirmationProposalForPending(
    ActionPending pending,
  ) {
    final fields = switch (pending.payload) {
      PendingTaskPayload(
        :final title,
        :final dueDate,
        :final notes,
        :final planning,
        :final priority,
        :final isImportant,
      ) =>
        [
          ActionConfirmationField(
            key: ActionConfirmationFieldKey.title,
            value: title,
          ),
          ActionConfirmationField(
            key: ActionConfirmationFieldKey.dueDate,
            value: dueDate.isEmpty ? null : dueDate,
          ),
          ActionConfirmationField(
            key: ActionConfirmationFieldKey.category,
            value: planning.isEmpty ? null : planning,
          ),
          ActionConfirmationField(
            key: ActionConfirmationFieldKey.section,
            value: priority.isEmpty ? null : priority,
          ),
          ActionConfirmationField(
            key: ActionConfirmationFieldKey.choiceId,
            value: isImportant,
          ),
          if (notes.isNotEmpty)
            ActionConfirmationField(
              key: ActionConfirmationFieldKey.operation,
              value: notes,
            ),
        ],
      PendingShoppingPayload(
        :final title,
        :final additionalTitles,
        :final category,
        :final notes,
        :final section,
        :final isUrgent,
      ) =>
        [
          ActionConfirmationField(
            key: ActionConfirmationFieldKey.title,
            value: title,
          ),
          ActionConfirmationField(
            key: ActionConfirmationFieldKey.category,
            value: category.isEmpty ? null : category,
          ),
          ActionConfirmationField(
            key: ActionConfirmationFieldKey.section,
            value: section.isEmpty ? null : section,
          ),
          ActionConfirmationField(
            key: ActionConfirmationFieldKey.choiceId,
            value: isUrgent,
          ),
          if (notes.isNotEmpty)
            ActionConfirmationField(
              key: ActionConfirmationFieldKey.operation,
              value: notes,
            ),
          if (additionalTitles.isNotEmpty)
            ActionConfirmationField(
              key: ActionConfirmationFieldKey.operation,
              value: additionalTitles.join('|'),
            ),
        ],
    };
    final isTask = pending.actionType == ActionType.createTask;
    final scope = ActionConfirmationScope(
      type: ActionConfirmationScopeType.executeExactMutation,
      targetId: pending.pendingActionId,
      operation: isTask ? 'createTask' : 'addShoppingItem',
      expectedRevision: 0,
      fields: fields,
    );
    return ActionConfirmationProposal(
      accountScopeId: _confirmationAccountScope()!,
      sessionGeneration: pending.sessionGeneration,
      actionPendingId: pending.pendingActionId,
      actionType: pending.actionType,
      actionDomain:
          isTask ? ActionLedgerDomain.task : ActionLedgerDomain.shopping,
      actionOrigin: pending.origin,
      riskLevel: pending.riskLevel,
      scope: scope,
      requirements: [
        ActionConfirmationRequirement(
          source: ActionConfirmationRequirementSource.autonomySuggestionsMode,
          code: 'autonomy_suggestions_confirmation',
          scope: scope.type,
          requiresFreshConfirmation: true,
          requiresSeparateConfirmation: false,
          policyVersionObserved: pending.policyVersionAtCreation,
        ),
        ActionConfirmationRequirement(
          source: ActionConfirmationRequirementSource.domainRequired,
          code: 'exact_mutation_confirmation',
          scope: scope.type,
          requiresFreshConfirmation: true,
          requiresSeparateConfirmation: false,
          policyVersionObserved: pending.policyVersionAtCreation,
        ),
      ],
      mutationId: pending.mutationId,
      policyMode: pending.policyModeAtCreation,
      policyVersion: pending.policyVersionAtCreation,
      presentation: ActionConfirmationPresentation(
        title: isTask ? 'Confirmer la tâche' : 'Confirmer l’ajout',
        summary: isTask
            ? 'Créer la tâche préparée.'
            : 'Ajouter l’article préparé à la liste.',
        consequence: isTask
            ? 'La liste des tâches sera modifiée.'
            : 'La liste de courses sera modifiée.',
        allowPostpone: true,
      ),
      provenance: 'conversation_action_pending',
      validity: const Duration(minutes: 15),
    );
  }

  Future<ConversationOutcome> _beginShoppingIntent({
    required ConversationInput input,
    required ShoppingConversationIntent intent,
  }) =>
      _beginShoppingProposal(
        sessionGeneration: input.sessionGeneration,
        logicalRequestId: input.logicalRequestId,
        originalInstruction: input.message,
        intent: intent,
      );

  Future<ConversationOutcome> _beginShoppingProposal({
    required int sessionGeneration,
    required String? logicalRequestId,
    required String originalInstruction,
    required ShoppingConversationIntent intent,
  }) async {
    final policy = await _canonicalPolicy();
    _lastAutonomyPolicy = policy;
    final actionType = ActionType.addShoppingItem;
    final decision = _autonomyEngine.evaluate(
      policy: policy,
      request: ActionAuthorizationRequest(
        actionType: actionType,
        origin: ActionOrigin.explicitUserRequest,
        riskLevel: const ActionAutonomyActionRegistry().riskFor(actionType),
        sessionGeneration: sessionGeneration,
        policyVersionObserved: policy.schemaVersion,
        isGrounded: true,
        isComplete: true,
      ),
      evaluatedAt: _clock(),
    );
    if (!decision.mayExecute && !decision.mayCreateProposal) {
      return ConversationOutcome(reply: _autonomyMessage(decision));
    }
    final now = _clock().toUtc();
    final pendingId = _actionDraftIdGenerator.generate();
    final stableLogicalRequestId = logicalRequestId ?? pendingId;
    final titles = intent.items.map((item) => item.title).toList();
    final pending = ActionPending(
      pendingActionId: pendingId,
      sessionGeneration: sessionGeneration,
      actionType: actionType,
      origin: ActionOrigin.explicitUserRequest,
      riskLevel: const ActionAutonomyActionRegistry().riskFor(actionType),
      policyModeAtCreation: policy.mode,
      policyVersionAtCreation: policy.schemaVersion,
      wasGrounded: true,
      wasComplete: true,
      payload: PendingShoppingPayload(
        title: titles.first,
        additionalTitles: titles.skip(1).toList(growable: false),
      ),
      originalInstruction: originalInstruction,
      mutationId: stableLogicalRequestId,
      createdAt: now,
      expiresAt: now.add(const Duration(minutes: 15)),
    )..validate();
    final issued = _confirmationCoordinator.issueWithPolicy(
      _confirmationProposalForPending(pending),
      policy: policy,
    );
    _state = _state.copyWith(
      phase: ConversationPhase.awaitingActionConfirmation,
      pendingAction: PendingConversationAction.autonomyConfirmation(
        pending,
        issued.confirmation,
      ),
    );
    final label = _shoppingTitlesLabel(titles);
    return ConversationOutcome(
      reply: intent.isStockOut
          ? titles.length == 1
              ? 'Tu n’as plus de $label. Veux-tu que je l’ajoute à ta liste de courses ?'
              : 'Tu n’as plus de $label. Veux-tu que je les ajoute à ta liste de courses ?'
          : titles.length == 1
              ? 'Veux-tu que j’ajoute “$label” à ta liste de courses ?'
              : 'Veux-tu que j’ajoute “$label” à ta liste de courses ?',
    );
  }

  ConversationOutcome _beginShoppingClarification({
    required ConversationInput input,
    required String article,
  }) {
    final now = _clock().toUtc();
    final clarificationId = _actionDraftIdGenerator.generate();
    _state = _state.copyWith(
      phase: ConversationPhase.awaitingActionConfirmation,
      pendingAction: PendingConversationAction.shoppingClarification(
        PendingShoppingClarification(
          clarificationId: clarificationId,
          logicalRequestId: input.logicalRequestId ?? clarificationId,
          sessionGeneration: input.sessionGeneration,
          article: article,
          type: ShoppingClarificationType.moreOrNoMore,
          createdAt: now,
          expiresAt: now.add(const Duration(minutes: 15)),
        ),
      ),
    );
    return ConversationOutcome(
      reply: _shoppingClarificationQuestion(article),
      responseKind: ConversationResponseKind.clarificationRequired,
    );
  }

  static String _shoppingClarificationQuestion(String article) =>
      'Tu veux dire que tu souhaites acheter davantage de $article, '
      'ou que tu n’en veux plus ?';

  static _ShoppingAmbiguityResolution _shoppingAmbiguityResolution(
    String answer,
  ) {
    final normalized = answer
        .toLowerCase()
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('’', "'")
        .replaceAll(RegExp(r"['`]"), ' ')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.contains(RegExp(
      r'\b(?:davantage|acheter plus|acheter davantage|en racheter|ajoute les aux courses|j en veux plus)\b',
    ))) {
      return _ShoppingAmbiguityResolution.buyMore;
    }
    if (normalized.contains(RegExp(
      r'\b(?:je n en veux plus|je ne veux plus|non je n en veux plus|retire cette idee)\b',
    ))) {
      return _ShoppingAmbiguityResolution.refuse;
    }
    return _ShoppingAmbiguityResolution.stillAmbiguous;
  }

  static String _shoppingTitlesLabel(List<String> titles) {
    if (titles.length == 1) return titles.single;
    return '${titles.take(titles.length - 1).join(', ')} et ${titles.last}';
  }

  static String _autonomyMessage(ActionAuthorizationDecision decision) {
    return switch (decision.decision) {
      ActionAuthorizationDecisionType.blockedPaused =>
        'Les actions sont en pause. Je peux continuer à répondre, mais je ne '
            'modifierai rien.',
      ActionAuthorizationDecisionType.blockedUnsupported =>
        'Cette action n’est pas prise en charge.',
      _ => 'Je ne peux pas appliquer cette action de façon sûre.',
    };
  }

  static String _confirmationResponseId(
    ActionConfirmation confirmation,
    ActionConfirmationResponseChoice choice,
  ) =>
      '${confirmation.confirmationId}:${choice.name}';

  Future<String?> _authorizeConfirmed(ActionType actionType) async {
    final policy = await _loadAutonomyPolicy?.call();
    if (policy == null) return null;
    _lastAutonomyPolicy = policy;
    final decision = _autonomyEngine.evaluate(
      policy: policy,
      request: ActionAuthorizationRequest(
        actionType: actionType,
        origin: ActionOrigin.explicitUserConfirmation,
        riskLevel: const ActionAutonomyActionRegistry().riskFor(actionType),
        sessionGeneration: 0,
        policyVersionObserved: policy.schemaVersion,
        hasFreshExplicitConfirmation: true,
      ),
      evaluatedAt: _clock(),
    );
    return decision.mayExecute ? null : _autonomyMessage(decision);
  }

  ActionPendingMetadata _pendingMetadata(ActionType actionType) {
    final policy = _lastAutonomyPolicy;
    return ActionPendingMetadata(
      actionType: actionType,
      origin: ActionOrigin.structuredContinuation,
      riskLevel: const ActionAutonomyActionRegistry().riskFor(actionType),
      policyModeAtCreation: policy?.mode ?? ActionAutonomyMode.suggestions,
      policyVersionAtCreation:
          policy?.schemaVersion ?? ActionAutonomyPolicy.currentSchemaVersion,
      sessionGeneration: _sessionGeneration,
    );
  }

  String? _confirmationAccountScope() =>
      _lastAutonomyPolicy?.accountScopeId ??
      identityAccountScope?.accountId ??
      _observedAccountScopeId ??
      'conversation-local';

  Future<ActionAutonomyPolicy> _canonicalPolicy() async {
    final loaded = await _loadAutonomyPolicy?.call();
    if (loaded != null) {
      _lastAutonomyPolicy = loaded;
      return loaded;
    }
    return _lastAutonomyPolicy ??
        ActionAutonomyPolicy.restrictiveDefault(
          accountScopeId: _confirmationAccountScope()!,
          changedAt: _clock().toUtc(),
        );
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

enum _ShoppingAmbiguityResolution { buyMore, refuse, stillAmbiguous }
