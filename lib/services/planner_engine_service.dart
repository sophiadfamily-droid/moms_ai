import 'natural_duration_service.dart';

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

  static bool saysUnknownTime(String text) {
    final lower = text.trim().toLowerCase();

    return lower.contains("je sais pas") ||
        lower.contains("je ne sais pas") ||
        lower.contains("jsp") ||
        lower.contains("pas d'heure") ||
        lower.contains("pas dheure") ||
        lower.contains("sans heure") ||
        lower.contains("je connais pas l'heure") ||
        lower.contains("je ne connais pas l'heure");
  }

  static String extractDateFromText(String text) {
    final lower = text.trim().toLowerCase();

    const days = [
      "lundi",
      "mardi",
      "mercredi",
      "jeudi",
      "vendredi",
      "samedi",
      "dimanche",
    ];

    for (final day in days) {
      if (lower.contains(day)) return day;
    }

    if (lower.contains("demain")) return "demain";
    if (lower.contains("aujourd'hui") || lower.contains("aujourd’hui")) {
      return "aujourd'hui";
    }

    return text.trim();
  }

  static int parseDurationMinutes(String text) {
    return NaturalDurationService.parseMinutes(text);
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
