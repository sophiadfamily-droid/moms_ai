class PlannerEngineService {
  static bool isNegativeAnswer(String text) {
    final lower = text.trim().toLowerCase();

    return lower == "non" ||
        lower == "non merci" ||
        lower == "annule" ||
        lower == "annuler" ||
        lower == "laisse tomber" ||
        lower == "pas maintenant" ||
        lower.contains("n'ajoute pas") ||
        lower.contains("ne l'ajoute pas") ||
        lower.contains("n’enregistre pas") ||
        lower.contains("ne l’enregistre pas");
  }

  static bool isPositiveAnswer(String text) {
    final lower = text.trim().toLowerCase();

    return lower == "oui" ||
        lower == "yes" ||
        lower == "ok" ||
        lower == "d’accord" ||
        lower == "daccord" ||
        lower == "vas-y" ||
        lower == "vasy" ||
        lower == "réserve" ||
        lower == "reserve" ||
        lower.contains("oui vas") ||
        lower.contains("tu peux");
  }

  static bool isNoTravelAnswer(String text) {
    final lower = text.trim().toLowerCase();

    return lower == "non" ||
        lower == "non merci" ||
        lower.contains("pas de trajet") ||
        lower.contains("aucun trajet");
  }

  static String nextMissingEventStep(
    Map<String, dynamic> action, {
    bool needsTravel = false,
  }) {
    final date = action["date"]?.toString().trim() ?? "";
    final time = action["time"]?.toString().trim() ?? "";
    final durationMinutes = int.tryParse(
          action["durationMinutes"]?.toString() ?? "0",
        ) ??
        0;

    if (date.isEmpty) return "date";
    if (time.isEmpty) return "time";
    if (durationMinutes <= 0) return "duration";
    if (needsTravel) return "travel";

    return "ready";
  }
}
