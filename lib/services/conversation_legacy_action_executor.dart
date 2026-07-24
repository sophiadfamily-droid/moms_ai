import '../models/conversation_models.dart';
import '../models/task_model.dart';
import '../models/action_autonomy_policy.dart';
import 'action_handler_service.dart';
import 'chat_planning_helper_service.dart';
import 'conversation_coordinator.dart';
import 'event_confirmation_service.dart';
import 'event_service.dart';
import 'notification_service.dart';
import 'planner_engine_service.dart';
import 'smart_planning_continuation_coordinator.dart';

final class ConversationLegacyActionExecutor {
  const ConversationLegacyActionExecutor({
    required this.coordinator,
    this.smartPlanning,
    this.loadAutonomyPolicy,
  });

  final ConversationCoordinator coordinator;
  final SmartPlanningContinuationCoordinator? smartPlanning;
  final Future<ActionAutonomyPolicy> Function()? loadAutonomyPolicy;

  Future<ConversationOutcome?> resolvePending(
    String answer,
    int sessionGeneration,
  ) async {
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
    final planningResolution = await smartPlanning?.resolve(
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
          conflictChecker: EventService.getOverlapConflict,
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

  Future<ConversationActionOutcome> execute(
    Map<String, dynamic> action,
    String userMessage,
    int sessionGeneration,
  ) async {
    final effectiveUserMessage =
        action['originalMessage']?.toString() ?? userMessage;
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
    );
    final event = result.pendingConfirmationEvent;
    if (event != null) {
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
    final pendingTask = result.pendingSmartPlanningTask;
    final task = pendingTask?['task'];
    final planningTitle = task is TaskModel ? task.title : null;
    if (task is TaskModel && smartPlanning != null) {
      final policy = await loadAutonomyPolicy?.call();
      if (policy != null) smartPlanning!.updateAutonomyPolicy(policy);
      smartPlanning!.beginTaskPlanning(
        task: task,
        originalMessage:
            pendingTask?['originalMessage']?.toString() ?? effectiveUserMessage,
        sessionGeneration: sessionGeneration,
      );
    }
    return ConversationActionOutcome(
      message: result.message,
      planningTitle: planningTitle,
    );
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
}
