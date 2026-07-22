import '../models/planning_draft_model.dart';
import '../models/event_participant.dart';
import '../models/task_model.dart';
import 'natural_language_understanding_service.dart';

class PlanningDraftService {
  static PlanningDraftModel buildFromAction({
    required Map<String, dynamic> action,
    required String sourceMessage,
    required bool needsTravel,
  }) {
    final nlu = NaturalLanguageUnderstandingService.parse(
      sourceMessage,
      fallbackIsoDate: action["date"]?.toString() ?? "",
    );

    return PlanningDraftModel.fromAction(
      action: action,
      sourceMessage: sourceMessage,
      resolvedDateIso: nlu.dateIso,
      resolvedTime:
          nlu.time.isNotEmpty ? nlu.time : action["time"]?.toString() ?? "",
      resolvedDurationMinutes: nlu.durationMinutes > 0
          ? nlu.durationMinutes
          : int.tryParse(action["durationMinutes"]?.toString() ?? "0") ?? 0,
      needsTravel: needsTravel,
      confidence: nlu.confidence,
      source: "planning_draft_service",
    );
  }

  static PlanningDraftModel updateWithUserReply({
    required PlanningDraftModel draft,
    required String userReply,
  }) {
    final nlu = NaturalLanguageUnderstandingService.parse(
      userReply,
      fallbackIsoDate: draft.dateIso,
    );

    var updated = draft;

    if (nlu.hasDate) {
      updated = updated.withDate(nlu.dateIso);
    }

    if (nlu.hasTime) {
      updated = updated.withTime(nlu.time);
    }

    if (nlu.hasDuration) {
      updated = updated.withDuration(nlu.durationMinutes);
    }

    return updated.markUpdated();
  }

  static Map<String, dynamic> toPendingTimeEvent(
    PlanningDraftModel draft, {
    EventParticipant? participant,
  }) {
    return {
      "type": draft.type,
      "title": draft.title,
      "date": draft.dateIso,
      "dueDate": draft.dateIso,
      "planning": draft.dateIso,
      "requestedDateIso": draft.dateIso,
      "time": draft.time,
      "durationMinutes": draft.durationMinutes,
      "needsDuration": draft.needsDuration,
      "category": draft.category,
      "isRecurring": draft.isRecurring,
      "recurringType": draft.recurringType,
      "recurringWeekday": draft.recurringWeekday,
      "recurringUntil": draft.recurringUntil,
      "originalUserMessage": draft.sourceMessage,
      "planningDraft": draft.toJson(),
      if (participant != null) "participant": participant,
    };
  }

  static Map<String, dynamic> toPendingDurationPlanningTask(
    PlanningDraftModel draft,
  ) {
    return {
      "task": TaskModel(
        title: draft.title.isNotEmpty ? draft.title : "Rendez-vous",
        category: draft.category.isNotEmpty ? draft.category : "Personnel",
        isDone: false,
        createdAt: DateTime.now(),
        dueDate: draft.dateIso,
        planning: draft.dateIso,
      ),
      "originalMessage": "${draft.title} ${draft.dateIso}",
      "requestedDateIso": draft.dateIso,
      "type": draft.type.isNotEmpty ? draft.type : "rendez-vous",
      "outside": draft.isOutside,
      "estimatedMinutes": draft.durationMinutes,
      "groupedTasks": <TaskModel>[],
      "planningDraft": draft.toJson(),
    };
  }

  static PlanningDraftModel fromPendingDurationPlanningTask(
    Map<String, dynamic> pending,
  ) {
    final rawDraft = pending["planningDraft"];

    if (rawDraft is Map<String, dynamic>) {
      return PlanningDraftModel.fromJson(rawDraft);
    }

    final task = pending["task"];
    final title = task is TaskModel ? task.title : "Rendez-vous";
    final category = task is TaskModel ? task.category : "Personnel";
    final date = pending["requestedDateIso"]?.toString() ??
        (task is TaskModel ? task.dueDate : "");

    return PlanningDraftModel.empty().copyWith(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      sourceMessage: pending["originalMessage"]?.toString() ?? "",
      title: title,
      type: pending["type"]?.toString() ?? "event",
      category: category,
      dateIso: date,
      needsDate: date.isEmpty,
      needsTime: false,
      needsDuration: true,
      needsTravel: pending["outside"] == true,
      status: "draft",
      source: "legacy_pending_duration_task",
      updatedAt: DateTime.now(),
    );
  }

  static PlanningDraftModel withDurationFromPending({
    required Map<String, dynamic> pending,
    required int durationMinutes,
  }) {
    final draft = fromPendingDurationPlanningTask(pending);
    return draft.withDuration(durationMinutes);
  }

  static PlanningDraftModel withTravelFromPending({
    required Map<String, dynamic> pending,
    required int travelGoMinutes,
    required int travelBackMinutes,
  }) {
    final draft = fromPendingDurationPlanningTask(pending);

    return draft.withTravel(
      goMinutes: travelGoMinutes,
      backMinutes: travelBackMinutes,
    );
  }

  static bool isReadyForProposal(PlanningDraftModel draft) {
    return draft.isReadyForProposal;
  }

  static String nextQuestionForDraft(PlanningDraftModel draft) {
    switch (draft.nextMissingStep) {
      case "date":
        return "Quel jour veux-tu prévoir « ${draft.title} » ?";
      case "time":
        return "À quelle heure veux-tu prévoir « ${draft.title} » ?";
      case "duration":
        return "Combien de temps veux-tu prévoir pour « ${draft.title} » ?";
      case "travel":
        return "Combien de temps faut-il prévoir pour le trajet aller ?";
      case "confirmation":
        return "Tu veux que je réserve ce créneau dans ton agenda ?";
      default:
        return "";
    }
  }

  static String humanSummary(PlanningDraftModel draft) {
    final parts = <String>[];

    if (draft.title.isNotEmpty) {
      parts.add("« ${draft.title} »");
    }

    if (draft.dateIso.isNotEmpty) {
      parts.add("le ${draft.dateIso}");
    }

    if (draft.time.isNotEmpty) {
      parts.add("à ${draft.time}");
    }

    if (draft.durationMinutes > 0) {
      parts.add("pendant ${draft.durationMinutes} min");
    }

    if (draft.isOutside || draft.totalTravelMinutes > 0) {
      parts.add("trajet aller : ${draft.travelGoMinutes} min");
      parts.add("trajet retour : ${draft.travelBackMinutes} min");
    }

    if (draft.marginMinutes > 0) {
      parts.add("marge de sécurité : ${draft.marginMinutes} min");
    }

    return parts.join(", ");
  }
}
