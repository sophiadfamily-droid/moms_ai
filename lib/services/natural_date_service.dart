import 'natural_language_normalizer.dart';

class NaturalDateService {
  static String resolveDateFromText(
    String text, {
    String fallbackIsoDate = "",
    DateTime? now,
  }) {
    final today = _startOfDay(now ?? DateTime.now());
    final lower = _normalize(text);

    if (lower.isEmpty && fallbackIsoDate.trim().isNotEmpty) {
      return _cleanFallback(fallbackIsoDate);
    }

    final isoDate = _extractIsoDate(lower);
    if (isoDate.isNotEmpty) return isoDate;

    final slashDate = _extractSlashDate(lower, today);
    if (slashDate.isNotEmpty) return slashDate;

    final writtenDate = _extractWrittenDate(lower, today);
    if (writtenDate.isNotEmpty) return writtenDate;

    final relativeDate = _extractRelativeDate(lower, today);
    if (relativeDate.isNotEmpty) return relativeDate;

    final weekendDate = _extractWeekendDate(lower, today);
    if (weekendDate.isNotEmpty) return weekendDate;

    final monthPeriodDate = _extractMonthPeriodDate(lower, today);
    if (monthPeriodDate.isNotEmpty) return monthPeriodDate;

    final weekdayDate = _extractWeekdayDate(lower, today);
    if (weekdayDate.isNotEmpty) return weekdayDate;

    return _cleanFallback(fallbackIsoDate);
  }

  static String _extractIsoDate(String text) {
    final match = RegExp(r'\b\d{4}-\d{2}-\d{2}\b').firstMatch(text);
    if (match == null) return "";

    final parsed = DateTime.tryParse(match.group(0) ?? "");
    if (parsed == null) return "";

    return _formatIso(_startOfDay(parsed));
  }

  static String _extractSlashDate(String text, DateTime today) {
    final match =
        RegExp(r'\b(\d{1,2})[\/\-\.](\d{1,2})(?:[\/\-\.](\d{2,4}))?\b')
            .firstMatch(text);

    if (match == null) return "";

    final day = int.tryParse(match.group(1) ?? "") ?? 0;
    final month = int.tryParse(match.group(2) ?? "") ?? 0;
    var year = int.tryParse(match.group(3) ?? "") ?? today.year;

    if (year < 100) year += 2000;

    return _safeDate(
      year: year,
      month: month,
      day: day,
      today: today,
    );
  }

  static String _extractWrittenDate(String text, DateTime today) {
    final monthNames = _monthNames();

    for (final entry in monthNames.entries) {
      final monthName = entry.key;
      final month = entry.value;

      final match = RegExp(r'\b(\d{1,2})\s+' + monthName + r'(?:\s+(\d{4}))?\b')
          .firstMatch(text);

      if (match == null) continue;

      final day = int.tryParse(match.group(1) ?? "") ?? 0;
      final year = int.tryParse(match.group(2) ?? "") ?? today.year;

      return _safeDate(
        year: year,
        month: month,
        day: day,
        today: today,
      );
    }

    return "";
  }

  static String _extractRelativeDate(String text, DateTime today) {
    final withNumbers = _replaceFrenchNumbers(text);

    if (_containsAny(withNumbers, [
      "aujourd'hui",
      "aujourd hui",
      "aujourdhui",
    ])) {
      return _formatIso(today);
    }

    if (_containsAny(withNumbers, [
      "apres demain",
      "apres-demain",
    ])) {
      return _formatIso(today.add(const Duration(days: 2)));
    }

    if (withNumbers.contains("demain")) {
      return _formatIso(today.add(const Duration(days: 1)));
    }

    final daysMatch = RegExp(r'dans\s+(\d+)\s+jours?').firstMatch(withNumbers);
    if (daysMatch != null) {
      final days = int.tryParse(daysMatch.group(1) ?? "") ?? 0;
      if (days > 0) return _formatIso(today.add(Duration(days: days)));
    }

    final weeksMatch =
        RegExp(r'dans\s+(\d+)\s+semaines?').firstMatch(withNumbers);
    if (weeksMatch != null) {
      final weeks = int.tryParse(weeksMatch.group(1) ?? "") ?? 0;
      if (weeks > 0) return _formatIso(today.add(Duration(days: weeks * 7)));
    }

    if (_containsAny(withNumbers, [
      "semaine prochaine",
      "la semaine prochaine",
    ])) {
      return _formatIso(today.add(const Duration(days: 7)));
    }

    if (_containsAny(withNumbers, [
      "dans un mois",
      "dans 1 mois",
    ])) {
      return _formatIso(DateTime(today.year, today.month + 1, today.day));
    }

    return "";
  }

  static String _extractWeekendDate(String text, DateTime today) {
    if (!_containsAny(text, ["week-end", "week end", "weekend"])) return "";

    final forceNext = _containsAny(text, ["prochain", "prochaine"]);

    final saturday = _nextWeekday(
      today: today,
      weekday: DateTime.saturday,
      forceNextWeek: forceNext,
    );

    return _formatIso(saturday);
  }

  static String _extractMonthPeriodDate(String text, DateTime today) {
    if (_containsAny(text, ["debut du mois", "debut mois"])) {
      return _formatIso(DateTime(today.year, today.month, 1));
    }

    if (_containsAny(text, ["fin du mois", "fin mois"])) {
      return _formatIso(DateTime(today.year, today.month + 1, 0));
    }

    for (final entry in _monthNames().entries) {
      final monthName = entry.key;
      final month = entry.value;

      if (text.contains("debut $monthName")) {
        final year = month < today.month ? today.year + 1 : today.year;
        return _formatIso(DateTime(year, month, 1));
      }

      if (text.contains("fin $monthName")) {
        final year = month < today.month ? today.year + 1 : today.year;
        return _formatIso(DateTime(year, month + 1, 0));
      }
    }

    return "";
  }

  static String _extractWeekdayDate(String text, DateTime today) {
    final weekday = _weekdayFromText(text);
    if (weekday <= 0) return "";

    final forceNextWeek = _containsAny(text, [
      "prochain",
      "prochaine",
      "semaine prochaine",
    ]);

    return _formatIso(_nextWeekday(
      today: today,
      weekday: weekday,
      forceNextWeek: forceNextWeek,
    ));
  }

  static int _weekdayFromText(String text) {
    if (text.contains("lundi")) return DateTime.monday;
    if (text.contains("mardi")) return DateTime.tuesday;
    if (text.contains("mercredi")) return DateTime.wednesday;
    if (text.contains("jeudi")) return DateTime.thursday;
    if (text.contains("vendredi")) return DateTime.friday;
    if (text.contains("samedi")) return DateTime.saturday;
    if (text.contains("dimanche")) return DateTime.sunday;
    return 0;
  }

  static DateTime _nextWeekday({
    required DateTime today,
    required int weekday,
    required bool forceNextWeek,
  }) {
    var daysToAdd = weekday - today.weekday;

    if (daysToAdd <= 0) {
      daysToAdd += 7;
    }

    if (forceNextWeek && daysToAdd < 7) {
      daysToAdd += 7;
    }

    return today.add(Duration(days: daysToAdd));
  }

  static String _safeDate({
    required int year,
    required int month,
    required int day,
    required DateTime today,
  }) {
    if (year < 2000 || year > 2100) return "";
    if (month < 1 || month > 12) return "";
    if (day < 1 || day > 31) return "";

    final parsed = DateTime(year, month, day);

    if (parsed.month != month || parsed.day != day) return "";

    var result = _startOfDay(parsed);

    if (result.isBefore(today)) {
      result = DateTime(result.year + 1, result.month, result.day);
    }

    return _formatIso(result);
  }

  static String _cleanFallback(String fallbackIsoDate) {
    final fallback = DateTime.tryParse(fallbackIsoDate.trim());
    if (fallback == null) return "";
    return _formatIso(_startOfDay(fallback));
  }

  static Map<String, int> _monthNames() {
    return {
      "janvier": 1,
      "fevrier": 2,
      "mars": 3,
      "avril": 4,
      "mai": 5,
      "juin": 6,
      "juillet": 7,
      "aout": 8,
      "septembre": 9,
      "octobre": 10,
      "novembre": 11,
      "decembre": 12,
    };
  }

  static bool _containsAny(String text, List<String> values) {
    return values.any(text.contains);
  }

  static DateTime _startOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  static String _formatIso(DateTime date) {
    final year = date.year.toString().padLeft(4, "0");
    final month = date.month.toString().padLeft(2, "0");
    final day = date.day.toString().padLeft(2, "0");
    return "$year-$month-$day";
  }

  static String _normalize(String text) {
    return const NaturalLanguageNormalizer().normalize(text).normalizedText;
  }

  static String _replaceFrenchNumbers(String text) {
    final replacements = {
      "un": "1",
      "une": "1",
      "deux": "2",
      "trois": "3",
      "quatre": "4",
      "cinq": "5",
      "six": "6",
      "sept": "7",
      "huit": "8",
      "neuf": "9",
      "dix": "10",
      "onze": "11",
      "douze": "12",
      "treize": "13",
      "quatorze": "14",
      "quinze": "15",
    };

    var result = text;
    replacements.forEach((word, value) {
      result = result.replaceAll(RegExp("\\b$word\\b"), value);
    });
    return result;
  }
}
