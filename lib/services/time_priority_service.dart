class TimePriorityService {
  static int urgencyScore(String text) {
    final lower = text.trim().toLowerCase();

    var score = 0;

    if (_containsAny(lower, [
      "maintenant",
      "immédiatement",
      "immediatement",
      "tout de suite",
      "dans 1 heure",
      "dans une heure",
    ])) {
      return 5;
    }

    if (_containsAny(lower, [
      "aujourd'hui",
      "ce soir",
      "avant ce soir",
      "avant 18h",
      "avant 19h",
      "avant 20h",
    ])) {
      score = 4;
    }

    if (_containsAny(lower, [
      "demain",
      "avant demain",
    ])) {
      score = score < 3 ? 3 : score;
    }

    if (_containsAny(lower, [
      "cette semaine",
      "avant vendredi",
      "avant lundi",
      "avant mardi",
      "avant mercredi",
      "avant jeudi",
    ])) {
      score = score < 2 ? 2 : score;
    }

    if (_containsAny(lower, [
      "ce mois-ci",
      "ce mois",
      "avant la fin du mois",
    ])) {
      score = score < 1 ? 1 : score;
    }

    return score.clamp(0, 5);
  }

  static bool isUrgent(String text) {
    return urgencyScore(text) >= 4;
  }

  static bool isCritical(String text) {
    return urgencyScore(text) >= 5;
  }

  static bool _containsAny(String text, List<String> values) {
    return values.any(text.contains);
  }
}
