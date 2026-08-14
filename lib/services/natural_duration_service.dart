import 'natural_language_normalizer.dart';

enum NaturalDurationExpectedField {
  duration,
  travelGo,
  travelBack,
  margin,
}

class NaturalDurationService {
  static int parseMinutes(
    String text, {
    NaturalDurationExpectedField? expectedField,
  }) {
    final lower = _normalize(text);

    if (lower.isEmpty) return 0;

    if (_containsAny(lower, [
      "je sais pas",
      "je ne sais pas",
      "aucune idee",
      "comme tu veux",
      "a toi de voir",
      "le temps necessaire",
    ])) {
      return 0;
    }

    final normalizedNumbers = _replaceFrenchNumbers(lower);
    final embeddedDuration = _explicitDurationMinutes(normalizedNumbers);
    final hasDurationContext = _hasDurationContext(lower);
    final standaloneDuration = _looksLikeStandaloneDuration(lower);

    if (!hasDurationContext && !standaloneDuration && embeddedDuration <= 0) {
      return 0;
    }

    if (_containsAny(lower, [
      "quelques minutes",
      "vite fait",
      "rapide",
      "rapidement",
    ])) {
      return 10;
    }

    if (_containsAny(lower, [
      "un quart d'heure",
      "un quart d heure",
      "quart d'heure",
      "quart d heure",
      "quinze minutes",
    ])) {
      return 15;
    }

    if (_containsAny(lower, [
      "une demi heure",
      "demi heure",
      "demi-heure",
      "1/2 heure",
    ])) {
      return 30;
    }

    if (_containsAny(lower, [
      "trois quarts d'heure",
      "trois quarts d heure",
      "trois quart d'heure",
      "trois quart d heure",
      "3 quarts d'heure",
      "3 quarts d heure",
      "3 quart d'heure",
      "3 quart d heure",
    ])) {
      return 45;
    }

    final hourAndHalfMatch = RegExp(
      r'(une|un|1|deux|2|trois|3|quatre|4|cinq|5)\s*(h|heure|heures)\s*et\s*(demie|demi)',
    ).firstMatch(lower);

    if (hourAndHalfMatch != null) {
      final hourText = hourAndHalfMatch.group(1) ?? "1";
      final hours = int.tryParse(_replaceFrenchNumbers(hourText)) ?? 1;
      return _safeDuration((hours * 60) + 30);
    }

    var normalized = _replaceFrenchNumbers(lower);

    normalized = normalized
        .replaceAll(" et demie", " 30 minutes")
        .replaceAll(" et demi", " 30 minutes")
        .replaceAll(" et quart", " 15 minutes");

    final compactHourMinute = RegExp(r'^(\d+)h(\d+)$').firstMatch(normalized);

    if (compactHourMinute != null) {
      final hours = int.tryParse(compactHourMinute.group(1) ?? "0") ?? 0;
      final minutes = int.tryParse(compactHourMinute.group(2) ?? "0") ?? 0;
      return _safeDuration((hours * 60) + minutes);
    }

    final explicitDuration = _explicitDurationMinutes(normalized);
    if (explicitDuration > 0) return explicitDuration;

    final standaloneHourMinute = RegExp(
      r'^(\d+)\s*(h|heure|heures)\s*(\d+)?\s*(min|minute|minutes)?$',
    ).firstMatch(normalized);

    if (standaloneHourMinute != null) {
      final hours = int.tryParse(standaloneHourMinute.group(1) ?? "0") ?? 0;
      final minutes = int.tryParse(standaloneHourMinute.group(3) ?? "0") ?? 0;
      return _safeDuration((hours * 60) + minutes);
    }

    final minutesOnly = RegExp(
      r'(\d+)\s*(min|minute|minutes)',
    ).firstMatch(normalized);

    if (minutesOnly != null) {
      final minutes = int.tryParse(minutesOnly.group(1) ?? "0") ?? 0;
      return _safeDuration(minutes);
    }

    final onlyNumber = RegExp(r'^\s*(\d+)\s*$').firstMatch(normalized);

    if (onlyNumber != null) {
      final value = int.tryParse(onlyNumber.group(1) ?? "0") ?? 0;

      if (value <= 0) return 0;

      if (expectedField != null) {
        return _safeDuration(value);
      }

      if (value >= 1 && value <= 5) {
        return value * 60;
      }

      return _safeDuration(value);
    }

    return 0;
  }

  static bool _hasDurationContext(String text) {
    return _containsAny(text, [
      "pendant",
      "duree",
      "durée",
      "durer",
      "dure",
      "combien de temps",
      "prevoir",
      "prévoir",
      "bloquer",
      "bloque",
      "bloqué",
      "pour une duree",
      "ca prend",
      "ça prend",
      "temps necessaire",
      "temps nécessaire",
    ]);
  }

  static int _explicitDurationMinutes(String text) {
    final pattern = RegExp(
      r"(?:\b(?:pendant|duree|durer|dure|prevoir|bloquer|bloque|pour)\s+(?:de\s+)?|\bd'\s*|\bd\s+|\bde\s+)"
      r'(\d+)\s*(heures|heure|h|minutes|minute|min)\s*'
      r'(\d+)?\s*(min|minute|minutes)?',
    );

    for (final match in pattern.allMatches(text)) {
      final value = int.tryParse(match.group(1) ?? '0') ?? 0;
      if (value <= 0) continue;
      final unit = match.group(2) ?? '';
      if (unit.startsWith('min')) return _safeDuration(value);

      final trailing = text.substring(match.end);
      if (RegExp(r'^\s*a\s+\d+\s*(?:h|heure|heures)\b').hasMatch(trailing)) {
        continue;
      }
      final minutes = int.tryParse(match.group(3) ?? '0') ?? 0;
      return _safeDuration((value * 60) + minutes);
    }
    return 0;
  }

  static bool _looksLikeStandaloneDuration(String text) {
    final cleaned = text.trim();

    if (RegExp(r'^\d+\s*$').hasMatch(cleaned)) return true;
    if (RegExp(r'^\d+\s*h\s*\d*\s*$').hasMatch(cleaned)) return true;
    if (RegExp(r'^\d+\s*(min|minute|minutes)\s*$').hasMatch(cleaned)) {
      return true;
    }
    if (RegExp(
      r'^(une?|deux|trois|quatre|cinq|six|sept|huit|neuf|dix|onze|douze|'
      r'treize|quatorze|quinze|vingt|trente|quarante|cinquante|soixante)'
      r'\s*(min|minute|minutes)\s*$',
    ).hasMatch(cleaned)) {
      return true;
    }

    return _containsAny(cleaned, [
      "une heure",
      "un heure",
      "deux heures",
      "trois heures",
      "quatre heures",
      "cinq heures",
      "une heure et demie",
      "une heure et demi",
      "demi heure",
      "demi-heure",
      "un quart d'heure",
      "un quart d heure",
      "trois quarts d'heure",
      "trois quarts d heure",
      "quelques minutes",
    ]);
  }

  static int _safeDuration(int minutes) {
    if (minutes <= 0) return 0;
    if (minutes > 720) return 720;
    return minutes;
  }

  static bool _containsAny(String text, List<String> values) {
    return values.any(text.contains);
  }

  static String _normalize(String text) {
    return const NaturalLanguageNormalizer().normalize(text).normalizedText;
  }

  static String _replaceFrenchNumbers(String text) {
    final replacements = {
      "une": "1",
      "un": "1",
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
      "vingt": "20",
      "trente": "30",
      "quarante": "40",
      "cinquante": "50",
      "soixante": "60",
      "quatre vingt dix": "90",
      "quatre-vingt-dix": "90",
    };

    var result = text;

    replacements.forEach((word, value) {
      result = result.replaceAll(RegExp("\\b$word\\b"), value);
    });

    return result;
  }
}
