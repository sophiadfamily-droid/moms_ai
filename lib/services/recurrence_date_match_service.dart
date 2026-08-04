import 'routine/routine_date_applicability_engine.dart';

class RecurrenceDateMatchService {
  static const _engine = RoutineDateApplicabilityEngine();

  static bool appliesToDate(
    Map<String, dynamic> item,
    DateTime date,
  ) {
    final recurrenceType =
        item["recurrenceType"]?.toString().trim().toLowerCase() ?? "weekly";

    return _engine.applies(
      recurrenceType: recurrenceType,
      weekdays: _configuredWeekdays(item),
      date: date,
      anchorDateIso: item["anchorDateIso"]?.toString(),
      weekOfMonth: int.tryParse(item["weekOfMonth"]?.toString() ?? ""),
      // Old blocked periods without `days` historically applied every day.
      emptyWeekdaysMatchAll: true,
    );
  }

  static List<int> _configuredWeekdays(Map<String, dynamic> item) {
    final rawDays = item["days"];
    if (rawDays is! List || rawDays.isEmpty) {
      return const [];
    }
    final normalizedDays = rawDays
        .map((day) => _normalize(day.toString()))
        .where((day) => day.isNotEmpty)
        .toList();
    return [
      for (var weekday = DateTime.monday; weekday <= DateTime.sunday; weekday++)
        if (normalizedDays.any((day) {
          final acceptedNames = _dayNamesForWeekday(weekday);
          return acceptedNames.contains(day) || acceptedNames.any(day.contains);
        }))
          weekday,
    ];
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
