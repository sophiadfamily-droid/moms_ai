import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/conversation_models.dart';
import '../models/action_autonomy_policy.dart';
import '../models/action_confirmation.dart';
import '../models/conversation_epistemic_models.dart';
import '../models/conversation_context_envelope.dart';
import '../models/conversation_session_models.dart';
import '../models/agenda_conflict_move_suggestion.dart';
import '../models/smart_planning_continuation.dart';
import '../models/task_model.dart';
import '../models/priority/proactive_priority_models.dart';
import '../models/user_profile.dart';
import 'app_diagnostics.dart';
import 'app_error_classifier.dart';
import 'action_handler_service.dart';
import 'action_autonomy_policy_service.dart';
import 'chat_backend_client.dart';
import 'chat_backend_client_factory.dart';
import 'chat_service.dart';
import 'conversation_compound_request_service.dart';
import 'conversation_context_service.dart';
import 'conversation_coordinator.dart';
import 'conversation_grounding_policy.dart';
import 'conversation_legacy_action_executor.dart';
import 'conversation_reference_history_store.dart';
import 'conversation_reference_resolver.dart';
import 'event_confirmation_service.dart';
import 'event_conversation_mutation_service.dart';
import 'event_planning_conflict_service.dart';
import 'event_title_service.dart';
import 'routine_conversation_service.dart';
import 'human/human_model_edit_service.dart';
import 'human/recurring_responsibility_conversation_service.dart';
import 'identity/identity_production_services.dart';
import 'mental_load/mental_load_consultation_service.dart';
import 'mental_load_anticipation_production.dart';
import 'priority/proactive_interaction_registry.dart';
import 'smart_planning_continuation_coordinator.dart';

typedef ConversationSessionActionExecutor = Future<ConversationActionOutcome>
    Function(
  Map<String, dynamic> action,
  String userMessage,
  int sessionGeneration,
);
typedef ConversationPendingResolver = Future<ConversationOutcome?> Function(
  String answer,
  int sessionGeneration,
);
typedef ConversationLocalRequestResolver = Future<ConversationOutcome?>
    Function(
  String message,
  int sessionGeneration,
);
typedef ConversationClarificationDraftPreparer = Future<String?> Function(
  ConversationClarificationDraft draft,
  int sessionGeneration,
  String userMessage,
);
typedef ConversationSessionInvalidator = void Function(
  UserProfile profile,
  int sessionGeneration,
);
typedef ConversationApplicationPendingPhase = ConversationSessionPhase?
    Function();
typedef ConversationApplicationInteractionSources
    = Set<ProactiveInteractionSource> Function();
typedef ConversationTaskDurationStarter = SmartPlanningContinuationResult
    Function({
  required TaskModel task,
  required String question,
  required int sessionGeneration,
  required String logicalRequestId,
  required String sourceSuggestionId,
});
typedef ConversationActiveSmartPlanningContinuation = SmartPlanningContinuation?
    Function();

abstract interface class ConversationMessageStore {
  Future<void> save({
    required String sessionId,
    required ConversationMessageRole role,
    required String text,
  });
}

final class DefaultConversationMessageStore
    implements ConversationMessageStore {
  const DefaultConversationMessageStore();

  @override
  Future<void> save({
    required String sessionId,
    required ConversationMessageRole role,
    required String text,
  }) =>
      ChatService.saveMessage(
        conversationId: sessionId,
        role: role.name,
        text: text,
      );
}

final class ConversationSessionController extends ChangeNotifier {
  static const int maximumBackendRetries = 1;

  ConversationSessionController({
    required UserProfile profile,
    required ConversationCoordinator coordinator,
    ConversationSessionActionExecutor? executeAction,
    ConversationPendingResolver? resolvePending,
    ConversationLocalRequestResolver? resolveLocalRequest,
    ConversationCompoundRequestService compoundRequestService =
        const ConversationCompoundRequestService(),
    ConversationClarificationDraftPreparer? prepareClarificationDraft,
    ConversationSessionInvalidator? invalidateSession,
    ConversationApplicationPendingPhase? applicationPendingPhase,
    ConversationApplicationInteractionSources? applicationInteractionSources,
    ConversationTaskDurationStarter? startTaskDuration,
    ConversationActiveSmartPlanningContinuation?
        applicationSmartPlanningContinuation,
    ConversationMessageStore messageStore =
        const DefaultConversationMessageStore(),
    ConversationReferenceHistoryStore? referenceHistoryStore,
    String? accountScopeId,
    ProactiveInteractionRegistry? proactiveInteractionRegistry,
    ChatBackendClient? ownedBackend,
    DateTime Function()? clock,
    String Function()? idGenerator,
    String? initialAssistantMessage,
  })  : _profile = profile,
        _coordinator = coordinator,
        _executeAction = executeAction ??
            ConversationLegacyActionExecutor(coordinator: coordinator).execute,
        _resolvePending = resolvePending,
        _resolveLocalRequest = resolveLocalRequest,
        _compoundRequestService = compoundRequestService,
        _prepareClarificationDraft = prepareClarificationDraft,
        _invalidateSession = invalidateSession,
        _applicationPendingPhase = applicationPendingPhase,
        _applicationInteractionSources = applicationInteractionSources,
        _startTaskDuration = startTaskDuration,
        _applicationSmartPlanningContinuation =
            applicationSmartPlanningContinuation,
        _messageStore = messageStore,
        _referenceHistoryStore = referenceHistoryStore,
        _accountScopeId = accountScopeId?.trim(),
        _proactiveInteractionRegistry = proactiveInteractionRegistry ??
            ProactiveInteractionRegistry.instance,
        _ownedBackend = ownedBackend,
        _clock = clock ?? DateTime.now,
        _idGenerator = idGenerator ?? _defaultId,
        _state = ConversationSessionState(
          sessionId: (idGenerator ?? _defaultId)(),
          sessionGeneration: 0,
          phase: ConversationSessionPhase.initial,
          messages: const [],
          effects: const [],
        ) {
    _state = _state.copyWith(phase: ConversationSessionPhase.ready);
    addInitialAssistantMessage(initialAssistantMessage);
  }

  factory ConversationSessionController.production({
    required UserProfile profile,
    ChatBackendClient? backendClient,
    ConversationContextProvider? contextProvider,
    IdentityProductionServices? identityServices,
    ConversationSessionActionExecutor? executeAction,
    EventStartConflictChecker? eventStartConflictChecker,
    EventConflictChecker? eventConflictChecker,
    EventStartAlternativeSuggester? eventStartAlternativeSuggester,
    EventAlternativeSuggester? eventAlternativeSuggester,
    EventConversationMutationService? eventConversationMutationService,
    ConversationReferenceHistoryStore? referenceHistoryStore,
    ConversationMessageStore messageStore =
        const DefaultConversationMessageStore(),
    DateTime Function()? clock,
    String Function()? idGenerator,
    String? accountScopeId,
    ProactiveInteractionRegistry? proactiveInteractionRegistry,
    String? initialAssistantMessage,
  }) {
    var activeProfile = profile;
    final backend = backendClient ?? createDefaultChatBackendClient();
    final resolvedAccountScopeId = accountScopeId?.trim().isNotEmpty == true
        ? accountScopeId!.trim()
        : identityServices?.scope.accountId ??
            (backendClient == null
                ? FirebaseAuth.instance.currentUser?.uid
                : null);
    Future<ActionAutonomyPolicyService>? autonomyService;
    Future<ActionAutonomyPolicyService> loadAutonomyService() =>
        autonomyService ??= ActionAutonomyPolicyService.local(
          currentAccountScopeId: () => FirebaseAuth.instance.currentUser?.uid,
        );
    Future<ActionAutonomyPolicy> loadAutonomyPolicy() async {
      if (backendClient != null) {
        return ActionAutonomyPolicy.restrictiveDefault(
          accountScopeId: resolvedAccountScopeId ?? 'injected-session',
          changedAt: DateTime.now().toUtc(),
        );
      }
      return (await loadAutonomyService()).load();
    }

    final mutationService = eventConversationMutationService ??
        EventConversationMutationService.production(
          accountScopeId: resolvedAccountScopeId,
        );
    final coordinator = ConversationCoordinator(
      backend: backend,
      contextProvider: contextProvider ?? DefaultConversationContextProvider(),
      identityApplicationService: identityServices?.applicationService,
      identityCreationService: identityServices?.creationService,
      identityAccountScope: identityServices?.scope,
      eventParticipantIdentityValidationService:
          identityServices?.eventParticipantValidation,
      eventConversationMutationService: mutationService,
      loadAutonomyPolicy: loadAutonomyPolicy,
      routineConversationService: RoutineConversationService.production(
        currentProfile: () => activeProfile,
      ),
      recurringResponsibilityConversationService:
          RecurringResponsibilityConversationService(
        currentAccountScopeId: () => resolvedAccountScopeId,
        loadEditor: HumanModelEditService.createProduction,
      ),
      mentalLoadConsultationService: resolvedAccountScopeId == null
          ? null
          : MentalLoadConsultationService(
              loadSuggestions: () => MentalLoadAnticipationProduction.load(
                resolvedAccountScopeId,
              ),
            ),
      clock: clock,
    );
    final smartPlanningGateway =
        ProductionSmartPlanningContinuationGateway(profile);
    final smartPlanning = SmartPlanningContinuationCoordinator(
      gateway: smartPlanningGateway,
      loadAutonomyPolicy: loadAutonomyPolicy,
    );
    final planningConflictService =
        eventStartConflictChecker == null || eventConflictChecker == null
            ? EventPlanningConflictService.production(
                currentAccountScopeId: () => resolvedAccountScopeId,
                currentProfile: () => activeProfile,
              )
            : null;
    final legacyExecutor = ConversationLegacyActionExecutor(
      coordinator: coordinator,
      smartPlanning: smartPlanning,
      loadAutonomyPolicy: loadAutonomyPolicy,
      eventStartConflictChecker: eventStartConflictChecker ??
          (eventConflictChecker == null
              ? planningConflictService!.findConflictAtStart
              : ({required startDateTimeIso}) =>
                  EventPlanningConflictService.findExistingConflictAtStart(
                    startDateTimeIso: startDateTimeIso,
                    loadEventConflict: eventConflictChecker,
                  )),
      eventConflictChecker:
          eventConflictChecker ?? planningConflictService!.findConflict,
      eventStartAlternativeSuggester: eventStartAlternativeSuggester ??
          planningConflictService?.suggestAlternativeAtStart,
      eventAlternativeSuggester: eventAlternativeSuggester ??
          planningConflictService?.suggestAlternative,
      clock: clock,
    );
    final controller = ConversationSessionController(
      profile: profile,
      coordinator: coordinator,
      executeAction: executeAction ?? legacyExecutor.execute,
      resolvePending: legacyExecutor.resolvePending,
      resolveLocalRequest: legacyExecutor.resolveLocalRequest,
      prepareClarificationDraft:
          legacyExecutor.prepareClarificationDraftFromMessage,
      invalidateSession: (nextProfile, _) {
        activeProfile = nextProfile;
        coordinator.invalidateSession();
        smartPlanning.invalidate();
        legacyExecutor.invalidate();
        smartPlanningGateway.updateProfile(nextProfile);
      },
      applicationPendingPhase: () {
        final active = smartPlanning.active;
        if (active == null) {
          return legacyExecutor.hasPendingEventDraft
              ? ConversationSessionPhase.awaitingClarification
              : null;
        }
        return switch (active.step) {
          SmartPlanningContinuationStep.planningConsent ||
          SmartPlanningContinuationStep.confirmation ||
          SmartPlanningContinuationStep.alternativeConfirmation =>
            ConversationSessionPhase.awaitingConfirmation,
          _ => ConversationSessionPhase.awaitingClarification,
        };
      },
      applicationInteractionSources: () {
        final active = smartPlanning.active;
        if (active == null) return const {};
        return {
          switch (active.step) {
            SmartPlanningContinuationStep.planningConsent =>
              ProactiveInteractionSource.smartPlanningConsent,
            SmartPlanningContinuationStep.duration ||
            SmartPlanningContinuationStep.location ||
            SmartPlanningContinuationStep.travelGo ||
            SmartPlanningContinuationStep.travelBack =>
              ProactiveInteractionSource.smartPlanningDuration,
            SmartPlanningContinuationStep.optionChoice =>
              ProactiveInteractionSource.smartPlanningSlotSelection,
            SmartPlanningContinuationStep.confirmation ||
            SmartPlanningContinuationStep.alternativeConfirmation =>
              ProactiveInteractionSource.smartPlanningFinalConfirmation,
          },
        };
      },
      startTaskDuration: ({
        required task,
        required question,
        required sessionGeneration,
        required logicalRequestId,
        required sourceSuggestionId,
      }) =>
          smartPlanning.beginTaskDurationCompletion(
        task: task,
        originalMessage: question,
        sessionGeneration: sessionGeneration,
        logicalRequestId: logicalRequestId,
        sourceSuggestionId: sourceSuggestionId,
      ),
      applicationSmartPlanningContinuation: () => smartPlanning.active,
      messageStore: messageStore,
      ownedBackend: backendClient == null ? backend : null,
      referenceHistoryStore: referenceHistoryStore ??
          const SharedPreferencesConversationReferenceHistoryStore(),
      accountScopeId: resolvedAccountScopeId,
      proactiveInteractionRegistry: proactiveInteractionRegistry,
      clock: clock,
      idGenerator: idGenerator,
      initialAssistantMessage:
          "Coucou 💕 Moi c'est Zelia. Je suis là pour t'aider à organiser ton quotidien ✨",
    );
    controller.addInitialAssistantMessage(initialAssistantMessage);
    return controller;
  }

  UserProfile _profile;
  final ConversationCoordinator _coordinator;

  ActionConfirmation? get activeActionConfirmation =>
      _coordinator.activeConfirmation;
  final ConversationSessionActionExecutor _executeAction;
  final ConversationPendingResolver? _resolvePending;
  final ConversationLocalRequestResolver? _resolveLocalRequest;
  final ConversationCompoundRequestService _compoundRequestService;
  final ConversationClarificationDraftPreparer? _prepareClarificationDraft;
  final ConversationSessionInvalidator? _invalidateSession;
  final ConversationApplicationPendingPhase? _applicationPendingPhase;
  final ConversationApplicationInteractionSources?
      _applicationInteractionSources;
  final ConversationTaskDurationStarter? _startTaskDuration;
  final ConversationActiveSmartPlanningContinuation?
      _applicationSmartPlanningContinuation;
  bool _proactiveEventMoveAwaitingConfirmation = false;
  final ConversationMessageStore _messageStore;
  final ConversationReferenceHistoryStore? _referenceHistoryStore;
  String? _accountScopeId;
  final ProactiveInteractionRegistry _proactiveInteractionRegistry;
  final ChatBackendClient? _ownedBackend;
  final DateTime Function() _clock;
  final String Function() _idGenerator;

  ConversationSessionState _state;
  ConversationSessionState get state => _state;
  SmartPlanningContinuation? get activeSmartPlanningContinuation =>
      _applicationSmartPlanningContinuation?.call();
  bool _disposed = false;
  int _requestSequence = 0;
  int _retryCount = 0;
  String? _lastSubmittedText;
  bool _lastSubmittedDiscussionOnly = false;
  bool _lastSubmittedContextualFollowUp = false;
  List<ConversationHistoryMessage> _lastSubmittedHistory = const [];
  String? _lastSubmittedVisibleText;
  String? _lastLogicalRequestId;
  String? _lastCorrelationId;
  String? get activeLogicalRequestId => _lastLogicalRequestId;
  ConversationClarificationLedger _clarificationLedger =
      const ConversationClarificationLedger();
  bool _referenceHistoryLoaded = false;
  String? _deferredRequestAfterResponsibilityClarification;
  final List<String> _deferredCompoundRequests = [];
  String? _activeDiscussionSubject;
  String _activeDiscussionTranscript = '';
  int _activeDiscussionTurns = 0;

  Future<void> dispatch(ConversationUiIntent intent) => switch (intent) {
        SubmitConversationText(:final text) => submitText(text),
        SelectConversationQuickReply(:final replyId) =>
          selectQuickReply(replyId),
        RetryConversationRequest() => retryLastRequest(),
        AnswerConversationClarification(:final answer) => submitText(answer),
        ConfirmPendingConversationAction() => submitText('oui'),
        RejectPendingConversationAction() => submitText('non'),
        PostponePendingConversationAction() => submitText('plus tard'),
        CancelConversationRequest() => cancelCurrentRequest(),
        DismissConversationError() => _dismissError(),
        ConsumeConversationEffect(:final effectId) => _consumeEffect(effectId),
      };

  void addInitialAssistantMessage(String? text) {
    final value = text?.trim() ?? '';
    if (value.isEmpty ||
        _state.messages.any(
          (message) =>
              message.role == ConversationMessageRole.assistant &&
              message.text == value,
        )) {
      return;
    }
    _appendMessage(ConversationMessageRole.assistant, value);
  }

  void addInitialAssistantMessageWithQuickReplies(
    String? text,
    List<ConversationQuickReply> replies,
  ) {
    final value = text?.trim() ?? '';
    if (_disposed || value.isEmpty || replies.isEmpty) return;
    final existing = _state.messages.where(
      (message) =>
          message.role == ConversationMessageRole.assistant &&
          message.text == value,
    );
    final messageId = existing.isEmpty
        ? _appendMessage(ConversationMessageRole.assistant, value)
        : existing.last.id;
    if (messageId == null) return;
    _setState(
      _state.copyWith(
        quickReplies: replies,
        quickReplyMessageId: messageId,
      ),
    );
  }

  Future<void> selectQuickReply(String replyId) async {
    if (_disposed || _state.isBusy) return;
    ConversationQuickReply? selected;
    for (final reply in _state.quickReplies) {
      if (reply.id == replyId) {
        selected = reply;
        break;
      }
    }
    if (selected == null) return;
    _clearQuickReplies();
    if (selected.discussionOnly) {
      await _coordinator.abandonPendingConversation();
      _activeDiscussionSubject = selected.submission;
      _activeDiscussionTranscript = '';
      _activeDiscussionTurns = 0;
    }
    await _submitText(
      selected.submission,
      visibleText: selected.visibleText,
      discussionOnly: selected.discussionOnly,
    );
  }

  void beginProactiveTaskDuration({
    required ProactiveTaskDurationHandoff handoff,
  }) {
    final task = handoff.task;
    if (_disposed ||
        task.id != handoff.taskId ||
        task.title != handoff.taskTitle ||
        _startTaskDuration == null) {
      throw const FormatException('invalid_proactive_duration_target');
    }
    final result = _startTaskDuration(
      task: task,
      question: handoff.question,
      sessionGeneration: _state.sessionGeneration,
      logicalRequestId: handoff.logicalRequestId,
      sourceSuggestionId: handoff.sourceSuggestionId,
    );
    _lastLogicalRequestId = handoff.logicalRequestId;
    _appendMessage(ConversationMessageRole.assistant, result.message);
    _setState(
      _state.copyWith(
        phase: ConversationSessionPhase.awaitingClarification,
        hasPendingAction: true,
        clearCurrentRequest: true,
      ),
    );
    _emit(ConversationUiEffectType.showClarification);
  }

  Future<void> beginProactiveEventMove(
    AgendaConflictMoveSuggestion suggestion,
  ) async {
    if (_disposed || _state.isBusy) return;
    final result = await _coordinator.beginSuggestedEventMove(
      eventId: suggestion.eventId,
      dateIso: suggestion.dateIso,
      time: suggestion.time,
    );
    _appendMessage(ConversationMessageRole.assistant, result.message);
    final pending = _coordinator.state.pendingAction != null;
    _proactiveEventMoveAwaitingConfirmation =
        _coordinator.state.pendingAction?.type ==
            PendingConversationActionType.eventMutationConfirmation;
    _setState(
      _state.copyWith(
        phase: pending
            ? ConversationSessionPhase.awaitingConfirmation
            : ConversationSessionPhase.ready,
        hasPendingAction: pending,
        clearCurrentRequest: true,
      ),
    );
    if (pending) _emit(ConversationUiEffectType.showConfirmation);
  }

  Future<void> submitText(String rawText) =>
      _submitText(rawText, visibleText: rawText);

  Future<void> _submitText(
    String rawText, {
    required String visibleText,
    bool discussionOnly = false,
  }) async {
    final text = rawText.trim();
    final visible = visibleText.trim();
    if (_disposed || text.isEmpty || visible.isEmpty || _state.isBusy) return;
    _clearQuickReplies();
    final explicitAction = _isExplicitActionRequest(text);
    if (!discussionOnly && explicitAction) {
      _clearActiveDiscussion();
    }
    final continuesActiveDiscussion =
        !discussionOnly && _activeDiscussionSubject != null && !explicitAction;
    final effectiveDiscussionOnly = discussionOnly || continuesActiveDiscussion;
    final continuesLogicalRequest =
        _state.phase == ConversationSessionPhase.awaitingClarification ||
            _state.phase == ConversationSessionPhase.awaitingConfirmation ||
            _coordinator.state.pendingAction != null ||
            _applicationPendingPhase?.call() != null;
    final contextualFollowUp = _shouldUseContextualFollowUp(
      text,
      discussionOnly: effectiveDiscussionOnly,
      continuesLogicalRequest: continuesLogicalRequest,
    );
    final conversationHistory = _buildConversationHistory();
    final compound =
        !effectiveDiscussionOnly && _deferredCompoundRequests.isEmpty
            ? _compoundRequestService.split(
                text,
                referenceDate: _clock(),
                allowContextualLeadingPart: continuesLogicalRequest,
              )
            : null;
    final requestText = continuesActiveDiscussion
        ? _buildActiveDiscussionRequest(text)
        : compound?.parts.first ?? text;
    if (compound != null) {
      _deferredCompoundRequests.addAll(compound.parts.skip(1));
    }
    _lastSubmittedText = requestText;
    _lastSubmittedDiscussionOnly = effectiveDiscussionOnly;
    _lastSubmittedContextualFollowUp = contextualFollowUp;
    _lastSubmittedHistory = conversationHistory;
    _lastSubmittedVisibleText = visible;
    _lastCorrelationId = AppDiagnostics.createCorrelationId();
    _retryCount = 0;
    final submittedMessageId =
        _appendMessage(ConversationMessageRole.user, visible);
    if (!continuesLogicalRequest || _lastLogicalRequestId == null) {
      _lastLogicalRequestId = submittedMessageId;
      _clarificationLedger = ConversationClarificationLedger(
        sessionGeneration: _state.sessionGeneration,
      );
    }
    await _runRequest(
      requestText,
      addUserMessage: false,
      discussionOnly: effectiveDiscussionOnly,
      contextualFollowUp: contextualFollowUp,
      conversationHistory: conversationHistory,
      discussionTurnText: visible,
    );
  }

  Future<void> retryLastRequest() async {
    final text = _lastSubmittedText;
    if (_disposed ||
        text == null ||
        !_state.retryAvailable ||
        _state.isBusy ||
        _retryCount >= maximumBackendRetries) {
      return;
    }
    _retryCount++;
    await _runRequest(
      text,
      addUserMessage: false,
      discussionOnly: _lastSubmittedDiscussionOnly,
      contextualFollowUp: _lastSubmittedContextualFollowUp,
      conversationHistory: _lastSubmittedHistory,
      discussionTurnText: _lastSubmittedVisibleText,
    );
  }

  Future<void> _runRequest(
    String text, {
    required bool addUserMessage,
    bool discussionOnly = false,
    bool contextualFollowUp = false,
    List<ConversationHistoryMessage> conversationHistory = const [],
    String? discussionTurnText,
  }) async {
    if (addUserMessage) _appendMessage(ConversationMessageRole.user, text);
    final generation = _state.sessionGeneration;
    final requestId = '${_state.sessionId}:${++_requestSequence}';
    _setState(
      _state.copyWith(
        phase: ConversationSessionPhase.loadingContext,
        currentRequestId: requestId,
        retryAvailable: false,
        clearError: true,
      ),
    );
    try {
      await _loadReferenceHistory();
      final conversationalFollowUp = discussionOnly || contextualFollowUp;
      final pendingOutcome =
          conversationalFollowUp || _proactiveEventMoveAwaitingConfirmation
              ? null
              : await _resolvePending?.call(text, generation);
      final hasPendingRecurringResponsibility =
          _coordinator.hasPendingRecurringResponsibility;
      final contextualResponsibility = !conversationalFollowUp &&
              pendingOutcome == null &&
              !_proactiveEventMoveAwaitingConfirmation &&
              !hasPendingRecurringResponsibility &&
              _deferredRequestAfterResponsibilityClarification == null
          ? await _coordinator.beginContextualResponsibilityClarification(
              _profile,
              text,
            )
          : null;
      if (contextualResponsibility != null) {
        _deferredRequestAfterResponsibilityClarification = text;
      }
      final contextualOutcome = contextualResponsibility == null
          ? null
          : ConversationOutcome(
              reply: contextualResponsibility.message,
              responseKind: ConversationResponseKind.confirmationRequired,
            );
      final localOutcome = !conversationalFollowUp &&
              pendingOutcome == null &&
              contextualOutcome == null &&
              !hasPendingRecurringResponsibility &&
              !_proactiveEventMoveAwaitingConfirmation
          ? await _resolveLocalRequest?.call(text, generation)
          : null;
      final handledLocally = pendingOutcome != null ||
          contextualOutcome != null ||
          localOutcome != null;
      final outcome = pendingOutcome ??
          contextualOutcome ??
          localOutcome ??
          await _coordinator.send(
            input: ConversationInput(
              message: text,
              profile: _profile,
              sessionGeneration: generation,
              logicalRequestId: _lastLogicalRequestId,
              correlationId: _lastCorrelationId,
              discussionOnly: discussionOnly,
              contextualFollowUp: contextualFollowUp,
              conversationHistory: conversationHistory,
            ),
            executeAction: (action) => _executeAction(action, text, generation),
          );
      if (!_isCurrent(requestId, generation) || outcome == null) return;
      if (_proactiveEventMoveAwaitingConfirmation &&
          _coordinator.state.pendingAction?.type !=
              PendingConversationActionType.eventMutationConfirmation) {
        _proactiveEventMoveAwaitingConfirmation = false;
      }
      final clarificationDraft = outcome.epistemicClarification?.draft;
      String? clarificationReplyOverride;
      if (!handledLocally && clarificationDraft != null) {
        clarificationReplyOverride = await _prepareClarificationDraft?.call(
          clarificationDraft,
          generation,
          text,
        );
      }
      await _saveReferenceHistory();
      if (!_isCurrent(requestId, generation)) return;
      _setState(
          _state.copyWith(phase: ConversationSessionPhase.validatingResponse));
      if (outcome.reply.trim().isEmpty) {
        throw ChatBackendMalformedResponseException();
      }
      var responseKind = outcome.responseKind;
      var visibleReply = clarificationReplyOverride ?? outcome.reply;
      final clarification = outcome.epistemicClarification;
      if (!handledLocally &&
          clarificationDraft != null &&
          EventTitleService.isGeneric(clarificationDraft.title)) {
        visibleReply = EventTitleService.clarificationQuestion;
      }
      if (responseKind == ConversationResponseKind.clarificationRequired &&
          clarification != null) {
        final codes = clarification.missingFieldCodes;
        if (_clarificationLedger.sessionGeneration != generation) {
          _clarificationLedger = ConversationClarificationLedger(
            sessionGeneration: generation,
          );
        }
        if (_clarificationLedger.canAsk(codes, generation: generation)) {
          _clarificationLedger = _clarificationLedger.record(codes);
        } else {
          responseKind = ConversationResponseKind.cannotDetermine;
          visibleReply = ConversationSafeResponseCatalog.clarificationLimit;
        }
      } else if (responseKind != null &&
          responseKind != ConversationResponseKind.confirmationRequired) {
        _clarificationLedger = ConversationClarificationLedger(
          sessionGeneration: generation,
        );
      }
      _appendMessage(ConversationMessageRole.assistant, visibleReply);
      if (discussionOnly && _activeDiscussionSubject != null) {
        _recordActiveDiscussionTurn(
          userText: discussionTurnText ?? text,
          assistantText: visibleReply,
        );
      }
      if (!_isCurrent(requestId, generation)) return;
      final applicationPhase = _applicationPendingPhase?.call();
      final epistemicPhase =
          responseKind == ConversationResponseKind.clarificationRequired
              ? ConversationSessionPhase.awaitingClarification
              : responseKind == ConversationResponseKind.confirmationRequired
                  ? ConversationSessionPhase.awaitingConfirmation
                  : null;
      final pending = _coordinator.state.pendingAction != null ||
          applicationPhase != null ||
          epistemicPhase != null;
      _setState(
        _state.copyWith(
          phase: applicationPhase ??
              epistemicPhase ??
              (_coordinator.state.pendingAction != null
                  ? _pendingPhase(_coordinator.state.pendingAction!.type)
                  : ConversationSessionPhase.ready),
          clearCurrentRequest: true,
          retryAvailable: false,
          hasPendingAction: pending,
        ),
      );
      if (pending) {
        _emit(
          _state.phase == ConversationSessionPhase.awaitingClarification
              ? ConversationUiEffectType.showClarification
              : ConversationUiEffectType.showConfirmation,
        );
      }
      final deferred = _deferredRequestAfterResponsibilityClarification;
      if (deferred != null &&
          !_coordinator.hasPendingRecurringResponsibility &&
          _state.phase == ConversationSessionPhase.ready) {
        _deferredRequestAfterResponsibilityClarification = null;
        await _runRequest(deferred, addUserMessage: false);
        return;
      }
      await _runNextCompoundRequestIfReady();
    } catch (error) {
      if (!_isCurrent(requestId, generation)) return;
      final descriptor = error is ConversationTaskPersistenceException
          ? AppErrorCatalog.describe(AppErrorCode.storageFailure)
          : error is ConversationShoppingPersistenceException
              ? AppErrorCatalog.describe(
                  switch (error.code) {
                    'shopping_account_scope_mismatch' =>
                      AppErrorCode.accountScopeMismatch,
                    'shopping_revision_conflict' => AppErrorCode.conflict,
                    'shopping_payload_corrupted' ||
                    'shopping_mutation_not_found' =>
                      AppErrorCode.invalidArgument,
                    _ => AppErrorCode.storageFailure,
                  },
                )
              : AppErrorClassifier.classify(
                  error,
                  boundary: error is ChatBackendMalformedResponseException
                      ? AppErrorBoundaryKind.contract
                      : AppErrorBoundaryKind.application,
                );
      AppDiagnostics.record(
        component: 'conversation',
        domain: 'conversation',
        operation: 'submit',
        step: 'orchestrate',
        code: descriptor.code,
        severity: descriptor.severity,
        retryStrategy: descriptor.retryStrategy,
        correlationId: descriptor.correlationId,
        sourceExceptionType: error is ConversationTaskPersistenceException
            ? 'ConversationTaskPersistenceException'
            : error is ConversationShoppingPersistenceException
                ? 'ConversationShoppingPersistenceException'
                : AppErrorClassifier.safeExceptionType(error),
        metadata: {
          'retryable': descriptor.retryable,
          'retryStrategy': descriptor.retryStrategy.name,
        },
      );
      _appendMessage(
        ConversationMessageRole.assistant,
        descriptor.userMessage,
      );
      _setState(
        _state.copyWith(
          phase: descriptor.retryable
              ? ConversationSessionPhase.recoverableError
              : ConversationSessionPhase.blockingError,
          clearCurrentRequest: true,
          retryAvailable: descriptor.canRetryDirectly &&
              _retryCount < maximumBackendRetries,
          errorMessage: descriptor.userMessage,
        ),
      );
      _emit(
        ConversationUiEffectType.showRecoverableError,
        message: descriptor.userMessage,
      );
    }
  }

  Future<void> cancelCurrentRequest() async {
    if (_disposed || !_state.isBusy) return;
    _deferredRequestAfterResponsibilityClarification = null;
    _deferredCompoundRequests.clear();
    _clearActiveDiscussion();
    _coordinator.invalidateSession();
    _setState(
      _state.copyWith(
        sessionGeneration: _state.sessionGeneration + 1,
        phase: ConversationSessionPhase.cancelled,
        clearCurrentRequest: true,
        retryAvailable: false,
      ),
    );
    _clarificationLedger = ConversationClarificationLedger(
      sessionGeneration: _state.sessionGeneration,
    );
    _setState(_state.copyWith(phase: ConversationSessionPhase.ready));
  }

  void changeAccount(UserProfile profile) {
    _proactiveEventMoveAwaitingConfirmation = false;
    if (_disposed || identical(profile, _profile)) return;
    _proactiveInteractionRegistry.deactivateOwner(
      _accountScopeId,
      ownerId: _interactionOwnerId,
    );
    _profile = profile;
    final generation = _state.sessionGeneration + 1;
    _invalidateSession?.call(profile, generation);
    _setState(
      ConversationSessionState(
        sessionId: _idGenerator(),
        sessionGeneration: generation,
        phase: ConversationSessionPhase.ready,
        messages: const [],
        effects: const [],
      ),
    );
    _lastSubmittedText = null;
    _lastSubmittedDiscussionOnly = false;
    _lastSubmittedContextualFollowUp = false;
    _lastSubmittedHistory = const [];
    _lastSubmittedVisibleText = null;
    _lastLogicalRequestId = null;
    _lastCorrelationId = null;
    _retryCount = 0;
    _clarificationLedger = ConversationClarificationLedger(
      sessionGeneration: generation,
    );
    _coordinator.restoreValidatedReferenceHistory(
      const [],
      accountScopeId: _accountScopeId ?? 'unavailable-account',
      referenceDate: _clock().toUtc(),
    );
    _accountScopeId = null;
    _referenceHistoryLoaded = false;
    _deferredRequestAfterResponsibilityClarification = null;
    _deferredCompoundRequests.clear();
    _clearActiveDiscussion();
  }

  Future<void> _runNextCompoundRequestIfReady() async {
    if (_disposed ||
        _state.phase != ConversationSessionPhase.ready ||
        _coordinator.state.pendingAction != null ||
        _applicationPendingPhase?.call() != null ||
        _deferredRequestAfterResponsibilityClarification != null ||
        _deferredCompoundRequests.isEmpty) {
      return;
    }
    final next = _deferredCompoundRequests.removeAt(0);
    _lastSubmittedText = next;
    _lastSubmittedDiscussionOnly = false;
    _lastSubmittedContextualFollowUp = false;
    _lastSubmittedHistory = _buildConversationHistory();
    _lastLogicalRequestId = _idGenerator();
    _lastCorrelationId = AppDiagnostics.createCorrelationId();
    _retryCount = 0;
    _clarificationLedger = ConversationClarificationLedger(
      sessionGeneration: _state.sessionGeneration,
    );
    await _runRequest(
      next,
      addUserMessage: false,
      conversationHistory: _lastSubmittedHistory,
    );
  }

  bool _shouldUseContextualFollowUp(
    String value, {
    required bool discussionOnly,
    required bool continuesLogicalRequest,
  }) {
    if (discussionOnly ||
        continuesLogicalRequest ||
        _coordinator.state.pendingAction != null ||
        _applicationPendingPhase?.call() != null ||
        _isExplicitActionRequest(value)) {
      return false;
    }
    final assistant = _state.messages.reversed
        .where((message) => message.role == ConversationMessageRole.assistant)
        .firstOrNull;
    if (assistant == null || !assistant.text.trim().endsWith('?')) return false;
    final trimmed = value.trim();
    if (trimmed.endsWith('?') || _looksLikeStandaloneQuestion(trimmed)) {
      return false;
    }
    return trimmed.split(RegExp(r'\s+')).length <= 12;
  }

  bool _looksLikeStandaloneQuestion(String value) {
    final normalized =
        value.toLowerCase().replaceAll(RegExp(r"[’']"), ' ').trim();
    return RegExp(
      r'^(qui|que|quoi|quand|ou|où|comment|pourquoi|combien|quel|quelle|'
      r'quels|quelles|est ce que)\b',
    ).hasMatch(normalized);
  }

  List<ConversationHistoryMessage> _buildConversationHistory() {
    final history = <ConversationHistoryMessage>[];
    for (final message in _state.messages.reversed) {
      if (history.length >=
          ConversationTransportContract.maximumHistoryMessages) {
        break;
      }
      final entry = ConversationHistoryMessage(
        role:
            message.role == ConversationMessageRole.user ? 'user' : 'assistant',
        text: _truncateHistoryMessage(message.text),
      );
      final candidate = <ConversationHistoryMessage>[entry, ...history];
      final encodedBytes = utf8
          .encode(
            jsonEncode(
              candidate.map((item) => item.toJson()).toList(growable: false),
            ),
          )
          .length;
      if (encodedBytes <=
          ConversationTransportContract.maximumHistoryUtf8Bytes) {
        history.insert(0, entry);
      }
    }
    return List.unmodifiable(history);
  }

  String _truncateHistoryMessage(String value) {
    final limit = ConversationTransportContract.maximumHistoryMessageCharacters;
    if (value.length <= limit) return value;
    var start = value.length - limit;
    final codeUnit = value.codeUnitAt(start);
    if (codeUnit >= 0xDC00 && codeUnit <= 0xDFFF) start++;
    return value.substring(start);
  }

  String _buildActiveDiscussionRequest(String currentMessage) {
    final subject = _truncateDiscussionPart(
      _activeDiscussionSubject ?? '',
      maximumCharacters: 1100,
    );
    final transcript = _truncateDiscussionPart(
      _activeDiscussionTranscript,
      maximumCharacters: 800,
      keepEnd: true,
    );
    final current = _truncateDiscussionPart(
      currentMessage,
      maximumCharacters: 1800,
    );
    return <String>[
      'Contexte de la discussion choisie par l’utilisatrice : $subject',
      if (transcript.isNotEmpty) 'Échanges utiles : $transcript',
      'Nouveau message de l’utilisatrice : $current',
      'Continue naturellement sur ce même sujet. Ne repose pas une question '
          'dont la réponse figure déjà dans ce contexte. Si le nouveau message '
          'change clairement de sujet, réponds simplement au nouveau sujet. '
          'Ne crée, ne modifie et ne supprime rien dans cette discussion.',
    ].join('\n');
  }

  void _recordActiveDiscussionTurn({
    required String userText,
    required String assistantText,
  }) {
    final addition = '\nUtilisatrice : ${userText.trim()}'
        '\nZelia : ${assistantText.trim()}';
    _activeDiscussionTranscript = _truncateDiscussionPart(
      '$_activeDiscussionTranscript$addition',
      maximumCharacters: 2400,
      keepEnd: true,
    );
    _activeDiscussionTurns++;
    if (_activeDiscussionTurns > 6) _activeDiscussionTurns = 6;
  }

  void _clearActiveDiscussion() {
    _activeDiscussionSubject = null;
    _activeDiscussionTranscript = '';
    _activeDiscussionTurns = 0;
  }

  bool _isExplicitActionRequest(String value) {
    final normalized = value
        .toLowerCase()
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('à', 'a')
        .replaceAll('ù', 'u')
        .replaceAll('î', 'i')
        .replaceAll('ô', 'o');
    return RegExp(
      r'\b(ajoute|ajouter|cree|creer|reserve|reserver|note|noter|planifie|'
      r'planifier|supprime|supprimer|modifie|modifier|deplace|deplacer|'
      r'annule|annuler|enregistre|enregistrer)\b',
    ).hasMatch(normalized);
  }

  String _truncateDiscussionPart(
    String value, {
    required int maximumCharacters,
    bool keepEnd = false,
  }) {
    final trimmed = value.trim();
    if (trimmed.length <= maximumCharacters) return trimmed;
    return keepEnd
        ? trimmed.substring(trimmed.length - maximumCharacters)
        : trimmed.substring(0, maximumCharacters);
  }

  Future<void> _loadReferenceHistory() async {
    if (_referenceHistoryLoaded) return;
    _referenceHistoryLoaded = true;
    final store = _referenceHistoryStore;
    final scope = _accountScopeId;
    if (store == null || scope == null || scope.isEmpty) return;
    final now = _clock().toUtc();
    List<ValidatedConversationReference> references;
    try {
      references = await store.load(
        accountScopeId: scope,
        referenceDate: now,
      );
    } catch (error) {
      final descriptor = AppErrorClassifier.classify(
        error,
        boundary: AppErrorBoundaryKind.localStorage,
      );
      AppDiagnostics.record(
        component: 'conversation_reference_history',
        domain: 'conversation',
        operation: 'load',
        step: 'local_store',
        code: descriptor.code,
        severity: AppErrorSeverity.warning,
        retryStrategy: descriptor.retryStrategy,
        correlationId: descriptor.correlationId,
        sourceExceptionType: AppErrorClassifier.safeExceptionType(error),
      );
      references = const [];
    }
    _coordinator.restoreValidatedReferenceHistory(
      references,
      accountScopeId: scope,
      referenceDate: now,
    );
  }

  Future<void> _saveReferenceHistory() async {
    final store = _referenceHistoryStore;
    final scope = _accountScopeId;
    if (store == null || scope == null || scope.isEmpty) return;
    try {
      await store.save(
        accountScopeId: scope,
        references: _coordinator.validatedReferenceHistory,
        referenceDate: _clock().toUtc(),
      );
    } catch (error) {
      final descriptor = AppErrorClassifier.classify(
        error,
        boundary: AppErrorBoundaryKind.localStorage,
      );
      AppDiagnostics.record(
        component: 'conversation_reference_history',
        domain: 'conversation',
        operation: 'save',
        step: 'local_store',
        code: descriptor.code,
        severity: AppErrorSeverity.warning,
        retryStrategy: descriptor.retryStrategy,
        correlationId: descriptor.correlationId,
        sourceExceptionType: AppErrorClassifier.safeExceptionType(error),
      );
    }
  }

  String? _appendMessage(ConversationMessageRole role, String text) {
    if (_disposed || text.trim().isEmpty) return null;
    final message = ConversationVisibleMessage(
      id: _idGenerator(),
      role: role,
      text: text,
      createdAt: _clock().toUtc(),
    );
    _setState(
      _state.copyWith(
        messages: [..._state.messages, message],
        effects: _state.effects,
      ),
    );
    _messageStore
        .save(sessionId: _state.sessionId, role: role, text: message.text)
        .ignore();
    _emit(ConversationUiEffectType.scrollToLatest);
    return message.id;
  }

  void _clearQuickReplies() {
    if (_state.quickReplies.isEmpty) return;
    _setState(_state.copyWith(clearQuickReplies: true));
  }

  void _emit(ConversationUiEffectType type, {String? message}) {
    if (_disposed) return;
    final effect = ConversationUiEffect(
      id: _idGenerator(),
      type: type,
      sessionGeneration: _state.sessionGeneration,
      message: message,
    );
    _setState(_state.copyWith(effects: [..._state.effects, effect]));
  }

  Future<void> _consumeEffect(String effectId) async {
    if (_disposed) return;
    _setState(
      _state.copyWith(
        effects:
            _state.effects.where((effect) => effect.id != effectId).toList(),
      ),
    );
  }

  Future<void> _dismissError() async {
    if (_disposed) return;
    _setState(
      _state.copyWith(
        phase: ConversationSessionPhase.ready,
        clearError: true,
      ),
    );
  }

  bool _isCurrent(String requestId, int generation) =>
      !_disposed &&
      _state.currentRequestId == requestId &&
      _state.sessionGeneration == generation;

  void _setState(ConversationSessionState value) {
    if (_disposed) return;
    _state = value;
    _proactiveInteractionRegistry.replaceOwnerSources(
      _accountScopeId,
      ownerId: _interactionOwnerId,
      sources: _currentInteractionSources(value),
    );
    notifyListeners();
  }

  String get _interactionOwnerId => 'conversation:${_state.sessionId}';

  Set<ProactiveInteractionSource> _currentInteractionSources(
    ConversationSessionState value,
  ) {
    if (value.isBusy || value.phase == ConversationSessionPhase.pendingSync) {
      return const {ProactiveInteractionSource.conversationRequest};
    }
    final application = _applicationInteractionSources?.call() ?? const {};
    if (application.isNotEmpty) return application;
    final pending = _coordinator.state.pendingAction;
    if (pending == null) return const {};
    return {
      switch (pending.type) {
        PendingConversationActionType.taskClarification =>
          ProactiveInteractionSource.taskClarification,
        PendingConversationActionType.shoppingClarification =>
          ProactiveInteractionSource.shoppingClarification,
        PendingConversationActionType.eventConfirmation ||
        PendingConversationActionType.eventTargetClarification ||
        PendingConversationActionType.eventMutationConfirmation =>
          ProactiveInteractionSource.eventConfirmation,
        PendingConversationActionType.identityClarification =>
          ProactiveInteractionSource.identityClarification,
        PendingConversationActionType.identityCreation =>
          ProactiveInteractionSource.identityConfirmation,
        PendingConversationActionType.memoryConfirmation =>
          ProactiveInteractionSource.memoryConfirmation,
        PendingConversationActionType.autonomyConfirmation =>
          _autonomyInteractionSource(pending.autonomyMetadata.actionType),
      },
    };
  }

  static ProactiveInteractionSource _autonomyInteractionSource(
    ActionType actionType,
  ) =>
      switch (actionType) {
        ActionType.createTask => ProactiveInteractionSource.taskConfirmation,
        ActionType.createRoutine =>
          ProactiveInteractionSource.routineConfirmation,
        ActionType.confirmMemory =>
          ProactiveInteractionSource.memoryConfirmation,
        ActionType.createEvent ||
        ActionType.updateEvent ||
        ActionType.deleteEvent ||
        ActionType.smartPlanningReservation =>
          ProactiveInteractionSource.eventConfirmation,
        _ => ProactiveInteractionSource.identityConfirmation,
      };

  static ConversationSessionPhase _pendingPhase(
    PendingConversationActionType type,
  ) =>
      switch (type) {
        PendingConversationActionType.identityClarification ||
        PendingConversationActionType.shoppingClarification ||
        PendingConversationActionType.eventTargetClarification =>
          ConversationSessionPhase.awaitingClarification,
        _ => ConversationSessionPhase.awaitingConfirmation,
      };

  static String _defaultId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(Object())}';

  @override
  void dispose() {
    if (_disposed) return;
    final interactionOwnerId = _interactionOwnerId;
    _deferredRequestAfterResponsibilityClarification = null;
    _deferredCompoundRequests.clear();
    _clearActiveDiscussion();
    _coordinator.invalidateSession();
    _disposed = true;
    _state = _state.copyWith(
      sessionGeneration: _state.sessionGeneration + 1,
      phase: ConversationSessionPhase.disposed,
      clearCurrentRequest: true,
    );
    _proactiveInteractionRegistry.deactivateOwner(
      _accountScopeId,
      ownerId: interactionOwnerId,
    );
    _clarificationLedger = ConversationClarificationLedger(
      sessionGeneration: _state.sessionGeneration,
    );
    final backend = _ownedBackend;
    if (backend is ClosableChatBackendClient) backend.close();
    super.dispose();
  }
}
