import 'natural_date_service.dart';
import 'natural_duration_service.dart';
import 'natural_language_normalizer.dart';

/// A bounded request to search for the best slot over a civil-date period.
///
/// This is deliberately distinct from Event creation: "next week" is a
/// search range, not an incomplete Event date.
final class PlanningSearchRequest {
  const PlanningSearchRequest({
    required this.title,
    required this.startDate,
    required this.searchDays,
    required this.durationMinutes,
    this.location = '',
  });

  final String title;
  final DateTime startDate;
  final int searchDays;
  final int durationMinutes;
  final String location;
}

final class PlanningSearchRequestService {
  const PlanningSearchRequestService._();

  static PlanningSearchRequest? parse(
    String text, {
    DateTime? now,
  }) {
    final original = text.trim();
    if (original.isEmpty) return null;
    final normalized = _normalize(original);
    if (!_expressesSlotSearch(normalized)) return null;

    final target = _target(original, normalized);
    if (target == null) return null;
    final period = _period(normalized, now ?? DateTime.now());
    return PlanningSearchRequest(
      title: target.title,
      startDate: period.startDate,
      searchDays: period.searchDays,
      durationMinutes: NaturalDurationService.parseMinutes(original),
      location: target.location,
    );
  }

  static bool _expressesSlotSearch(String value) {
    return RegExp(
          r'\b(?:propose|trouve|cherche|cale|place)(?:\s+moi)?\s+'
          r'(?:(?:un|le|des)\s+)?(?:creneau|horaire|moment)\b',
        ).hasMatch(value) ||
        RegExp(
          r'\bquand\s+(?:est\s+ce\s+que\s+)?je\s+peux\s+'
          r'(?:prevoir|placer|caler|aller)\b',
        ).hasMatch(value);
  }

  static _PlanningSearchTarget? _target(String original, String normalized) {
    final known = _knownTitle(normalized);
    final forMatch = RegExp(r'\bpour\b', caseSensitive: false)
        .allMatches(original)
        .lastOrNull;
    if (forMatch == null) {
      return known == null ? null : _PlanningSearchTarget(known, '');
    }

    var value = original.substring(forMatch.end).trim();
    value = value
        .replaceAll(RegExp(r'[!?;:()\[\]{}"“”«»]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceFirst(
          RegExp(
            r'^(?:une|un|les|le|la|du|de\s+la|des)\b\s*|^l[’\x27]\s*',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    if (value.isEmpty) {
      return known == null ? null : _PlanningSearchTarget(known, '');
    }
    final separated = _separateExplicitLocation(value);
    final cleanTitle = _withoutSearchPeriod(separated.title);
    final cleanLocation = _withoutSearchPeriod(separated.location);
    if (cleanTitle.isEmpty) {
      return known == null ? null : _PlanningSearchTarget(known, cleanLocation);
    }
    final normalizedTarget = _normalize(cleanTitle);
    final mapped = _knownTitle(normalizedTarget);
    if (mapped != null && normalizedTarget.split(' ').length <= 4) {
      return _PlanningSearchTarget(mapped, cleanLocation);
    }
    final title = cleanTitle;
    return _PlanningSearchTarget(
      '${title[0].toUpperCase()}${title.substring(1)}',
      cleanLocation,
    );
  }

  static String _withoutSearchPeriod(String value) => value
      .replaceAll(_trailingPeriod, ' ')
      .replaceFirst(RegExp(r'[.,]+$'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static _PlanningSearchTarget _separateExplicitLocation(String value) {
    final match = RegExp(
      r'^(.+?)\s+(?:à|a|au|aux|chez)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) return _PlanningSearchTarget(value, '');
    final title = match.group(1)?.trim() ?? '';
    final location = match.group(2)?.trim() ?? '';
    if (title.isEmpty || location.isEmpty || _looksTemporal(location)) {
      return _PlanningSearchTarget(value, '');
    }
    return _PlanningSearchTarget(
      title,
      location.length <= 240 ? location : '',
    );
  }

  static bool _looksTemporal(String value) {
    final normalized = _normalize(value);
    return RegExp(r'^\d{1,2}\s*(?:h|heure|:)').hasMatch(normalized) ||
        RegExp(
          r'^(?:aujourd hui|demain|apres demain|lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche)\b',
        ).hasMatch(normalized);
  }

  static String? _knownTitle(String value) {
    const values = <String, String>{
      'controle technique': 'Contrôle technique',
      'estheticienne': 'Esthéticienne',
      'ophtalmo': 'Ophtalmo',
      'pediatre': 'Pédiatre',
      'medecin': 'Médecin',
      'dentiste': 'Dentiste',
      'veterinaire': 'Vétérinaire',
      'reunion': 'Réunion',
      'coiffeuse': 'Coiffeur',
      'coiffeur': 'Coiffeur',
      'ongles': 'Ongles',
      'garage': 'Garage',
    };
    for (final entry in values.entries) {
      if (RegExp('\\b${RegExp.escape(entry.key)}\\b').hasMatch(value)) {
        return entry.value;
      }
    }
    return null;
  }

  static _PlanningSearchPeriod _period(String text, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    if (RegExp(r'\b(?:la\s+)?semaine\s+prochaine\b').hasMatch(text)) {
      final daysUntilNextMonday = 8 - today.weekday;
      return _PlanningSearchPeriod(
        today.add(Duration(days: daysUntilNextMonday)),
        7,
      );
    }
    if (RegExp(r'\b(?:cette|dans\s+la)\s+semaine\b').hasMatch(text)) {
      return _PlanningSearchPeriod(today, 8 - today.weekday);
    }
    final nextDays = RegExp(
      r'\bdans\s+(?:les\s+)?(\d{1,2})\s+prochains?\s+jours?\b',
    ).firstMatch(text);
    if (nextDays != null) {
      final count = int.tryParse(nextDays.group(1) ?? '');
      if (count != null && count >= 1 && count <= 31) {
        return _PlanningSearchPeriod(today, count);
      }
    }
    if (RegExp(r'\bdans\s+les\s+prochains?\s+jours?\b').hasMatch(text)) {
      return _PlanningSearchPeriod(today, 7);
    }
    if (RegExp(r'\b(?:ce|le)\s+week\s*end\s+prochain\b').hasMatch(text)) {
      final currentSaturday = today.add(
        Duration(days: (DateTime.saturday - today.weekday + 7) % 7),
      );
      return _PlanningSearchPeriod(
        currentSaturday.add(const Duration(days: 7)),
        2,
      );
    }
    if (RegExp(r'\b(?:ce|le)\s+week\s*end\b').hasMatch(text)) {
      final saturday = today.add(
        Duration(days: (DateTime.saturday - today.weekday + 7) % 7),
      );
      return _PlanningSearchPeriod(saturday, 2);
    }
    if (const [
      'aujourd hui',
      'ce matin',
      'cet apres midi',
      'ce soir',
    ].any(text.contains)) {
      return _PlanningSearchPeriod(today, 1);
    }

    final dateIso = NaturalDateService.resolveDateFromText(text, now: now);
    final date = DateTime.tryParse(dateIso);
    if (date != null) {
      return _PlanningSearchPeriod(
        DateTime(date.year, date.month, date.day),
        1,
      );
    }
    return _PlanningSearchPeriod(today, 21);
  }

  static final RegExp _trailingPeriod = RegExp(
    r'\b(?:(?:la\s+)?(?:semaine|sem|semain|semiane)\s+'
    r'(?:prochaine|proch|prochane|prochiane)|'
    r'(?:cette|dans\s+la)\s+semaine|'
    r'dans\s+(?:les\s+)?\d{1,2}\s+prochains?\s+jours?|'
    r'dans\s+les\s+prochains?\s+jours?|'
    r'(?:aujourd[’\x27\s-]*hui|demain|apr[èe]s[\s-]*demain)|'
    r'(?:ce|le)\s+week[\s-]*end(?:\s+prochain)?|'
    r'(?:(?:ce|le)\s+)?(?:lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche)(?:\s+prochain)?)\b.*$',
    caseSensitive: false,
  );

  static String _normalize(String value) =>
      const NaturalLanguageNormalizer().normalize(value).normalizedText;
}

final class _PlanningSearchPeriod {
  const _PlanningSearchPeriod(this.startDate, this.searchDays);

  final DateTime startDate;
  final int searchDays;
}

final class _PlanningSearchTarget {
  const _PlanningSearchTarget(this.title, this.location);

  final String title;
  final String location;
}

extension on Iterable<RegExpMatch> {
  RegExpMatch? get lastOrNull {
    RegExpMatch? result;
    for (final value in this) {
      result = value;
    }
    return result;
  }
}
