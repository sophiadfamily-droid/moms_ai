import '../models/conversation_models.dart';
import '../models/event_model.dart';
import '../models/life_context/memory_context.dart';
import '../models/memory_lifecycle.dart';
import '../models/memory_lifecycle_state.dart';
import '../core/identity/uuid_v7_entity_id_generator.dart';
import 'chat_backend_client.dart';
import 'conversation_answer_classifier.dart';
import 'conversation_context_service.dart';
import 'memory_confirmation_copy.dart';
import 'memory_lifecycle_engine.dart';
import 'memory_lifecycle_repository.dart';
import 'identity/identity_application_models.dart';
import 'identity/identity_application_service.dart';
import 'identity/identity_action_binding_service.dart';
import 'identity/identity_clarification_service.dart';
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

  ConversationState _state = const ConversationState();
  bool _isSending = false;
  bool _isResolvingPendingAction = false;
  final Map<String, PendingIdentityActionBinding> _identityActionBindings = {};

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
  })  : _memoryLifecycleRepository = memoryLifecycleRepository,
        identityClarificationService = identityClarificationService ??
            IdentityClarificationService(
              idGenerator: UuidV7EntityIdGenerator(),
            ),
        identityActionBindingService = identityActionBindingService ??
            IdentityActionBindingService(
              idGenerator: UuidV7EntityIdGenerator(),
            );

  ConversationState get state => _state;

  void setPendingEventConfirmation(EventModel? event) {
    if (event == null) {
      _state = _state.copyWith(
        phase: ConversationPhase.idle,
        clearPendingAction: true,
      );
      return;
    }

    _state = _state.copyWith(
      phase: ConversationPhase.awaitingActionConfirmation,
      pendingAction: PendingConversationAction.eventConfirmation(event),
    );
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
            PendingConversationActionType.identityClarification) {
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

  Future<PendingConversationResolution> beginIdentityActionBinding({
    required IdentityResolutionRequest request,
    required IdentityActionContinuation continuation,
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
    return PendingConversationResolution(
      result.followUpMessage,
      identityClarificationResult: result,
      identityActionBindingResult: bindingResult,
    );
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
      final message = await execute(pending.event);
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
      final request = await contextProvider.buildRequest(
        message: input.message,
        profile: input.profile,
      );
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

      return ConversationOutcome(reply: reply, request: request);
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
