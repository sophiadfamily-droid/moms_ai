import '../models/conversation_models.dart';
import '../models/event_model.dart';
import '../models/smart_planning_continuation.dart';
import '../models/task_model.dart';
import '../models/user_profile.dart';
import 'chat_planning_helper_service.dart';
import 'event_service.dart';
import 'memory_planning_compatibility_service.dart';
import 'notification_service.dart';
import 'planner_engine_service.dart';
import 'planning_proposal_engine.dart';
import 'planning_proposal_selection_service.dart';
import 'planning_proposal_service.dart';
import 'selected_slot_revalidation_service.dart';
import 'selected_slot_schedule_service.dart';
import 'smart_planning_response_builder.dart';
import 'smart_planning_service.dart';

abstract interface class SmartPlanningContinuationGateway {
  Future<List<TaskModel>> relatedTasks(TaskModel task, String originalMessage);

  Future<PlanningProposalEngineResult> findOptions({
    required DateTime startDate,
    required int totalMinutes,
    required int searchDays,
  });

  Future<SmartPlanningProposal> buildProposal({
    required TaskModel task,
    required String originalMessage,
    required int actionMinutes,
    required int travelGoMinutes,
    required int travelBackMinutes,
    required List<TaskModel> groupedTasks,
  });

  Future<SelectedSlotRevalidationResult> revalidate({
    required EventModel event,
    required DateTime protectedStart,
    required int totalMinutes,
  });

  Future<EventModel?> conflict(EventModel event);

  Future<void> addEvent(EventModel event);
}

final class ProductionSmartPlanningContinuationGateway
    implements SmartPlanningContinuationGateway {
  ProductionSmartPlanningContinuationGateway(UserProfile profile)
      : _profile = profile;

  UserProfile _profile;

  void updateProfile(UserProfile profile) => _profile = profile;

  Future<List<Map<String, dynamic>>> _reasoning() =>
      MemoryPlanningCompatibilityService.build(profile: _profile);

  @override
  Future<List<TaskModel>> relatedTasks(
    TaskModel task,
    String originalMessage,
  ) =>
      SmartPlanningService.getRelatedOutsideTasks(
        mainTask: task,
        originalMessage: originalMessage,
      );

  @override
  Future<PlanningProposalEngineResult> findOptions({
    required DateTime startDate,
    required int totalMinutes,
    required int searchDays,
  }) async =>
      PlanningProposalEngine.findBestOptions(
        startDate: startDate,
        totalMinutes: totalMinutes,
        reasoning: await _reasoning(),
        searchDays: searchDays,
        maxOptions: 3,
      );

  @override
  Future<SmartPlanningProposal> buildProposal({
    required TaskModel task,
    required String originalMessage,
    required int actionMinutes,
    required int travelGoMinutes,
    required int travelBackMinutes,
    required List<TaskModel> groupedTasks,
  }) async =>
      PlanningProposalService.buildFromTravelPlanning(
        task: task,
        originalMessage: originalMessage,
        actionMinutes: actionMinutes,
        travelGoMinutes: travelGoMinutes,
        travelBackMinutes: travelBackMinutes,
        groupedTasks: groupedTasks,
        memoryReasoning: await _reasoning(),
      );

  @override
  Future<SelectedSlotRevalidationResult> revalidate({
    required EventModel event,
    required DateTime protectedStart,
    required int totalMinutes,
  }) async =>
      SelectedSlotRevalidationService.revalidate(
        candidate: event,
        protectedStart: protectedStart,
        totalMinutes: totalMinutes,
        reasoning: await _reasoning(),
      );

  @override
  Future<EventModel?> conflict(EventModel event) =>
      EventService.getOverlapConflict(candidate: event);

  @override
  Future<void> addEvent(EventModel event) async {
    await EventService.addEvent(event);
    await NotificationService.showNotification(
      title: 'Créneau réservé 📅',
      body: event.title,
    );
  }
}

final class SmartPlanningContinuationCoordinator {
  static const Duration continuationLifetime = Duration(hours: 2);
  static const int maximumCompletedMutationReceipts = 128;

  SmartPlanningContinuationCoordinator({
    required SmartPlanningContinuationGateway gateway,
    DateTime Function()? clock,
    String Function()? idGenerator,
  })  : _gateway = gateway,
        _clock = clock ?? DateTime.now,
        _idGenerator = idGenerator ??
            (() => DateTime.now().microsecondsSinceEpoch.toString());

  final SmartPlanningContinuationGateway _gateway;
  final DateTime Function() _clock;
  final String Function() _idGenerator;
  SmartPlanningContinuation? _active;
  final Set<String> _completedMutationIds = <String>{};

  SmartPlanningContinuation? get active => _active;
  bool get hasActive => _active != null;

  void invalidate() => _active = null;

  SmartPlanningContinuationResult beginTaskPlanning({
    required TaskModel task,
    required String originalMessage,
    required int sessionGeneration,
  }) {
    _active = _new(
      type: SmartPlanningContinuationType.taskPlanning,
      step: SmartPlanningContinuationStep.planningConsent,
      task: task,
      originalMessage: originalMessage,
      sessionGeneration: sessionGeneration,
    );
    return SmartPlanningContinuationResult(
      status: SmartPlanningContinuationResultStatus.confirmationRequired,
      message: SmartPlanningResponseBuilder.askPlanningConfirmation(task.title),
      handled: true,
    );
  }

  Future<SmartPlanningContinuationResult?> tryStartExplicitSlotRequest({
    required String text,
    required int sessionGeneration,
  }) async {
    if (!_looksLikeSlotRequest(text)) return null;
    final title = _slotTitle(text);
    final startDate = _slotStartDate(text);
    final task = TaskModel(
      title: title,
      category: 'Agenda',
      isDone: false,
      createdAt: _clock(),
      dueDate: SmartPlanningService.formatIsoDate(startDate),
      planning: SmartPlanningService.formatIsoDate(startDate),
      notes: text,
    );
    _active = _new(
      type: SmartPlanningContinuationType.explicitSlotRequest,
      step: SmartPlanningContinuationStep.duration,
      task: task,
      originalMessage: text,
      sessionGeneration: sessionGeneration,
      startDate: startDate,
    );
    return SmartPlanningContinuationResult(
      status: SmartPlanningContinuationResultStatus.clarificationStillRequired,
      message:
          'D’accord 💕 Pour te proposer un vrai créneau disponible pour « $title », '
          'j’ai d’abord besoin de la durée du rendez-vous.\n\n'
          'Combien de temps veux-tu prévoir ?',
      handled: true,
    );
  }

  Future<ConversationOutcome?> resolve(
    String answer, {
    required int sessionGeneration,
  }) async {
    final continuation = _active;
    if (continuation == null) {
      final started = await tryStartExplicitSlotRequest(
        text: answer,
        sessionGeneration: sessionGeneration,
      );
      return started == null
          ? null
          : ConversationOutcome(reply: started.message);
    }
    if (continuation.sessionGeneration != sessionGeneration) {
      _active = null;
      return const ConversationOutcome(
        reply: 'Cette demande n’est plus active. Tu peux la reformuler.',
      );
    }
    if (!_clock().isBefore(continuation.expiresAt)) {
      _active = null;
      return const ConversationOutcome(
        reply: 'Cette proposition a expiré. Tu peux relancer la recherche.',
      );
    }
    final result = await _transition(continuation, answer);
    return ConversationOutcome(reply: result.message);
  }

  Future<SmartPlanningContinuationResult> _transition(
    SmartPlanningContinuation continuation,
    String answer,
  ) async {
    return switch (continuation.step) {
      SmartPlanningContinuationStep.planningConsent =>
        _resolvePlanningConsent(continuation, answer),
      SmartPlanningContinuationStep.duration =>
        _resolveDuration(continuation, answer),
      SmartPlanningContinuationStep.travelGo =>
        _resolveTravelGo(continuation, answer),
      SmartPlanningContinuationStep.travelBack =>
        _resolveTravelBack(continuation, answer),
      SmartPlanningContinuationStep.optionChoice =>
        _resolveOptionChoice(continuation, answer),
      SmartPlanningContinuationStep.confirmation =>
        _resolveConfirmation(continuation, answer),
      SmartPlanningContinuationStep.alternativeConfirmation =>
        _resolveAlternative(continuation, answer),
    };
  }

  Future<SmartPlanningContinuationResult> _resolvePlanningConsent(
    SmartPlanningContinuation continuation,
    String answer,
  ) async {
    if (PlannerEngineService.isNegativeAnswer(answer)) {
      _active = null;
      return _result(
        SmartPlanningContinuationResultStatus.cancelled,
        SmartPlanningResponseBuilder.keepOnlyTodo(continuation.task.title),
      );
    }
    if (!PlannerEngineService.isPositiveAnswer(answer)) {
      return _result(
        SmartPlanningContinuationResultStatus.invalidAnswer,
        SmartPlanningResponseBuilder.askPlanningConfirmation(
          continuation.task.title,
        ),
      );
    }
    final type = SmartPlanningService.detectTaskType(
      continuation.originalMessage,
      continuation.task,
    );
    final outside = SmartPlanningService.isOutsideTask(
      type: type,
      originalMessage: continuation.originalMessage,
      task: continuation.task,
    );
    final tasks = outside
        ? await _gateway.relatedTasks(
            continuation.task,
            continuation.originalMessage,
          )
        : <TaskModel>[continuation.task];
    final estimated = tasks.length > 1
        ? SmartPlanningService.estimateGroupedActionMinutes(tasks)
        : SmartPlanningService.actionDurationForType(
            type,
            continuation.originalMessage,
            continuation.task,
          );
    _active = continuation.copyWith(
      step: SmartPlanningContinuationStep.duration,
      taskType: type,
      outside: outside,
      estimatedMinutes: estimated,
      groupedTasks: tasks,
    );
    return _result(
      SmartPlanningContinuationResultStatus.clarificationStillRequired,
      SmartPlanningResponseBuilder.askDurationValidation(
        relatedTasks: tasks,
        hasGroupedTasks: tasks.length > 1,
        taskTitle: continuation.task.title,
        estimatedMinutes: estimated,
      ),
    );
  }

  Future<SmartPlanningContinuationResult> _resolveDuration(
    SmartPlanningContinuation continuation,
    String answer,
  ) async {
    var minutes = PlannerEngineService.isPositiveAnswer(answer)
        ? continuation.estimatedMinutes
        : ChatPlanningHelperService.parseDurationMinutes(answer);
    if (minutes <= 0) minutes = SmartPlanningService.parseTravelMinutes(answer);
    if (minutes <= 0) {
      return _result(
        SmartPlanningContinuationResultStatus.invalidAnswer,
        SmartPlanningResponseBuilder.askDurationExample(),
      );
    }
    final updated = continuation.copyWith(
      actionMinutes: minutes,
      step: SmartPlanningContinuationStep.travelGo,
    );
    if (continuation.type == SmartPlanningContinuationType.taskPlanning &&
        !continuation.outside) {
      return _findProposal(updated);
    }
    _active = updated;
    return _result(
      SmartPlanningContinuationResultStatus.clarificationStillRequired,
      continuation.type == SmartPlanningContinuationType.explicitSlotRequest
          ? 'Très bien 💕\n\nCombien de temps faut-il prévoir pour le trajet aller ?\n'
              'Tu peux répondre 0 si aucun trajet.'
          : SmartPlanningResponseBuilder.askTravelForOutsideTask(
              continuation.task.title,
            ),
    );
  }

  Future<SmartPlanningContinuationResult> _resolveTravelGo(
    SmartPlanningContinuation continuation,
    String answer,
  ) async {
    final parsed = _travelMinutes(answer);
    if (parsed == null) {
      return _result(
        SmartPlanningContinuationResultStatus.invalidAnswer,
        SmartPlanningResponseBuilder.askTravelDurationExample(),
      );
    }
    _active = continuation.copyWith(
      travelGoMinutes: parsed,
      step: SmartPlanningContinuationStep.travelBack,
    );
    return _result(
      SmartPlanningContinuationResultStatus.clarificationStillRequired,
      SmartPlanningResponseBuilder.askTravelBackForOutsideTask(),
    );
  }

  Future<SmartPlanningContinuationResult> _resolveTravelBack(
    SmartPlanningContinuation continuation,
    String answer,
  ) async {
    final parsed = _travelMinutes(
      answer,
      sameValue: continuation.travelGoMinutes,
    );
    if (parsed == null) {
      return _result(
        SmartPlanningContinuationResultStatus.invalidAnswer,
        SmartPlanningResponseBuilder.askTravelBackDurationExample(),
      );
    }
    final updated = continuation.copyWith(travelBackMinutes: parsed);
    return _findProposal(updated);
  }

  Future<SmartPlanningContinuationResult> _findProposal(
    SmartPlanningContinuation continuation,
  ) async {
    final margin = SmartPlanningService.defaultMarginMinutes(
      continuation.taskType.isEmpty
          ? SmartPlanningService.detectTaskType(
              continuation.originalMessage,
              continuation.task,
            )
          : continuation.taskType,
    );
    final total = continuation.actionMinutes +
        continuation.travelGoMinutes +
        continuation.travelBackMinutes +
        margin;
    final start = continuation.startDate ??
        SmartPlanningService.targetDateFromText(
          continuation.originalMessage,
          continuation.task,
        );
    final options = await _gateway.findOptions(
      startDate: start,
      totalMinutes: total,
      searchDays: _searchDays(continuation.originalMessage),
    );
    if (options.hasOptions && options.options.isNotEmpty) {
      _active = continuation.copyWith(
        type: SmartPlanningContinuationType.proposalSelection,
        step: SmartPlanningContinuationStep.optionChoice,
        marginMinutes: margin,
        options: options.options,
      );
      return _result(
        SmartPlanningContinuationResultStatus.clarificationStillRequired,
        _optionsMessage(options.options, continuation.task.title),
      );
    }
    if (continuation.type ==
        SmartPlanningContinuationType.explicitSlotRequest) {
      _active = continuation.copyWith(
        type: SmartPlanningContinuationType.alternativeSearch,
        step: SmartPlanningContinuationStep.alternativeConfirmation,
        failedDate: start,
        marginMinutes: margin,
      );
      return _result(
        SmartPlanningContinuationResultStatus.confirmationRequired,
        'Je n’ai pas trouvé de créneau disponible réaliste pour '
        '« ${continuation.task.title} » sur cette période 💕\n\n'
        'Tu veux que je cherche plus loin ?',
      );
    }
    final proposal = await _gateway.buildProposal(
      task: continuation.task,
      originalMessage: continuation.originalMessage,
      actionMinutes: continuation.actionMinutes,
      travelGoMinutes: continuation.travelGoMinutes,
      travelBackMinutes: continuation.travelBackMinutes,
      groupedTasks: continuation.groupedTasks.isEmpty
          ? [continuation.task]
          : continuation.groupedTasks,
    );
    if (proposal.canPropose) {
      _active = continuation.copyWith(
        type: SmartPlanningContinuationType.simpleProposal,
        step: SmartPlanningContinuationStep.confirmation,
        proposal: proposal,
        marginMinutes: proposal.marginMinutes,
      );
      return _result(
        SmartPlanningContinuationResultStatus.confirmationRequired,
        proposal.confirmationMessage,
      );
    }
    _active = continuation.copyWith(
      type: SmartPlanningContinuationType.alternativeSearch,
      step: SmartPlanningContinuationStep.alternativeConfirmation,
      failedDate: DateTime.tryParse(proposal.date) ?? start,
      marginMinutes: margin,
    );
    return _result(
      SmartPlanningContinuationResultStatus.confirmationRequired,
      proposal.confirmationMessage,
    );
  }

  Future<SmartPlanningContinuationResult> _resolveOptionChoice(
    SmartPlanningContinuation continuation,
    String answer,
  ) async {
    final index = PlanningProposalSelectionService.extractIndex(
      answer,
      continuation.options,
    );
    if (index == null || index >= continuation.options.length) {
      return _result(
        SmartPlanningContinuationResultStatus.invalidAnswer,
        'Réponds avec le numéro du créneau que tu préfères 💕',
      );
    }
    final selected = continuation.options[index];
    _active = continuation.copyWith(
      type: SmartPlanningContinuationType.selectedSlot,
      step: SmartPlanningContinuationStep.confirmation,
      selectedOption: selected,
      options: const [],
      mutationId: _idGenerator(),
    );
    return _result(
      SmartPlanningContinuationResultStatus.confirmationRequired,
      _recap(_active!),
    );
  }

  Future<SmartPlanningContinuationResult> _resolveConfirmation(
    SmartPlanningContinuation continuation,
    String answer,
  ) async {
    if (PlannerEngineService.isNegativeAnswer(answer)) {
      _active = null;
      return _result(
        SmartPlanningContinuationResultStatus.cancelled,
        'D’accord 💕 Je ne réserve rien dans l’agenda pour le moment.',
      );
    }
    if (!PlannerEngineService.isPositiveAnswer(answer)) {
      return _result(
        SmartPlanningContinuationResultStatus.invalidAnswer,
        'Réponds simplement oui pour réserver, ou non pour annuler 💕',
      );
    }
    final mutationId = continuation.mutationId ?? _idGenerator();
    if (_completedMutationIds.contains(mutationId)) {
      return _result(
        SmartPlanningContinuationResultStatus.duplicateIntent,
        'Cette réservation a déjà été traitée.',
      );
    }
    final event = continuation.proposal != null
        ? SmartPlanningService.eventFromProposal(continuation.proposal!)
        : _eventFromSelected(continuation);
    if (event == null) {
      _active = null;
      return _result(
        SmartPlanningContinuationResultStatus.planningValidationFailure,
        'Je n’ai pas pu finaliser ce rendez-vous, car ses horaires sont invalides.',
      );
    }
    if (continuation.selectedOption != null) {
      final schedule = _schedule(continuation);
      if (schedule == null) {
        _active = null;
        return _result(
          SmartPlanningContinuationResultStatus.planningValidationFailure,
          'Je n’ai pas pu calculer correctement les horaires de ce créneau.',
        );
      }
      final revalidation = await _gateway.revalidate(
        event: event,
        protectedStart: schedule.protectedStart,
        totalMinutes: continuation.actionMinutes +
            continuation.travelGoMinutes +
            continuation.travelBackMinutes +
            continuation.marginMinutes,
      );
      if (!revalidation.isAvailable) {
        if (revalidation.alternatives.hasOptions) {
          _active = continuation.copyWith(
            type: SmartPlanningContinuationType.proposalSelection,
            step: SmartPlanningContinuationStep.optionChoice,
            options: revalidation.alternatives.options,
          );
          return _result(
            SmartPlanningContinuationResultStatus.conflict,
            'Ce créneau vient d’être pris 💕\n\n'
            '${_optionsMessage(revalidation.alternatives.options, continuation.task.title)}',
          );
        }
        _active = null;
        return _result(
          SmartPlanningContinuationResultStatus.conflict,
          'Je n’ai pas réservé ce créneau, car il est maintenant en conflit. '
          'Je n’ai pas trouvé d’autre disponibilité réaliste pour le moment.',
        );
      }
    } else if (await _gateway.conflict(event) != null) {
      _active = continuation.copyWith(
        type: SmartPlanningContinuationType.alternativeSearch,
        step: SmartPlanningContinuationStep.alternativeConfirmation,
        failedDate: DateTime.tryParse(continuation.proposal?.date ?? ''),
      );
      return _result(
        SmartPlanningContinuationResultStatus.conflict,
        'Je n’ai pas réservé le créneau, car il y a maintenant un conflit. '
        'Je peux chercher un autre créneau si tu veux.',
      );
    }
    await _gateway.addEvent(event);
    _completedMutationIds.add(mutationId);
    if (_completedMutationIds.length > maximumCompletedMutationReceipts) {
      _completedMutationIds.remove(_completedMutationIds.first);
    }
    _active = null;
    return _result(
      SmartPlanningContinuationResultStatus.success,
      'C’est fait 💕 J’ai réservé « ${event.title} » le ${event.date} '
      'de ${event.time} à ${event.endTime} dans ton agenda.',
    );
  }

  Future<SmartPlanningContinuationResult> _resolveAlternative(
    SmartPlanningContinuation continuation,
    String answer,
  ) async {
    if (PlannerEngineService.isNegativeAnswer(answer)) {
      _active = null;
      return _result(
        SmartPlanningContinuationResultStatus.cancelled,
        'D’accord 💕 Je ne cherche pas d’autre jour pour le moment.',
      );
    }
    if (!PlannerEngineService.isPositiveAnswer(answer)) {
      return _result(
        SmartPlanningContinuationResultStatus.invalidAnswer,
        'Dis-moi simplement oui si tu veux que je cherche un autre jour, '
        'ou non si tu préfères arrêter ici 💕',
      );
    }
    final failed = continuation.failedDate ?? _clock();
    for (var offset = 1; offset <= 14; offset++) {
      final date = failed.add(Duration(days: offset));
      final proposal = await _gateway.buildProposal(
        task: continuation.task.copyWith(
          planning: SmartPlanningService.formatIsoDate(date),
          dueDate: SmartPlanningService.formatIsoDate(date),
        ),
        originalMessage:
            '${continuation.task.title} ${SmartPlanningService.formatIsoDate(date)}',
        actionMinutes: continuation.actionMinutes,
        travelGoMinutes: continuation.travelGoMinutes,
        travelBackMinutes: continuation.travelBackMinutes,
        groupedTasks: continuation.groupedTasks.isEmpty
            ? [continuation.task]
            : continuation.groupedTasks,
      );
      if (proposal.canPropose) {
        _active = continuation.copyWith(
          type: SmartPlanningContinuationType.simpleProposal,
          step: SmartPlanningContinuationStep.confirmation,
          proposal: proposal,
          failedDate: date,
          mutationId: _idGenerator(),
        );
        return _result(
          SmartPlanningContinuationResultStatus.confirmationRequired,
          'J’ai trouvé une autre possibilité 💕\n\n'
          '${proposal.confirmationMessage}',
        );
      }
    }
    _active = continuation.copyWith(
      failedDate: failed.add(const Duration(days: 14)),
    );
    return _result(
      SmartPlanningContinuationResultStatus.recoverableFailure,
      'Je n’ai pas trouvé de créneau réaliste sur les 14 prochains jours 💕\n\n'
      'On peut soit chercher plus loin, soit réduire la durée ou le temps de trajet.',
    );
  }

  SmartPlanningContinuation _new({
    required SmartPlanningContinuationType type,
    required SmartPlanningContinuationStep step,
    required TaskModel task,
    required String originalMessage,
    required int sessionGeneration,
    DateTime? startDate,
  }) {
    final now = _clock().toUtc();
    return SmartPlanningContinuation(
      id: _idGenerator(),
      sessionGeneration: sessionGeneration,
      type: type,
      step: step,
      createdAt: now,
      expiresAt: now.add(continuationLifetime),
      task: task,
      originalMessage: originalMessage,
      groupedTasks: [task],
      startDate: startDate,
    );
  }

  static SmartPlanningContinuationResult _result(
    SmartPlanningContinuationResultStatus status,
    String message,
  ) =>
      SmartPlanningContinuationResult(
        status: status,
        message: message,
        handled: true,
      );

  static int? _travelMinutes(String text, {int? sameValue}) {
    final lower = text.trim().toLowerCase();
    if (sameValue != null &&
        ['pareil', 'même', 'meme', 'identique'].any(lower.contains)) {
      return sameValue;
    }
    if (PlannerEngineService.isNoTravelAnswer(lower) ||
        lower == '0' ||
        lower == 'aucun' ||
        lower == 'pas de trajet') {
      return 0;
    }
    final value = SmartPlanningService.parseTravelMinutes(text);
    return value > 0 ? value : null;
  }

  static SelectedSlotSchedule? _schedule(
    SmartPlanningContinuation continuation,
  ) =>
      SelectedSlotScheduleService.build(
        protectedStart: continuation.selectedOption?.start,
        durationMinutes: continuation.actionMinutes,
        travelGoMinutes: continuation.travelGoMinutes,
        travelBackMinutes: continuation.travelBackMinutes,
        marginMinutes: continuation.marginMinutes,
      );

  EventModel? _eventFromSelected(SmartPlanningContinuation continuation) {
    final schedule = _schedule(continuation);
    if (schedule == null) return null;
    final date = SmartPlanningService.formatIsoDate(schedule.appointmentStart);
    final start = SmartPlanningService.formatIsoTime(schedule.appointmentStart);
    final end = SmartPlanningService.formatIsoTime(schedule.appointmentEnd);
    return EventModel(
      title: continuation.task.title,
      date: date,
      time: start,
      endTime: end,
      durationMinutes: continuation.actionMinutes,
      travelMinutes:
          continuation.travelGoMinutes + continuation.travelBackMinutes,
      travelGoMinutes: continuation.travelGoMinutes,
      travelBackMinutes: continuation.travelBackMinutes,
      usesSeparateTravelTimes: true,
      marginMinutes: continuation.marginMinutes,
      departureContext: 'previous_event',
      arrivalContext: 'next_event',
      startDateTimeIso: '${date}T$start:00',
      endDateTimeIso: '${date}T$end:00',
      category: continuation.task.category,
      notes: 'Planifié par Zelia depuis une proposition multi-créneaux.',
      createdAt: _clock(),
    );
  }

  static String _recap(SmartPlanningContinuation continuation) {
    final option = continuation.selectedOption!;
    final schedule = _schedule(continuation)!;
    return 'Je récapitule avant de réserver 💕\n\n'
        '• Rendez-vous : ${continuation.task.title}\n'
        '• Date : ${option.dateIso}\n'
        '• Départ prévu : ${option.startTime}\n'
        '• Rendez-vous : ${SmartPlanningService.formatIsoTime(schedule.appointmentStart)} '
        'à ${SmartPlanningService.formatIsoTime(schedule.appointmentEnd)}\n'
        '• Retour et marge terminés à : '
        '${SmartPlanningService.formatIsoTime(schedule.protectedEnd)}\n'
        '• Durée du rendez-vous : '
        '${SmartPlanningService.durationLabel(continuation.actionMinutes)}\n'
        '• Trajet aller : '
        '${SmartPlanningService.durationLabel(continuation.travelGoMinutes)}\n'
        '• Trajet retour : '
        '${SmartPlanningService.durationLabel(continuation.travelBackMinutes)}\n\n'
        'Tu confirmes que je réserve ce créneau ?';
  }

  static String _optionsMessage(
    List<PlanningProposalOption> options,
    String title,
  ) {
    final lines = <String>[
      'Voici les créneaux disponibles que je peux te proposer pour « $title » 💕',
      '',
      for (var index = 0; index < options.length; index++)
        '${index + 1}. ${options[index].label}',
      '',
      'Réponds 1, 2 ou 3 pour choisir le créneau.',
    ];
    return lines.join('\n');
  }

  static int _searchDays(String text) {
    final lower = text.toLowerCase();
    if ([
      'demain',
      "aujourd'hui",
      'aujourd’hui',
      'ce soir',
      'cet après-midi',
      'cet apres-midi',
      'ce matin',
    ].any(lower.contains)) {
      return 1;
    }
    return lower.contains('semaine prochaine') ? 7 : 21;
  }

  static bool _looksLikeSlotRequest(String text) {
    final lower = text.toLowerCase();
    final proposal = [
      'propose-moi un créneau',
      'propose moi un créneau',
      'propose-moi un creneau',
      'propose moi un creneau',
      'trouve-moi un créneau',
      'trouve moi un créneau',
      'cherche-moi un créneau',
      'cherche moi un créneau',
      'place-moi un rendez-vous',
      'place moi un rendez-vous',
      "quand est-ce que je peux",
      'quand est ce que je peux',
    ].any(lower.contains);
    final appointment = [
      'rendez-vous',
      'rendez vous',
      'rdv',
      'médecin',
      'medecin',
      'dentiste',
      'consultation',
      'réunion',
      'reunion',
      'coiffeur',
      'coiffeuse',
      'esthéticienne',
      'estheticienne',
      'ongles',
      'garage',
      'contrôle technique',
      'controle technique',
    ].any(lower.contains);
    return proposal && appointment;
  }

  static String _slotTitle(String text) {
    final lower = text.toLowerCase();
    const values = <String, String>{
      'médecin': 'Médecin',
      'medecin': 'Médecin',
      'dentiste': 'Dentiste',
      'pédiatre': 'Pédiatre',
      'pediatre': 'Pédiatre',
      'réunion': 'Réunion',
      'reunion': 'Réunion',
      'coiffeur': 'Coiffeur',
      'coiffeuse': 'Coiffeur',
      'esthéticienne': 'Esthéticienne',
      'estheticienne': 'Esthéticienne',
      'ongles': 'Ongles',
      'garage': 'Garage',
      'contrôle technique': 'Contrôle technique',
      'controle technique': 'Contrôle technique',
    };
    for (final entry in values.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    return 'Rendez-vous';
  }

  DateTime _slotStartDate(String text) {
    final lower = text.toLowerCase();
    final now = _clock();
    final today = DateTime(now.year, now.month, now.day);
    if (lower.contains('semaine prochaine')) {
      final delta = (8 - today.weekday) % 7;
      return today.add(Duration(days: delta == 0 ? 7 : delta));
    }
    return SmartPlanningService.targetDateFromText(
      text,
      TaskModel(
        title: 'Rendez-vous',
        category: 'Agenda',
        isDone: false,
        createdAt: now,
        notes: text,
      ),
    );
  }
}
