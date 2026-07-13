import '../models/task_model.dart';
import 'smart_planning_service.dart';

class SmartPlanningResponseBuilder {
  static String keepOnlyTodo(String title) {
    return "D’accord 💕 Je garde « $title » seulement dans ta to-do list.";
  }

  static String askPlanningConfirmation(String title) {
    return "Dis-moi simplement oui pour que je cherche un créneau "
        "pour « $title », ou non pour garder seulement la to-do 💕";
  }

  static String askTravelDurationExample() {
    return "Dis-moi juste le temps du trajet aller, par exemple 10 min, 15 min, 25 min ou 0 si aucun trajet 💕";
  }

  static String askTravelBackDurationExample() {
    return "Dis-moi juste le temps du trajet retour, par exemple 10 min, 15 min, pareil ou 0 si aucun trajet 💕";
  }

  static String askDurationExample() {
    return "Dis-moi par exemple : oui, 30 min, 1h ou 1h30 💕";
  }

  static String askTravelForOutsideTask(String title) {
    return "Pour « $title », il faut prévoir un déplacement.\n\n"
        "Combien de minutes faut-il compter pour le trajet aller ?";
  }

  static String askTravelBackForOutsideTask() {
    return "Et combien de minutes faut-il compter pour le trajet retour ? "
        "Tu peux répondre pareil si le temps est identique.";
  }

  static String askDurationValidation({
    required List<TaskModel> relatedTasks,
    required bool hasGroupedTasks,
    required String taskTitle,
    required int estimatedMinutes,
  }) {
    final intro = hasGroupedTasks
        ? "J’ai trouvé ${relatedTasks.length} to-do qui peuvent être "
            "regroupées dans un même déplacement.\n\n"
            "Je les ai classées par priorité :\n\n"
            "${SmartPlanningService.priorityBulletList(relatedTasks)}\n\n"
        : "";

    final taskLabel = hasGroupedTasks ? "cette sortie" : "« $taskTitle »";

    return "${intro}Pour $taskLabel, je pense qu’il faut prévoir "
        "${SmartPlanningService.durationLabel(estimatedMinutes)}.\n\n"
        "Tu valides ce temps ou tu veux le modifier ?";
  }
}
