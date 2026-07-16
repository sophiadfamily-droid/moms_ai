class RecurringMemoryScheduleService {
  static const Map<int, String> _canonicalDays = {
    DateTime.monday: "Lundi",
    DateTime.tuesday: "Mardi",
    DateTime.wednesday: "Mercredi",
    DateTime.thursday: "Jeudi",
    DateTime.friday: "Vendredi",
    DateTime.saturday: "Samedi",
    DateTime.sunday: "Dimanche",
  };

  static Map<String, dynamic>? buildBlockedPeriod({
    required String text,
    String category = "personal",
  }) {
    final normalized = _normalize(text);

    if (normalized.isEmpty || !_looksRecurring(normalized)) {
      return null;
    }

    final days = _extractDays(normalized);

    if (days.isEmpty) {
      return null;
    }

    final range = _extractTimeRange(normalized);

    if (range == null) {
      return null;
    }

    return {
      "type": "blocked_period",
      "sourceType": "memory_routine",
      "label": _buildLabel(text),
      "category": category.trim().isEmpty ? "personal" : category.trim(),
      "days": days,
      "startTime": range.$1,
      "endTime": range.$2,
      "travelBeforeMinutes": 0,
      "travelAfterMinutes": 0,
      "travelMinutes": 0,
      "origin": "",
      "destination": "",
      "mode": "unknown",
      "provider": "memory_reasoning",
      "isDynamic": false,
      "source": text.trim(),
    };
  }

  static bool _looksRecurring(String text) {
    return text.contains("tous les ") ||
        text.contains("toutes les ") ||
        text.contains("chaque ") ||
        text.contains("chaque semaine");
  }

  static List<String> _extractDays(String text) {
    final result = <String>[];

    void addDay(int weekday) {
      final value = _canonicalDays[weekday];

      if (value != null && !result.contains(value)) {
        result.add(value);
      }
    }

    final dayPatterns = <int, RegExp>{
      DateTime.monday: RegExp(r"\blundis?\b"),
      DateTime.tuesday: RegExp(r"\bmardis?\b"),
      DateTime.wednesday: RegExp(r"\bmercredis?\b"),
      DateTime.thursday: RegExp(r"\bjeudis?\b"),
      DateTime.friday: RegExp(r"\bvendredis?\b"),
      DateTime.saturday: RegExp(r"\bsamedis?\b"),
      DateTime.sunday: RegExp(r"\bdimanches?\b"),
    };

    for (final entry in dayPatterns.entries) {
      if (entry.value.hasMatch(text)) {
        addDay(entry.key);
      }
    }

    return result;
  }

  static (String, String)? _extractTimeRange(String text) {
    final patterns = <RegExp>[
      RegExp(
        r"\bde\s+(\d{1,2})(?:h|:)(\d{0,2})\s+"
        r"(?:a|jusqu(?:'|’)a)\s+"
        r"(\d{1,2})(?:h|:)(\d{0,2})\b",
      ),
      RegExp(
        r"\bentre\s+(\d{1,2})(?:h|:)(\d{0,2})\s+"
        r"et\s+"
        r"(\d{1,2})(?:h|:)(\d{0,2})\b",
      ),
    ];

    RegExpMatch? match;

    for (final pattern in patterns) {
      match = pattern.firstMatch(text);

      if (match != null) {
        break;
      }
    }

    if (match == null) {
      return null;
    }

    final start = _formatTime(
      hourText: match.group(1),
      minuteText: match.group(2),
    );

    final end = _formatTime(
      hourText: match.group(3),
      minuteText: match.group(4),
    );

    if (start.isEmpty || end.isEmpty) {
      return null;
    }

    final startMinutes = _minutesFromTime(start);
    final endMinutes = _minutesFromTime(end);

    if (startMinutes < 0 || endMinutes < 0 || endMinutes <= startMinutes) {
      return null;
    }

    return (start, end);
  }

  static String _formatTime({
    required String? hourText,
    required String? minuteText,
  }) {
    final hour = int.tryParse(hourText ?? "") ?? -1;
    final minute = int.tryParse(
          (minuteText ?? "").trim().isEmpty ? "0" : minuteText!,
        ) ??
        -1;

    if (hour < 0 || hour > 23) {
      return "";
    }

    if (minute < 0 || minute > 59) {
      return "";
    }

    return "${hour.toString().padLeft(2, "0")}:"
        "${minute.toString().padLeft(2, "0")}";
  }

  static int _minutesFromTime(String value) {
    final parts = value.split(":");

    if (parts.length != 2) {
      return -1;
    }

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);

    if (hour == null || minute == null) {
      return -1;
    }

    return (hour * 60) + minute;
  }

  static String _buildLabel(String text) {
    final clean = text.trim();

    if (clean.isEmpty) {
      return "Routine enregistrée";
    }

    return clean.length <= 80
        ? clean
        : "${clean.substring(0, 77).trimRight()}...";
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
