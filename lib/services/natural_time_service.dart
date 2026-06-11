class NaturalTimeService {
  static String parseTime(String text) {
    final lower = _normalize(text);

    if (lower.isEmpty) return "";

    if (_containsAny(lower, [
      "je sais pas",
      "je ne sais pas",
      "aucune idee",
      "pas d'heure",
      "pas dheure",
      "sans heure",
    ])) {
      return "";
    }

    if (_containsAny(lower, [
      "fin de matinee",
      "en fin de matinee",
    ])) {
      return "11:00";
    }

    if (_containsAny(lower, [
      "debut de matinee",
      "en debut de matinee",
    ])) {
      return "09:00";
    }

    if (_containsAny(lower, [
      "midi",
      "vers midi",
      "autour de midi",
    ])) {
      return "12:00";
    }

    if (_containsAny(lower, [
      "debut d'apres-midi",
      "debut apres-midi",
      "en debut d'apres-midi",
    ])) {
      return "13:00";
    }

    if (_containsAny(lower, [
      "apres-midi",
      "dans l'apres-midi",
      "en apres-midi",
    ])) {
      return "15:00";
    }

    if (_containsAny(lower, [
      "fin d'apres-midi",
      "en fin d'apres-midi",
    ])) {
      return "17:00";
    }

    if (_containsAny(lower, [
      "apres l'ecole",
      "apres ecole",
      "sortie d'ecole",
    ])) {
      return "16:30";
    }

    if (_containsAny(lower, [
      "apres le travail",
      "apres boulot",
    ])) {
      return "18:00";
    }

    if (_containsAny(lower, [
      "debut de soiree",
      "en debut de soiree",
    ])) {
      return "18:30";
    }

    if (_containsAny(lower, [
      "soir",
      "ce soir",
      "en soiree",
      "dans la soiree",
    ])) {
      return "19:00";
    }

    if (_containsAny(lower, [
      "nuit",
      "cette nuit",
      "dans la nuit",
    ])) {
      return "22:00";
    }

    final aroundTime = RegExp(
      r'(vers|environ|autour de|aux alentours de)\s+(\d{1,2})(?:h|:)?(\d{2})?',
    ).firstMatch(lower);

    if (aroundTime != null) {
      return _formatTime(
        hourText: aroundTime.group(2),
        minuteText: aroundTime.group(3),
      );
    }

    final directTime = RegExp(
      r'\b(\d{1,2})(?:h|:)(\d{2})?\b',
    ).firstMatch(lower);

    if (directTime != null) {
      return _formatTime(
        hourText: directTime.group(1),
        minuteText: directTime.group(2),
      );
    }

    final standaloneHour = RegExp(
      r'\ba\s+(\d{1,2})\b',
    ).firstMatch(lower);

    if (standaloneHour != null) {
      return _formatTime(
        hourText: standaloneHour.group(1),
        minuteText: "0",
      );
    }

    return "";
  }

  static String _formatTime({
    required String? hourText,
    required String? minuteText,
  }) {
    final hour = int.tryParse(hourText ?? "") ?? -1;
    final minute = int.tryParse(minuteText ?? "0") ?? 0;

    if (hour < 0 || hour > 23) return "";
    if (minute < 0 || minute > 59) return "";

    return "${hour.toString().padLeft(2, "0")}:${minute.toString().padLeft(2, "0")}";
  }

  static bool _containsAny(String text, List<String> values) {
    return values.any(text.contains);
  }

  static String _normalize(String text) {
    return text
        .trim()
        .toLowerCase()
        .replaceAll("’", "'")
        .replaceAll("é", "e")
        .replaceAll("è", "e")
        .replaceAll("ê", "e")
        .replaceAll("ë", "e")
        .replaceAll("à", "a")
        .replaceAll("â", "a")
        .replaceAll("ù", "u")
        .replaceAll("û", "u")
        .replaceAll("î", "i")
        .replaceAll("ï", "i")
        .replaceAll("ô", "o")
        .replaceAll("ç", "c");
  }
}
