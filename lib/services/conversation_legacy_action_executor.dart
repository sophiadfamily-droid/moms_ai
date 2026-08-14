import '../models/conversation_models.dart';
import '../models/conversation_epistemic_models.dart';
import '../models/event_model.dart';
import '../models/smart_planning_continuation.dart';
import '../models/task_model.dart';
import '../models/action_autonomy_policy.dart';
import 'action_handler_service.dart';
import 'chat_planning_helper_service.dart';
import 'conversation_coordinator.dart';
import 'conversation_turn_intent_service.dart';
import 'event_confirmation_service.dart';
import 'event_planning_conflict_service.dart';
import 'event_service.dart';
import 'event_title_service.dart';
import 'notification_service.dart';
import 'natural_date_service.dart';
import 'natural_duration_service.dart';
import 'natural_event_request_service.dart';
import 'natural_time_service.dart';
import 'memory_engine_service.dart';
import 'planner_engine_service.dart';
import 'smart_planning_continuation_coordinator.dart';
import 'smart_planning_service.dart';

final class ConversationLegacyActionExecutor {
  ConversationLegacyActionExecutor({
    required this.coordinator,
    this.smartPlanning,
    this.loadAutonomyPolicy,
    EventStartConflictChecker? eventStartConflictChecker,
    EventConflictChecker? eventConflictChecker,
    EventStartAlternativeSuggester? eventStartAlternativeSuggester,
    EventAlternativeSuggester? eventAlternativeSuggester,
    DateTime Function()? clock,
  })  : _eventStartConflictChecker =
            eventStartConflictChecker ?? EventService.getConflictEvent,
        _eventConflictChecker =
            eventConflictChecker ?? EventService.getOverlapConflict,
        _eventStartAlternativeSuggester = eventStartAlternativeSuggester,
        _eventAlternativeSuggester = eventAlternativeSuggester,
        _clock = clock ?? DateTime.now;

  final ConversationCoordinator coordinator;
  final SmartPlanningContinuationCoordinator? smartPlanning;
  final Future<ActionAutonomyPolicy> Function()? loadAutonomyPolicy;
  final EventStartConflictChecker _eventStartConflictChecker;
  final EventConflictChecker _eventConflictChecker;
  final EventStartAlternativeSuggester? _eventStartAlternativeSuggester;
  final EventAlternativeSuggester? _eventAlternativeSuggester;
  final DateTime Function() _clock;
  _PendingEventDraft? _pendingEventDraft;

  bool get hasPendingEventDraft => _pendingEventDraft != null;
  String? get pendingEventDraftId => _pendingEventDraft?.draftId;
  String? get pendingEventLogicalRequestId =>
      _pendingEventDraft?.logicalRequestId;
  String? get pendingEventExpectedFieldCode =>
      _pendingEventDraft?.expectedField.name;

  bool registerClarificationDraft(
    ConversationClarificationDraft draft,
    int sessionGeneration,
  ) {
    if (draft.draftType != ConversationClarificationDraftType.eventCreation ||
        draft.sessionGeneration != sessionGeneration ||
        !_clock().toUtc().isBefore(draft.expiresAt)) {
      return false;
    }
    _pendingEventDraft = _PendingEventDraft(
      draftId: draft.draftId,
      logicalRequestId: draft.logicalRequestId,
      sessionGeneration: sessionGeneration,
      expectedField: EventTitleService.isGeneric(draft.title)
          ? _PendingEventField.eventTitle
          : _PendingEventField.values.byName(draft.expectedField.name),
      action: {
        'type': 'event',
        'title': draft.title,
        'date': draft.date ?? '',
        'time': draft.startTime ?? '',
        'durationMinutes': draft.durationMinutes ?? 0,
        'travelGoMinutes': draft.travelGoMinutes ?? 0,
        'travelBackMinutes': draft.travelBackMinutes ?? 0,
        'marginMinutes': draft.marginMinutes ?? 0,
      },
      expiresAt: draft.expiresAt,
    );
    return true;
  }

  bool registerClarificationDraftFromMessage(
    ConversationClarificationDraft draft,
    int sessionGeneration,
    String userMessage,
  ) {
    return registerClarificationDraft(
      _enrichClarificationDraft(draft, userMessage),
      sessionGeneration,
    );
  }

  Future<String?> prepareClarificationDraftFromMessage(
    ConversationClarificationDraft draft,
    int sessionGeneration,
    String userMessage,
  ) async {
    final enriched = _enrichClarificationDraft(draft, userMessage);
    final date = enriched.date;
    final time = enriched.startTime;
    if (date != null &&
        time != null &&
        !EventTitleService.isGeneric(enriched.title)) {
      final conflict = await _eventStartConflictChecker(
        startDateTimeIso: ChatPlanningHelperService.buildStartDateTimeIso(
          date: date,
          time: time,
        ),
      );
      if (conflict != null) {
        final conflictingStartDateTimeIso =
            ChatPlanningHelperService.buildStartDateTimeIso(
          date: date,
          time: time,
        );
        final suggestion = await _eventStartAlternativeSuggester?.call(
          startDateTimeIso: conflictingStartDateTimeIso,
          conflict: conflict,
        );
        _pendingEventDraft = _PendingEventDraft(
          draftId: enriched.draftId,
          logicalRequestId: enriched.logicalRequestId,
          sessionGeneration: sessionGeneration,
          expectedField: _PendingEventField.conflictAlternativeTime,
          action: {
            'type': 'event',
            'title': enriched.title,
            'date': date,
            'time': '',
            'durationMinutes': enriched.durationMinutes ?? 0,
            'travelGoMinutes': enriched.travelGoMinutes ?? 0,
            'travelBackMinutes': enriched.travelBackMinutes ?? 0,
            'marginMinutes': enriched.marginMinutes ?? 0,
          },
          expiresAt: enriched.expiresAt,
          suggestedAlternativeStart: suggestion,
        );
        return _conflictReply(conflict, suggestion);
      }
    }
    registerClarificationDraft(enriched, sessionGeneration);
    return null;
  }

  ConversationClarificationDraft _enrichClarificationDraft(
    ConversationClarificationDraft draft,
    String userMessage,
  ) {
    final parsedDate = draft.date?.trim().isNotEmpty == true
        ? draft.date
        : NaturalDateService.resolveDateFromText(
            userMessage,
            now: _clock(),
          );
    final parsedTime = draft.startTime?.trim().isNotEmpty == true
        ? draft.startTime
        : NaturalTimeService.parseTime(userMessage);
    final enriched = ConversationClarificationDraft(
      schemaVersion: draft.schemaVersion,
      draftType: draft.draftType,
      logicalRequestId: draft.logicalRequestId,
      draftId: draft.draftId,
      title: draft.title,
      date: parsedDate?.trim().isEmpty == true ? null : parsedDate,
      startTime: parsedTime?.trim().isEmpty == true ? null : parsedTime,
      durationMinutes: draft.durationMinutes,
      travelGoMinutes: draft.travelGoMinutes,
      travelBackMinutes: draft.travelBackMinutes,
      marginMinutes: draft.marginMinutes,
      expectedField: draft.expectedField,
      createdAt: draft.createdAt,
      expiresAt: draft.expiresAt,
      sessionGeneration: draft.sessionGeneration,
    );
    return enriched;
  }

  void invalidate() {
    _pendingEventDraft = null;
  }

  Future<ConversationOutcome?> resolveLocalRequest(
    String message,
    int sessionGeneration,
  ) async {
    final planning = await smartPlanning?.tryStartExplicitSlotRequest(
      text: message,
      sessionGeneration: sessionGeneration,
    );
    if (planning != null) {
      return ConversationOutcome(reply: planning.message);
    }
    final action = NaturalEventRequestService.parseAction(
      message,
      now: _clock(),
    );
    if (action == null) return null;
    final outcome = await execute(action, message, sessionGeneration);
    return ConversationOutcome(reply: outcome.message);
  }

  Future<ConversationOutcome?> resolvePending(
    String answer,
    int sessionGeneration,
  ) async {
    final eventDraft = await _resolvePendingEventDraft(
      answer,
      sessionGeneration,
    );
    if (eventDraft != null) return eventDraft;
    final shoppingClarification =
        await coordinator.resolvePendingShoppingClarification(
      answer: answer,
      sessionGeneration: sessionGeneration,
    );
    if (shoppingClarification != null) {
      return ConversationOutcome(reply: shoppingClarification.message);
    }
    final taskClarification = await coordinator.resolvePendingTaskClarification(
      answer: answer,
      sessionGeneration: sessionGeneration,
    );
    if (taskClarification != null) {
      return ConversationOutcome(reply: taskClarification.message);
    }
    final autonomyResolution =
        await coordinator.resolvePendingAutonomyConfirmation(
      answer: answer,
      sessionGeneration: sessionGeneration,
      executeAction: (action) => execute(
        action,
        answer,
        sessionGeneration,
      ),
    );
    if (autonomyResolution != null) {
      return ConversationOutcome(reply: autonomyResolution.message);
    }
    final activePlanning = smartPlanning?.active;
    if (activePlanning?.step == SmartPlanningContinuationStep.planningConsent &&
        !_isPlanningConsentAnswer(answer)) {
      smartPlanning!.invalidate();
    }
    final planningResolution = smartPlanning?.active == null
        ? null
        : await smartPlanning?.resolve(
            answer,
            sessionGeneration: sessionGeneration,
          );
    if (planningResolution != null) return planningResolution;
    final eventMutationId =
        coordinator.state.pendingAction?.canonicalConfirmation?.mutationId;
    final eventResolution = await coordinator.resolvePendingEventConfirmation(
      answer: answer,
      isPositiveAnswer: PlannerEngineService.isPositiveAnswer,
      isNegativeAnswer: PlannerEngineService.isNegativeAnswer,
      cancellationMessage: EventConfirmationService.buildCancellationMessage,
      expectedAnswerMessage:
          EventConfirmationService.buildExpectedAnswerMessage,
      execute: (event) async {
        final result = await EventConfirmationService.confirm(
          event: event,
          conflictChecker: _eventConflictChecker,
          addEvent: EventService.addEvent,
          addEvents: EventService.addEvents,
          showNotification: NotificationService.showNotification,
          mutationId: eventMutationId,
        );
        return result.message;
      },
    );
    if (eventResolution != null) {
      return ConversationOutcome(reply: eventResolution.message);
    }
    final memoryResolution = await coordinator.resolvePendingMemoryConfirmation(
      answer: answer,
      referenceDate: DateTime.now(),
    );
    return memoryResolution == null
        ? null
        : ConversationOutcome(reply: memoryResolution.message);
  }

  Future<ConversationOutcome?> _resolvePendingEventDraft(
    String answer,
    int sessionGeneration,
  ) async {
    final pending = _pendingEventDraft;
    if (pending == null) return null;
    if (pending.sessionGeneration != sessionGeneration ||
        !_clock().isBefore(pending.expiresAt)) {
      _pendingEventDraft = null;
      return const ConversationOutcome(
        reply: 'Cette demande de rendez-vous a expiré. Tu peux la reformuler.',
      );
    }
    final turn = const ConversationTurnIntentService().interpret(answer);
    if (turn.intent == ConversationTurnIntent.ambiguousControl) {
      return const ConversationOutcome(
        reply: 'Je garde ce rendez-vous en cours. Tu veux continuer à le '
            'préparer ?',
      );
    }
    if (turn.intent == ConversationTurnIntent.cancelCurrentFlow) {
      _pendingEventDraft = null;
      return const ConversationOutcome(
        reply: 'D’accord, on laisse tomber ce rendez-vous.',
      );
    }
    if (turn.intent == ConversationTurnIntent.switchToNewRequest) {
      _pendingEventDraft = null;
      return null;
    }
    final effectiveAnswer =
        turn.intent == ConversationTurnIntent.reviseCurrentAnswer
            ? turn.semanticContent
            : answer;
    if (turn.intent == ConversationTurnIntent.rejectCurrentProposal ||
        PlannerEngineService.isNegativeAnswer(effectiveAnswer)) {
      if (pending.expectedField == _PendingEventField.conflictAlternativeTime &&
          pending.suggestedAlternativeStart != null) {
        _pendingEventDraft = pending.copyWith(clearSuggestedAlternative: true);
        return const ConversationOutcome(
          reply: 'D’accord. Quel autre horaire te conviendrait ?',
        );
      }
      _pendingEventDraft = null;
      return const ConversationOutcome(
        reply: 'D’accord, on laisse tomber ce rendez-vous.',
      );
    }
    if (MemoryEngineService.hasExplicitMemoryRequest(effectiveAnswer)) {
      _pendingEventDraft = null;
      return null;
    }

    final action = Map<String, dynamic>.from(pending.action);
    switch (pending.expectedField) {
      case _PendingEventField.eventTitle:
        if (EventTitleService.shouldRouteIndependently(effectiveAnswer)) {
          _pendingEventDraft = null;
          return null;
        }
        final title = EventTitleService.titleFromMotif(effectiveAnswer);
        if (title == null) {
          return const ConversationOutcome(
            reply: EventTitleService.precisionQuestion,
          );
        }
        action['title'] = title;
        break;
      case _PendingEventField.date:
        final date = NaturalDateService.resolveDateFromText(
          effectiveAnswer,
          now: _clock(),
        );
        if (date.isEmpty) return null;
        action['date'] = date;
        break;
      case _PendingEventField.time:
        final time = NaturalTimeService.parseTime(effectiveAnswer);
        if (time.isEmpty) return null;
        action['time'] = time;
        break;
      case _PendingEventField.duration:
        final minutes = _contextualDurationMinutes(
          effectiveAnswer,
          NaturalDurationExpectedField.duration,
        );
        if (minutes <= 0) {
          final revised = _applyDateOrTimeRevision(action, effectiveAnswer);
          if (revised == null) {
            if (PlannerEngineService.isPositiveAnswer(effectiveAnswer)) {
              return const ConversationOutcome(
                reply: 'Indique-moi la durée, par exemple 1h ou 45 minutes.',
              );
            }
            return null;
          }
          _pendingEventDraft = pending.copyWith(action: revised);
          return const ConversationOutcome(
            reply: 'C’est mis à jour. Combien de temps dure le rendez-vous ?',
          );
        }
        action['durationMinutes'] = minutes;
        break;
      case _PendingEventField.travelGo:
        final minutes = _travelMinutes(
          effectiveAnswer,
          NaturalDurationExpectedField.travelGo,
        );
        if (minutes == null) return null;
        action['travelGoMinutes'] = minutes;
        _pendingEventDraft = pending.copyWith(
          expectedField: _PendingEventField.travelBack,
          action: action,
        );
        return const ConversationOutcome(
          reply: 'Combien de temps faut-il prévoir pour le trajet retour ?',
        );
      case _PendingEventField.travelBack:
        final minutes = _travelMinutes(
          effectiveAnswer,
          NaturalDurationExpectedField.travelBack,
        );
        if (minutes == null) return null;
        action['travelBackMinutes'] = minutes;
        _pendingEventDraft = pending.copyWith(
          expectedField: _PendingEventField.margin,
          action: action,
        );
        return const ConversationOutcome(
          reply: 'Quelle marge veux-tu prévoir ? Tu peux répondre aucune.',
        );
      case _PendingEventField.margin:
        final minutes = _marginMinutes(effectiveAnswer);
        if (minutes == null) return null;
        action['marginMinutes'] = minutes;
        action['usesSeparateTravelTimes'] = true;
        break;
      case _PendingEventField.conflictAlternativeTime:
        final suggested = pending.suggestedAlternativeStart;
        if (suggested != null &&
            PlannerEngineService.isPositiveAnswer(effectiveAnswer)) {
          action['date'] = EventService.formatIsoDate(suggested);
          action['time'] = EventService.formatIsoTime(suggested);
          break;
        }
        final revisedDate = NaturalDateService.resolveDateFromText(
          effectiveAnswer,
          now: _clock(),
        );
        final revisedTime = NaturalTimeService.parseTime(effectiveAnswer);
        if (revisedDate.isNotEmpty) action['date'] = revisedDate;
        if (revisedTime.isEmpty) {
          if (revisedDate.isNotEmpty) {
            _pendingEventDraft = pending.copyWith(action: action);
            return const ConversationOutcome(
              reply: 'À quelle heure précise veux-tu déplacer ce rendez-vous ?',
            );
          }
          if (_hasAmbiguousConflictAlternative(effectiveAnswer)) {
            return const ConversationOutcome(
              reply: 'À quelle heure précise veux-tu déplacer ce rendez-vous ?',
            );
          }
          return null;
        }
        action['time'] = revisedTime;
        break;
      case _PendingEventField.conflictAlternativeDate:
        final revised = _applyDateOrTimeRevision(action, effectiveAnswer);
        final revisedDate = revised?['date']?.toString() ?? '';
        if (revised == null || revisedDate.isEmpty) return null;
        action['date'] = revisedDate;
        if ((revised['time']?.toString() ?? '').isEmpty) {
          _pendingEventDraft = pending.copyWith(
            expectedField: _PendingEventField.conflictAlternativeTime,
            action: action,
          );
          return const ConversationOutcome(
            reply: 'À quelle heure précise veux-tu déplacer ce rendez-vous ?',
          );
        }
        action['time'] = revised['time'];
        break;
      case _PendingEventField.confirmation:
        return null;
    }

    final outcome = await execute(action, effectiveAnswer, sessionGeneration);
    return ConversationOutcome(reply: outcome.message);
  }

  Map<String, dynamic>? _applyDateOrTimeRevision(
    Map<String, dynamic> action,
    String answer,
  ) {
    final date = NaturalDateService.resolveDateFromText(
      answer,
      now: _clock(),
    );
    final time = NaturalTimeService.parseTime(answer);
    if (date.isEmpty && time.isEmpty) return null;
    if (date.isNotEmpty) action['date'] = date;
    if (time.isNotEmpty) action['time'] = time;
    return action;
  }

  static int _contextualDurationMinutes(
    String answer,
    NaturalDurationExpectedField expectedField,
  ) {
    final contextual = NaturalDurationService.parseMinutes(
      answer,
      expectedField: expectedField,
    );
    if (contextual > 0) return contextual;
    final legacy = ChatPlanningHelperService.parseDurationMinutes(answer);
    if (legacy > 0) return legacy;
    return SmartPlanningService.parseTravelMinutes(answer);
  }

  static int? _travelMinutes(
    String answer,
    NaturalDurationExpectedField expectedField,
  ) {
    if (PlannerEngineService.isNoTravelAnswer(answer) ||
        _normalized(answer) == 'aucun' ||
        _normalized(answer) == 'aucune' ||
        _isExplicitZeroDuration(answer)) {
      return 0;
    }
    final minutes = _contextualDurationMinutes(answer, expectedField);
    return minutes > 0 ? minutes : null;
  }

  static int? _marginMinutes(String answer) {
    final value = _normalized(answer);
    if (value == 'aucun' ||
        value == 'aucune' ||
        value == 'pas de marge' ||
        value == 'sans marge' ||
        _isExplicitZeroDuration(answer)) {
      return 0;
    }
    final minutes = _contextualDurationMinutes(
      answer,
      NaturalDurationExpectedField.margin,
    );
    return minutes > 0 ? minutes : null;
  }

  static bool _isExplicitZeroDuration(String answer) {
    final value = _normalized(answer).replaceAll(RegExp(r'\s+'), ' ');
    return RegExp(
      r'^(0+|zero|zéro)\s*(min|minute|minutes|h|heure|heures)?$',
    ).hasMatch(value);
  }

  static String _normalized(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('’', "'")
      .replaceAll(RegExp(r'[.!?]+$'), '');

  static bool _hasAmbiguousConflictAlternative(String answer) {
    final value = _normalized(answer);
    return const {
      'plus tard',
      'apres',
      'après',
      'dans la soiree',
      'dans la soirée',
    }.contains(value);
  }

  Future<ConversationActionOutcome> execute(
    Map<String, dynamic> action,
    String userMessage,
    int sessionGeneration,
  ) async {
    final effectiveUserMessage =
        action['originalMessage']?.toString() ?? userMessage;
    final policy =
        coordinator.lastAutonomyPolicy ?? await loadAutonomyPolicy?.call();
    if (policy != null) {
      coordinator.observeAutonomyPolicyForLocalAction(policy);
      smartPlanning?.updateAutonomyPolicy(policy);
    }
    final result = await ActionHandlerService.handleAction(
      action: action,
      currentUserMessage: effectiveUserMessage,
      normalizeTime: ChatPlanningHelperService.normalizeTime,
      parseDurationMinutes: ChatPlanningHelperService.parseDurationMinutes,
      weekdayFromText: () => _weekdayFromText(effectiveUserMessage),
      messageLooksRecurringWeekly: () => _looksRecurring(effectiveUserMessage),
      nextDateForWeekday: _nextDateForWeekday,
      eventNeedsTravel: _eventNeedsTravel,
      buildStartDateTimeIso: ChatPlanningHelperService.buildStartDateTimeIso,
      buildEndDateTimeIso: ChatPlanningHelperService.buildEndDateTimeIso,
      endTimeFromDuration: ChatPlanningHelperService.endTimeFromDuration,
      eventStartConflictChecker: _eventStartConflictChecker,
      eventConflictChecker: _eventConflictChecker,
    );
    DateTime? conflictSuggestion;
    final conflictEvent = result.conflictEvent;
    if (conflictEvent != null) {
      final candidate = result.conflictingCandidateEvent;
      if (candidate != null && _eventAlternativeSuggester != null) {
        conflictSuggestion = await _eventAlternativeSuggester(
          candidate: candidate,
          conflict: conflictEvent,
        );
      } else if (result.conflictingStartDateTimeIso != null) {
        conflictSuggestion = await _eventStartAlternativeSuggester?.call(
          startDateTimeIso: result.conflictingStartDateTimeIso!,
          conflict: conflictEvent,
        );
      }
    }
    final resultMessage = result.conflictEvent == null
        ? result.message
        : _conflictReply(result.conflictEvent!, conflictSuggestion);
    final event = result.pendingConfirmationEvent;
    if (event != null) {
      _pendingEventDraft = null;
      final participant = result.eventParticipant;
      if (participant == null) {
        coordinator.setPendingEventConfirmation(event);
      } else {
        final resolution = await coordinator.beginEventParticipantIdentity(
          event: event,
          participant: participant,
          confirmationMessage: result.message,
        );
        return ConversationActionOutcome(message: resolution.message);
      }
    }
    final pendingEvent = result.pendingDateEvent ??
        result.pendingTitleEvent ??
        result.pendingTimeEvent ??
        result.pendingDurationEvent ??
        result.pendingTravelEvent ??
        result.pendingConflictResolutionEvent;
    if (pendingEvent != null) {
      final current = _pendingEventDraft;
      final preservesCurrentDraft =
          current != null && current.sessionGeneration == sessionGeneration;
      _pendingEventDraft = _PendingEventDraft(
        draftId: preservesCurrentDraft
            ? current.draftId
            : 'local-event-$sessionGeneration-${_clock().microsecondsSinceEpoch}',
        logicalRequestId: preservesCurrentDraft
            ? current.logicalRequestId
            : 'local-event-$sessionGeneration',
        sessionGeneration: sessionGeneration,
        expectedField: result.pendingTitleEvent != null
            ? _PendingEventField.eventTitle
            : result.pendingConflictResolutionEvent != null
                ? _PendingEventField.conflictAlternativeTime
                : result.pendingDateEvent != null
                    ? _PendingEventField.date
                    : result.pendingTimeEvent != null
                        ? _PendingEventField.time
                        : result.pendingDurationEvent != null
                            ? _PendingEventField.duration
                            : _PendingEventField.travelGo,
        action: pendingEvent,
        expiresAt: preservesCurrentDraft
            ? current.expiresAt
            : _clock().toUtc().add(const Duration(minutes: 15)),
        suggestedAlternativeStart: conflictSuggestion,
      );
    } else if (action['type'] == 'event' && event == null) {
      _pendingEventDraft = null;
    }
    final pendingTask = result.pendingSmartPlanningTask;
    final task = pendingTask?['task'];
    final planningTitle = task is TaskModel ? task.title : null;
    SmartPlanningContinuationResult? planningProposal;
    if (task is TaskModel && smartPlanning != null) {
      planningProposal = smartPlanning!.beginTaskPlanning(
        task: task,
        originalMessage:
            pendingTask?['originalMessage']?.toString() ?? effectiveUserMessage,
        sessionGeneration: sessionGeneration,
      );
    }
    final creationMessage =
        resultMessage.trim().isEmpty ? 'C’est fait.' : resultMessage.trim();
    return ConversationActionOutcome(
      message: planningProposal == null
          ? resultMessage
          : '$creationMessage ${planningProposal.message}',
      planningTitle: planningTitle,
    );
  }

  static bool _isPlanningConsentAnswer(String answer) {
    if (PlannerEngineService.isPositiveAnswer(answer) ||
        PlannerEngineService.isNegativeAnswer(answer)) {
      return true;
    }
    final normalized =
        answer.trim().toLowerCase().replaceAll(RegExp(r'[.!?]+$'), '').trim();
    return const {
      'peut-être',
      'peut etre',
      'je ne sais pas',
      'pas sûr',
      'pas sur',
    }.contains(normalized);
  }

  static bool _looksRecurring(String text) {
    final value = text.toLowerCase();
    return value.contains('tous les') ||
        value.contains('toutes les') ||
        value.contains('chaque ') ||
        value.contains('par semaine') ||
        value.contains('hebdomadaire');
  }

  static int _weekdayFromText(String text) {
    final value = text.toLowerCase();
    if (value.contains('lundi')) return 1;
    if (value.contains('mardi')) return 2;
    if (value.contains('mercredi')) return 3;
    if (value.contains('jeudi')) return 4;
    if (value.contains('vendredi')) return 5;
    if (value.contains('samedi')) return 6;
    if (value.contains('dimanche')) return 7;
    return 0;
  }

  static String _nextDateForWeekday(int weekday) {
    if (weekday <= 0) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var days = weekday - today.weekday;
    if (days < 0) days += 7;
    final target = today.add(Duration(days: days));
    return '${target.year.toString().padLeft(4, '0')}-'
        '${target.month.toString().padLeft(2, '0')}-'
        '${target.day.toString().padLeft(2, '0')}';
  }

  static bool _eventNeedsTravel(Map<String, dynamic> action) {
    final value = [
      action['title'],
      action['category'],
      action['notes'],
    ].join(' ').toLowerCase();
    return ![
      'maison',
      'chez moi',
      'à domicile',
      'a domicile',
      'visio',
      'en ligne',
      'téléphone',
      'telephone',
      'appel',
    ].any(value.contains);
  }

  static String _conflictReply(
    EventModel conflict,
    DateTime? suggestedStart,
  ) {
    if (suggestedStart == null) {
      return 'À cette heure-là, tu as déjà ${conflict.title}. '
          'Quel autre horaire te conviendrait ?';
    }
    return 'À cette heure-là, tu as déjà ${conflict.title}. '
        'Je peux te proposer ${_formatFrenchTime(suggestedStart)}. '
        'Est-ce que ça te va ?';
  }

  static String _formatFrenchTime(DateTime value) => value.minute == 0
      ? '${value.hour} h'
      : '${value.hour} h ${value.minute.toString().padLeft(2, '0')}';
}

enum _PendingEventField {
  eventTitle,
  date,
  time,
  duration,
  travelGo,
  travelBack,
  margin,
  conflictAlternativeTime,
  conflictAlternativeDate,
  confirmation,
}

final class _PendingEventDraft {
  _PendingEventDraft({
    required this.draftId,
    required this.logicalRequestId,
    required this.sessionGeneration,
    required this.expectedField,
    required Map<String, dynamic> action,
    required this.expiresAt,
    this.suggestedAlternativeStart,
  }) : action = Map.unmodifiable(action);

  final int sessionGeneration;
  final String draftId;
  final String logicalRequestId;
  final _PendingEventField expectedField;
  final Map<String, dynamic> action;
  final DateTime expiresAt;
  final DateTime? suggestedAlternativeStart;

  _PendingEventDraft copyWith({
    _PendingEventField? expectedField,
    Map<String, dynamic>? action,
    DateTime? suggestedAlternativeStart,
    bool clearSuggestedAlternative = false,
  }) =>
      _PendingEventDraft(
        draftId: draftId,
        logicalRequestId: logicalRequestId,
        sessionGeneration: sessionGeneration,
        expectedField: expectedField ?? this.expectedField,
        action: action ?? this.action,
        expiresAt: expiresAt,
        suggestedAlternativeStart: clearSuggestedAlternative
            ? null
            : suggestedAlternativeStart ?? this.suggestedAlternativeStart,
      );
}
