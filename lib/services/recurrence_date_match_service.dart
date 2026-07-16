class RecurrenceDateMatchService {
  static bool appliesToDate(
    Map<String, dynamic> item,
    DateTime date,
  ) {
    final recurrenceType =
        item["recurrenceType"]?.toString().trim().toLowerCase() ?? "weekly";

    if (recurrenceType == "weekdays") {
      return date.weekday >= DateTime.monday && date.weekday <= DateTime.friday;
    }

    if (recurrenceType == "monthly_nth_weekday") {
      if (!_matchesConfiguredDay(item, date)) {
        return false;
      }

      final occurrence =
          int.tryParse(item["weekOfMonth"]?.toString() ?? "0") ?? 0;

      if (occurrence == -1) {
        return _isLastWeekdayOfMonth(date);
      }

      if (occurrence < 1 || occurrence > 5) {
        return false;
      }

      return _weekOfMonth(date) == occurrence;
    }

    if (recurrenceType == "biweekly") {
      if (!_matchesConfiguredDay(item, date)) {
        return false;
      }

      final anchorIso = item["anchorDateIso"]?.toString().trim() ?? "";
      final anchor = DateTime.tryParse(anchorIso);

      if (anchor == null) {
        return false;
      }

      final anchorDay = DateTime(anchor.year, anchor.month, anchor.day);
      final targetDay = DateTime(date.year, date.month, date.day);
      final differenceInDays = targetDay.difference(anchorDay).inDays;

      if (differenceInDays < 0) {
        return false;
      }

      return (differenceInDays ~/ 7).isEven;
    }

    return _matchesConfiguredDay(item, date);
  }

  static bool _matchesConfiguredDay(
    Map<String, dynamic> item,
    DateTime date,
  ) {
    final rawDays = item["days"];

    if (rawDays is! List || rawDays.isEmpty) {
      return true;
    }

    final normalizedDays = rawDays
        .map((day) => _normalize(day.toString()))
        .where((day) => day.isNotEmpty)
        .toList();

    if (normalizedDays.isEmpty) {
      return true;
    }

    final acceptedNames = _dayNamesForWeekday(date.weekday);

    return normalizedDays.any((day) {
      return acceptedNames.contains(day) ||
          acceptedNames.any(day.contains) ||
          day == date.weekday.toString();
    });
  }

  static int _weekOfMonth(DateTime date) {
    return ((date.day - 1) ~/ 7) + 1;
  }

  static bool _isLastWeekdayOfMonth(DateTime date) {
    final nextSameWeekday = date.add(const Duration(days: 7));
    return nextSameWeekday.month != date.month;
  }

  static List<String> _dayNamesForWeekday(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return ["lundi", "monday", "mon", "1"];
      case DateTime.tuesday:
        return ["mardi", "tuesday", "tue", "2"];
      case DateTime.wednesday:
        return ["mercredi", "wednesday", "wed", "3"];
      case DateTime.thursday:
        return ["jeudi", "thursday", "thu", "4"];
      case DateTime.friday:
        return ["vendredi", "friday", "fri", "5"];
      case DateTime.saturday:
        return ["samedi", "saturday", "sat", "6"];
      case DateTime.sunday:
        return ["dimanche", "sunday", "sun", "7"];
      default:
        return [];
    }
  }

  static String _normalize(String value) {
    return value
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
