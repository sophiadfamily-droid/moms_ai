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
    DateTime? referenceDate,
  }) {
    final normalized = _normalize(text);

    if (normalized.isEmpty || !_looksRecurring(normalized)) {
      return null;
    }

    final recurrenceType = _extractRecurrenceType(normalized);
    final extractedDays = _extractDays(normalized);

    final days = recurrenceType == "biweekly" &&
            extractedDays.isEmpty &&
            referenceDate != null
        ? [_canonicalDays[referenceDate.weekday]!]
        : extractedDays;

    if (recurrenceType == "weekly" && days.isEmpty) {
      return null;
    }

    if (recurrenceType == "biweekly" &&
        (days.isEmpty || referenceDate == null)) {
      return null;
    }

    final anchorDateIso = recurrenceType == "biweekly"
        ? _buildBiweeklyAnchorDateIso(
            referenceDate: referenceDate!,
            days: days,
          )
        : null;

    if (recurrenceType == "biweekly" && anchorDateIso == null) {
      return null;
    }

    final range = _extractTimeRange(normalized);

    if (range == null) {
      return null;
    }

    final travel = _extractTravel(normalized);

    return {
      "type": "blocked_period",
      "sourceType": "memory_routine",
      "label": _buildLabel(text),
      "category": category.trim().isEmpty ? "personal" : category.trim(),
      "recurrenceType": recurrenceType,
      if (days.isNotEmpty) "days": days,
      if (anchorDateIso != null) "anchorDateIso": anchorDateIso,
      "startTime": range.$1,
      "endTime": range.$2,
      "travelBeforeMinutes": travel.$1,
      "travelAfterMinutes": travel.$2,
      "travelMinutes": travel.$1 + travel.$2,
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
        text.contains("chaque semaine") ||
        _isWeekdaysRecurrence(text) ||
        _isBiweeklyRecurrence(text);
  }

  static String _extractRecurrenceType(String text) {
    if (_isBiweeklyRecurrence(text)) {
      return "biweekly";
    }

    if (_isWeekdaysRecurrence(text)) {
      return "weekdays";
    }

    return "weekly";
  }

  static bool _isBiweeklyRecurrence(String text) {
    return text.contains("une semaine sur deux") ||
        text.contains("toutes les deux semaines") ||
        text.contains("tous les quinze jours") ||
        text.contains("tous les 15 jours") ||
        RegExp(
          r"\bun\s+"
          r"(?:lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche)"
          r"\s+sur\s+deux\b",
        ).hasMatch(text);
  }

  static bool _isWeekdaysRecurrence(String text) {
    return text.contains("tous les jours ouvres") ||
        text.contains("tous les jours ouvrables") ||
        text.contains("chaque jour ouvre") ||
        text.contains("chaque jour ouvrable") ||
        text.contains("du lundi au vendredi") ||
        text.contains("les jours de semaine");
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

  static String? _buildBiweeklyAnchorDateIso({
    required DateTime referenceDate,
    required List<String> days,
  }) {
    final referenceDay = DateTime(
      referenceDate.year,
      referenceDate.month,
      referenceDate.day,
    );

    final occurrences = <DateTime>[];

    for (final day in days) {
      final weekday = _weekdayFromCanonicalDay(day);

      if (weekday == null) {
        continue;
      }

      final offset = (weekday - referenceDay.weekday + DateTime.daysPerWeek) %
          DateTime.daysPerWeek;

      occurrences.add(referenceDay.add(Duration(days: offset)));
    }

    if (occurrences.isEmpty) {
      return null;
    }

    occurrences.sort();

    return _formatDateIso(occurrences.first);
  }

  static int? _weekdayFromCanonicalDay(String day) {
    for (final entry in _canonicalDays.entries) {
      if (entry.value == day) {
        return entry.key;
      }
    }

    return null;
  }

  static String _formatDateIso(DateTime date) {
    final year = date.year.toString().padLeft(4, "0");
    final month = date.month.toString().padLeft(2, "0");
    final day = date.day.toString().padLeft(2, "0");

    return "$year-$month-$day";
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

  static (int, int) _extractTravel(String text) {
    final outbound = _extractDirectionalTravel(
      text,
      directionPattern: r"(?:trajet\s+)?aller",
    );

    final inbound = _extractDirectionalTravel(
      text,
      directionPattern: r"(?:trajet\s+)?retour",
    );

    if (outbound != null || inbound != null) {
      return (outbound ?? 0, inbound ?? 0);
    }

    final shared = _extractSharedTravel(text);

    if (shared == null) {
      return (0, 0);
    }

    return (shared, shared);
  }

  static int? _extractDirectionalTravel(
    String text, {
    required String directionPattern,
  }) {
    final durationBeforeDirection = RegExp(
      r"\b(\d{1,3})\s*(h|heure|heures|min|mn|minute|minutes)\s+"
      "(?:de\\s+)?$directionPattern"
      r"\b",
    ).firstMatch(text);

    if (durationBeforeDirection != null) {
      return _durationMatchToMinutes(durationBeforeDirection);
    }

    final directionBeforeDuration = RegExp(
      r"\b"
      "$directionPattern"
      r"\s*(?:de|:|=)?\s*"
      r"(\d{1,3})\s*(h|heure|heures|min|mn|minute|minutes)\b",
    ).firstMatch(text);

    if (directionBeforeDuration != null) {
      return _durationMatchToMinutes(directionBeforeDuration);
    }

    return null;
  }

  static int? _extractSharedTravel(String text) {
    final patterns = <RegExp>[
      RegExp(
        r"\b(?:avec\s+)?(\d{1,3})\s*"
        r"(h|heure|heures|min|mn|minute|minutes)\s+"
        r"(?:de\s+)?trajet\b",
      ),
      RegExp(
        r"\btrajet\s*(?:de|:|=)?\s*"
        r"(\d{1,3})\s*"
        r"(h|heure|heures|min|mn|minute|minutes)\b",
      ),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);

      if (match != null) {
        return _durationMatchToMinutes(match);
      }
    }

    return null;
  }

  static int _durationMatchToMinutes(RegExpMatch match) {
    final amount = int.tryParse(match.group(1) ?? "") ?? 0;
    final unit = match.group(2)?.toLowerCase() ?? "";

    if (amount <= 0) {
      return 0;
    }

    final minutes = unit.startsWith("h") ? amount * 60 : amount;

    return minutes.clamp(0, 240);
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
