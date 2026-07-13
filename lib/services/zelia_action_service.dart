import '../models/event_model.dart';
import '../models/task_model.dart';
import '../models/shopping_item_model.dart';

import 'event_service.dart';
import 'task_service.dart';
import 'shopping_service.dart';
import 'notification_service.dart';

class ZeliaActionService {
  static String normalizeTime(String value) {
    final clean = value.trim().toLowerCase().replaceAll("h", ":");

    if (clean.isEmpty) {
      return "";
    }

    if (!clean.contains(":")) {
      return "${clean.padLeft(2, "0")}:00";
    }

    final parts = clean.split(":");
    final hour = parts.isNotEmpty ? parts[0].padLeft(2, "0") : "00";
    final minute = parts.length > 1 ? parts[1].padLeft(2, "0") : "00";

    return "$hour:$minute";
  }

  static String buildStartDateTimeIso({
    required String date,
    required String time,
  }) {
    final cleanTime = normalizeTime(time);

    if (date.trim().isEmpty || cleanTime.isEmpty) {
      return "";
    }

    return "${date}T$cleanTime:00";
  }

  static String buildEndDateTimeIso({
    required String date,
    required String time,
    required int durationMinutes,
  }) {
    final startIso = buildStartDateTimeIso(
      date: date,
      time: time,
    );

    if (startIso.isEmpty || durationMinutes <= 0) {
      return "";
    }

    final start = DateTime.tryParse(startIso);

    if (start == null) {
      return "";
    }

    final end = start.add(
      Duration(minutes: durationMinutes),
    );

    final endDate = end.toIso8601String().substring(0, 10);
    final endTime = end.toIso8601String().substring(11, 16);

    return "${endDate}T$endTime:00";
  }

  static String endTimeFromDuration({
    required String date,
    required String time,
    required int durationMinutes,
  }) {
    final endIso = buildEndDateTimeIso(
      date: date,
      time: time,
      durationMinutes: durationMinutes,
    );

    if (endIso.isEmpty) {
      return "";
    }

    return endIso.substring(11, 16);
  }

  static Future<String> handleAction({
    required dynamic action,
    required String currentUserMessage,
  }) async {
    if (action is! Map) {
      return "";
    }

    final type = action["type"]?.toString() ?? "";
    final title = action["title"]?.toString() ?? "";

    final date = action["date"]?.toString() ?? "";
    final time = normalizeTime(action["time"]?.toString() ?? "");

    final durationMinutes = int.tryParse(
          action["durationMinutes"]?.toString() ?? "60",
        ) ??
        60;

    if (title.trim().isEmpty) {
      return "";
    }

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

      return "";
    }

    if (type == "task") {
      final task = TaskModel(
        title: title,
        category: action["category"]?.toString() ?? "To-do",
        isDone: false,
        createdAt: DateTime.now(),
        isImportant: action["isImportant"] == true,
        dueDate: action["dueDate"]?.toString() ?? "",
        notes: action["notes"]?.toString() ?? "",
        planning: action["planning"]?.toString() ?? "Cette semaine",
        priority: action["priority"]?.toString() ?? "Normale",
      );

      await TaskService.addTask(task);

      await NotificationService.showNotification(
        title: "Nouvelle tâche ✅",
        body: title,
      );

      return "";
    }

    if (type == "event") {
      final startDateTimeIso = buildStartDateTimeIso(
        date: date,
        time: time,
      );

      final endDateTimeIso = buildEndDateTimeIso(
        date: date,
        time: time,
        durationMinutes: durationMinutes,
      );

      final endTime = endTimeFromDuration(
        date: date,
        time: time,
        durationMinutes: durationMinutes,
      );

      final event = EventModel(
        title: title,
        date: date,
        time: time,
        notes: action["notes"]?.toString() ?? "",
        category: action["category"]?.toString() ?? "Personnel",
        createdAt: DateTime.now(),
        startDateTimeIso: startDateTimeIso,
        endDateTimeIso: endDateTimeIso,
        endTime: endTime,
        durationMinutes: durationMinutes,
        travelMinutes:
            int.tryParse(action["travelMinutes"]?.toString() ?? "0") ?? 0,
        travelGoMinutes:
            int.tryParse(action["travelGoMinutes"]?.toString() ?? "0") ?? 0,
        travelBackMinutes:
            int.tryParse(action["travelBackMinutes"]?.toString() ?? "0") ?? 0,
        departureContext: action["departureContext"]?.toString() ?? "unknown",
        arrivalContext: action["arrivalContext"]?.toString() ?? "unknown",
      );

      final conflict = await EventService.getOverlapConflict(
        candidate: event,
      );

      if (conflict != null) {
        return "Attention 💕 Tu as déjà quelque chose prévu sur ce créneau : "
            "${conflict.title}. L’événement n’a pas été créé pour éviter un doublon. "
            "Essaie un autre horaire ✨";
      }

      await EventService.addEvent(event);

      await NotificationService.showNotification(
        title: "Nouvel événement 📅",
        body: title,
      );

      return "";
    }

    return "";
  }
}
