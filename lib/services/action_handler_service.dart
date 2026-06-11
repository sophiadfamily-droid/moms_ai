import '../models/event_model.dart';
import '../models/shopping_item_model.dart';
import '../models/task_model.dart';

import 'event_service.dart';
import 'notification_service.dart';
import 'shopping_service.dart';
import 'task_service.dart';
import 'zelia_response_builder.dart';
import 'natural_language_understanding_service.dart';

class ActionHandlerResult {
  final String message;
  final Map<String, dynamic>? pendingDateEvent;
  final Map<String, dynamic>? pendingTimeEvent;
  final Map<String, dynamic>? pendingDurationEvent;
  final Map<String, dynamic>? pendingTravelEvent;
  final Map<String, dynamic>? pendingConflictResolutionEvent;
  final Map<String, dynamic>? pendingSmartPlanningTask;

  const ActionHandlerResult({
    this.message = "",
    this.pendingDateEvent,
    this.pendingTimeEvent,
    this.pendingDurationEvent,
    this.pendingTravelEvent,
    this.pendingConflictResolutionEvent,
    this.pendingSmartPlanningTask,
  });
}

class ActionHandlerService {
  static Future<ActionHandlerResult> handleAction({
    required dynamic action,
    required String currentUserMessage,
    required String Function(String value) normalizeTime,
    required int Function(String value) parseDurationMinutes,
    required int Function() weekdayFromText,
    required bool Function() messageLooksRecurringWeekly,
    required String Function(int weekday) nextDateForWeekday,
    required bool Function(Map<String, dynamic> action) eventNeedsTravel,
    required String Function({
      required String date,
      required String time,
    }) buildStartDateTimeIso,
    required String Function({
      required String date,
      required String time,
      required int durationMinutes,
    }) buildEndDateTimeIso,
    required String Function({
      required String date,
      required String time,
      required int durationMinutes,
    }) endTimeFromDuration,
  }) async {
    if (action is! Map) return const ActionHandlerResult();

    final type = action["type"]?.toString() ?? "";
    final title = action["title"]?.toString() ?? "";
    var date = action["date"]?.toString() ?? "";
    final nlu = NaturalLanguageUnderstandingService.parse(
      currentUserMessage,
      fallbackIsoDate: action["date"]?.toString() ?? "",
    );

    var time = normalizeTime(action["time"]?.toString() ?? "");

    if (time.isEmpty && nlu.hasTime) {
      time = nlu.time;
    }

    var durationMinutes = int.tryParse(
          action["durationMinutes"]?.toString() ?? "0",
        ) ??
        0;

    if (durationMinutes <= 0) {
      durationMinutes = parseDurationMinutes(currentUserMessage);
    }

    final textWeekday = weekdayFromText();
    final isRecurringWeekly =
        action["isRecurring"] == true || messageLooksRecurringWeekly();

    var recurringWeekday = int.tryParse(
          action["recurringWeekday"]?.toString() ?? "0",
        ) ??
        0;

    if (recurringWeekday <= 0) recurringWeekday = textWeekday;

    if (isRecurringWeekly && recurringWeekday > 0) {
      date = nextDateForWeekday(recurringWeekday);
    }

    if (title.trim().isEmpty) return const ActionHandlerResult();

    if (type == "shopping") {
      final item = ShoppingItemModel(
        title: title,
        isBought: false,
        createdAt: DateTime.now(),
        category: action["category"]?.toString() ?? "Autre",
        notes: action["notes"]?.toString() ?? "",
        isUrgent: action["isUrgent"] == true,
        section: action["section"]?.toString() ?? "Aujourd’hui",
      );

      await ShoppingService.addItem(item);
      await NotificationService.showNotification(
        title: "Liste de courses 🛒",
        body: title,
      );

      return const ActionHandlerResult();
    }

    if (type == "task" || type == "todo" || type == "to-do") {
      final task = TaskModel(
        title: title,
        category: "To-do",
        isDone: false,
        createdAt: DateTime.now(),
        isImportant: action["isImportant"] == true,
        dueDate: action["dueDate"]?.toString() ?? "",
        notes: action["notes"]?.toString() ?? "",
        planning: action["planning"]?.toString().trim().isNotEmpty == true
            ? action["planning"].toString()
            : "Cette semaine",
        priority: action["priority"]?.toString().trim().isNotEmpty == true
            ? action["priority"].toString()
            : "Normale",
      );

      await TaskService.addTask(task);
      await NotificationService.showNotification(
        title: "Nouvelle to-do ✅",
        body: title,
      );

      return ActionHandlerResult(
        pendingSmartPlanningTask: {
          "task": task,
          "originalMessage": currentUserMessage,
        },
      );
    }

    if (type == "event") {
      final pendingAction = Map<String, dynamic>.from(action);
      pendingAction["isRecurring"] = isRecurringWeekly;
      pendingAction["recurringType"] = isRecurringWeekly ? "weekly" : "";
      pendingAction["recurringWeekday"] = recurringWeekday;

      if (date.isEmpty) {
        return ActionHandlerResult(
          pendingDateEvent: pendingAction,
          message:
              "J’ai bien noté « $title » 💕\n\nQuel jour est prévu ce rendez-vous ?",
        );
      }

      if (time.isEmpty) {
        final messageWeekday = weekdayFromText();
        final correctedDate =
            messageWeekday > 0 ? nextDateForWeekday(messageWeekday) : date;

        pendingAction["date"] = correctedDate;

        return ActionHandlerResult(
          pendingTimeEvent: pendingAction,
          message:
              "C’est noté pour « $title » 💕\n\nÀ quelle heure est-il prévu ?",
        );
      }

      final earlyStartDateTimeIso = buildStartDateTimeIso(
        date: date,
        time: time,
      );

      final earlyConflictEvent = await EventService.getConflictEvent(
        startDateTimeIso: earlyStartDateTimeIso,
      );

      if (earlyConflictEvent != null) {
        pendingAction["date"] = date;
        pendingAction["time"] = "";

        return ActionHandlerResult(
          pendingConflictResolutionEvent: pendingAction,
          message:
              "Attention 💕 Tu as déjà quelque chose de prévu à cette heure-là : "
              "${earlyConflictEvent.title}.\n\n"
              "Peux-tu me proposer un autre horaire ? ✨",
        );
      }

      final earlyCandidateEvent = EventModel(
        title: title,
        date: date,
        time: time,
        notes: action["notes"]?.toString() ?? "",
        category: action["category"]?.toString() ?? "Personnel",
        createdAt: DateTime.now(),
        startDateTimeIso: earlyStartDateTimeIso,
        endTime: endTimeFromDuration(
          date: date,
          time: time,
          durationMinutes: 60,
        ),
        endDateTimeIso: buildEndDateTimeIso(
          date: date,
          time: time,
          durationMinutes: 60,
        ),
        durationMinutes: 60,
        travelMinutes: 0,
        isRecurring: isRecurringWeekly,
        recurringType: isRecurringWeekly ? "weekly" : "",
        recurringWeekday: recurringWeekday,
      );

      final earlyOverlapConflictEvent = await EventService.getOverlapConflict(
        candidate: earlyCandidateEvent,
      );

      if (earlyOverlapConflictEvent != null) {
        pendingAction["date"] = date;
        pendingAction["time"] = "";

        return ActionHandlerResult(
          pendingConflictResolutionEvent: pendingAction,
          message:
              "Attention 💕 Ce créneau semble chevaucher un rendez-vous déjà prévu : "
              "${earlyOverlapConflictEvent.title}.\n\n"
              "Peux-tu me proposer un autre horaire ? ✨",
        );
      }

      if (durationMinutes <= 0) {
        pendingAction["date"] = date;
        pendingAction["time"] = time;

        return ActionHandlerResult(
          pendingDurationEvent: pendingAction,
          message:
              "Parfait 💕\n\nCombien de temps veux-tu prévoir pour « $title » ?",
        );
      }

      final travelMinutes =
          int.tryParse(action["travelMinutes"]?.toString() ?? "0") ?? 0;

      if (travelMinutes <= 0 && eventNeedsTravel(pendingAction)) {
        pendingAction["date"] = date;
        pendingAction["time"] = time;
        pendingAction["durationMinutes"] = durationMinutes;

        return ActionHandlerResult(
          pendingTravelEvent: pendingAction,
          message:
              "Très bien 💕\n\nCombien de temps faut-il prévoir pour le trajet aller ?",
        );
      }

      final safeDuration = durationMinutes > 0 ? durationMinutes : 60;
      final startDateTimeIso = buildStartDateTimeIso(date: date, time: time);
      final endDateTimeIso = buildEndDateTimeIso(
        date: date,
        time: time,
        durationMinutes: safeDuration,
      );
      final endTime = endTimeFromDuration(
        date: date,
        time: time,
        durationMinutes: safeDuration,
      );

      final event = EventModel(
        title: title,
        date: date,
        time: time,
        notes: action["notes"]?.toString() ?? "",
        category: action["category"]?.toString() ?? "Personnel",
        createdAt: DateTime.now(),
        startDateTimeIso: startDateTimeIso,
        endTime: endTime,
        endDateTimeIso: endDateTimeIso,
        durationMinutes: safeDuration,
        travelMinutes:
            int.tryParse(action["travelMinutes"]?.toString() ?? "0") ?? 0,
        isRecurring: isRecurringWeekly,
        recurringType: isRecurringWeekly ? "weekly" : "",
        recurringWeekday: recurringWeekday,
      );

      final conflictEvent = await EventService.getOverlapConflict(
        candidate: event,
      );

      if (conflictEvent != null) {
        return ActionHandlerResult(
          message:
              "Attention 💕 Tu as déjà quelque chose prévu sur ce créneau : "
              "${conflictEvent.title}. L’événement n’a pas été créé pour éviter un doublon. "
              "Essaie un autre horaire ✨",
        );
      }

      if (event.isRecurring && event.recurringType == "weekly") {
        final occurrences = EventService.buildWeeklyOccurrences(
          baseEvent: event,
          count: 52,
        );
        await EventService.addEvents(occurrences);
      } else {
        await EventService.addEvent(event);
      }

      await NotificationService.showNotification(
        title: "Nouvel événement 📅",
        body: title,
      );

      return ActionHandlerResult(
        message: ZeliaResponseBuilder.eventCreated(
          title: title,
          date: date,
          time: time,
          durationMinutes: safeDuration,
          travelMinutes: event.travelMinutes,
          isRecurring: event.isRecurring,
        ),
      );
    }

    return const ActionHandlerResult();
  }
}
