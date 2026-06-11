import '../models/task_model.dart';
import 'natural_date_service.dart';

class PlanningDraftService {
  static Map<String, dynamic> buildPendingTimeEvent({
    required Map<String, dynamic> action,
    required String originalUserMessage,
  }) {
    final correctedDate = NaturalDateService.resolveDateFromText(
      originalUserMessage,
      fallbackIsoDate: action["date"]?.toString() ?? "",
    );

    return {
      ...action,
      "date": correctedDate,
      "dueDate": correctedDate,
      "planning": correctedDate,
      "requestedDateIso": correctedDate,
      "originalUserMessage": originalUserMessage,
    };
  }

  static Map<String, dynamic> buildDurationPlanningTask({
    required Map<String, dynamic> action,
  }) {
    final title = action["title"]?.toString() ?? "Rendez-vous";
    final date = action["requestedDateIso"]?.toString().isNotEmpty == true
        ? action["requestedDateIso"]?.toString() ?? ""
        : action["date"]?.toString() ?? "";

    return {
      "task": TaskModel(
        title: title,
        category: action["category"]?.toString().isNotEmpty == true
            ? action["category"]?.toString() ?? "Personnel"
            : "Personnel",
        isDone: false,
        createdAt: DateTime.now(),
        dueDate: date,
        planning: date,
      ),
      "originalMessage": "$title $date",
      "requestedDateIso": date,
      "type": action["type"]?.toString() ?? "rendez-vous",
      "outside": true,
      "estimatedMinutes": 60,
      "groupedTasks": <TaskModel>[],
    };
  }
}
