class ConflictEngineService {
  static Map<String, dynamic> buildRescheduledAction({
    required Map<String, dynamic> pendingAction,
    required String time,
  }) {
    final action = Map<String, dynamic>.from(pendingAction);

    action["time"] = time.trim();

    // Le flux de résolution redemande volontairement la durée.
    // Toutes les données qui dépendent du créneau doivent donc être
    // réinitialisées ensemble afin d'éviter un état hybride.
    action["durationMinutes"] = 0;
    action["needsDuration"] = true;

    action["travelMinutes"] = 0;
    action["travelGoMinutes"] = 0;
    action["travelBackMinutes"] = 0;
    action["usesSeparateTravelTimes"] = false;
    action["marginMinutes"] = 0;

    action["departureContext"] = "unknown";
    action["arrivalContext"] = "unknown";

    action.remove("travelStep");

    return action;
  }

  static String cancellationMessage(String title) {
    return "D’accord 💕 Je n’ajoute pas « $title » dans ton agenda.";
  }

  static String askNewTimeMessage() {
    return "Dis-moi simplement le nouvel horaire, par exemple 11h, 15h ou 16h30 💕\n\nTu peux aussi répondre non si tu ne veux plus ajouter ce rendez-vous.";
  }

  static String askDurationMessage(String title) {
    return "Parfait 💕\n\nCombien de temps veux-tu prévoir pour « $title » ?";
  }
}
