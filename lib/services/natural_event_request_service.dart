import 'event_title_service.dart';
import 'natural_language_understanding_service.dart';

/// Recognizes a bounded, explicit Event creation request without relying on the
/// remote conversation service.
///
/// This route deliberately requires both a date and an explicit clock phrase.
/// Questions, mutations, reminders and recurring instructions keep using the
/// regular conversation orchestration.
final class NaturalEventRequestService {
  const NaturalEventRequestService._();

  static Map<String, dynamic>? parseAction(
    String text, {
    DateTime? now,
  }) {
    final original = text.trim();
    if (original.isEmpty) return null;

    final understanding = NaturalLanguageUnderstandingService.parse(
      original,
      now: now,
    );
    final normalized = understanding.normalization.normalizedText;
    if (!understanding.hasDate ||
        !understanding.hasTime ||
        understanding.expressesUncertainty ||
        understanding.normalization.preservedAmbiguities.isNotEmpty ||
        !_hasExplicitClockExpression(normalized) ||
        _mustUseRegularConversation(normalized)) {
      return null;
    }

    final hasEventLabel = RegExp(
      r'\b(?:rendez\s+vous|rdv|appointment)\b',
    ).hasMatch(normalized);
    final startsWithCreationCommand = RegExp(
      r'^(?:ajoute|ajouter|cree|creer|mets|mettre|planifie|planifier|prevois|prevoir|cale|caler)\b',
    ).hasMatch(normalized);
    if (startsWithCreationCommand && !hasEventLabel) return null;

    final details = _extractDetails(original);
    final motif = details.motif;
    final title = motif.isEmpty
        ? hasEventLabel
            ? 'Rendez-vous'
            : null
        : EventTitleService.titleFromMotif(motif);
    if (title == null) return null;

    return {
      'type': 'event',
      'title': title,
      'date': understanding.dateIso,
      'time': understanding.time,
      'durationMinutes':
          understanding.hasDuration ? understanding.durationMinutes : 0,
      'travelGoMinutes': 0,
      'travelBackMinutes': 0,
      'marginMinutes': 0,
      if (details.location.isNotEmpty) 'location': details.location,
      'originalMessage': original,
    };
  }

  static bool _mustUseRegularConversation(String value) {
    if (RegExp(
      r'^(?:quand|quel|quelle|quels|quelles|ou|comment|pourquoi|combien|est ce que|sais tu|peux tu me dire)\b',
    ).hasMatch(value)) {
      return true;
    }
    if (RegExp(
      r'^(?:annule|annuler|supprime|supprimer|deplace|deplacer|decale|decaler|modifie|modifier|change|changer)\b',
    ).hasMatch(value)) {
      return true;
    }
    if (RegExp(
      r'^(?:rappelle|rappeler|rappel|souviens|n oublie|je dois|il faut|achete|acheter|courses?)\b',
    ).hasMatch(value)) {
      return true;
    }
    return RegExp(
      r'\b(?:chaque|tous les|toutes les|par semaine|hebdomadaire)\b',
    ).hasMatch(value);
  }

  static bool _hasExplicitClockExpression(String value) {
    if (RegExp(
      r'\b\d{1,2}\s*(?:h(?:eur(?:es?)?|rs?)?|:)\s*\d{0,2}\b',
    ).hasMatch(value)) {
      return true;
    }
    if (RegExp(r'\ba\s+\d{1,2}\b').hasMatch(value)) return true;
    if (RegExp(
      '$_spokenHourPattern\\s*(?:h(?:eur(?:es?)?|rs?))\\b',
    ).hasMatch(value)) {
      return true;
    }
    return RegExp(
      r'\b(?:midi|fin de matinee|debut de matinee|debut d apres midi|apres midi|fin d apres midi|debut de soiree|soir|nuit)\b',
    ).hasMatch(value);
  }

  static _NaturalEventDetails _extractDetails(String original) {
    var value = original;
    for (final pattern in _temporalPatterns) {
      value = value.replaceAll(pattern, ' ');
    }
    final compact = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    final locationMatch = RegExp(
      r'^(.+?)\s+(?:chez|au|aux|à\s+la|a\s+la|à\s+l[’\x27]|a\s+l[’\x27]|à|a)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(compact);
    var location = '';
    if (locationMatch != null) {
      final candidate = locationMatch.group(2)?.trim() ?? '';
      if (candidate.isNotEmpty &&
          candidate.length <= 240 &&
          !_looksLikeClock(candidate)) {
        value = locationMatch.group(1)?.trim() ?? value;
        location = candidate;
      }
    }
    value = value
        .replaceFirst(
          RegExp(
            r'^\s*(?:je\s+(?:veux|voudrais|souhaite)\s+)?(?:ajoute(?:r)?|cr[ée]e?r?|mets?|mettre|planifie(?:r)?|pr[ée]vois|pr[ée]voir|cale(?:r)?)?\s*(?:moi\s+)?(?:un|une|le|la)?\s*(?:rendez[\s-]*vous|rdv|appointment)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'[.,!?;:()\[\]{}"“”«»]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(
            RegExp(r'^\s*(?:pour|le|la|un|une)\s+', caseSensitive: false), ' ')
        .trim();
    return _NaturalEventDetails(
      motif: _stripDanglingTemporalConnector(value),
      location: location,
    );
  }

  static bool _looksLikeClock(String value) => RegExp(
        r'^\d{1,2}\s*(?:h(?:eur(?:es?)?)?|:)\s*\d{0,2}\b',
        caseSensitive: false,
      ).hasMatch(value.trim());

  static String _stripDanglingTemporalConnector(String input) {
    final value = input.trim();
    final lower = value.toLowerCase();
    for (final connector in const [
      'aux alentours de',
      'autour de',
      'environ',
      'vers',
      'pour',
      'le',
      'ce',
      'à',
      'a',
    ]) {
      if (lower == connector) return '';
      if (lower.endsWith(' $connector')) {
        return value.substring(0, value.length - connector.length).trim();
      }
    }
    return value;
  }

  static final List<RegExp> _temporalPatterns = [
    RegExp(
      r'(?<![A-Za-zÀ-ÿ0-9])(?:(?:[àa]|vers|environ|autour\s+de|aux\s+alentours\s+de)\s*)?\d{1,2}\s*(?:h(?:eur(?:es?)?|ure(?:s?)?|rs?)?|:)\s*\d{0,2}\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(?:[àa]|vers|environ|autour\s+de|aux\s+alentours\s+de)\s+\d{1,2}\b',
      caseSensitive: false,
    ),
    RegExp(
      r'(?<![A-Za-zÀ-ÿ0-9])(?:(?:[àa]|vers|environ|autour\s+de|aux\s+alentours\s+de)\s*)?'
      '$_spokenHourPattern\\s*(?:h(?:eur(?:es?)?|ure(?:s?)?|rs?))'
      r'(?:\s+(?:et\s+(?:quart|demi(?:e)?)|trente|\d{1,2}))?\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(?:en\s+)?(?:fin\s+de\s+matin[ée]e?|d[ée]but\s+de\s+matin[ée]e?|midi|d[ée]but\s+d?[’\x27\s-]*apr[èe]s[\s-]*midi|apr[èe]s[\s-]*midi|fin\s+d?[’\x27\s-]*apr[èe]s[\s-]*midi|d[ée]but\s+de\s+soir[ée]e?|soir[ée]e?|nuit)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(?:apr[èe]s[\s-]*demain|apresdemain|aujourd[’\x27\s-]*hui|'
      r'auj|ajd|ojd|demain|dem1|dmain|deman|deamin)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(?:(?:ce|cet|cette|le)\s+)?(?:lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche)(?:\s+prochain(?:e)?)?\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(?:dans\s+\d+\s+(?:jours?|semaines?)|(?:la\s+)?semaine\s+prochaine|dans\s+un\s+mois)\b',
      caseSensitive: false,
    ),
    RegExp(r'\b(?:le\s+)?\d{4}-\d{2}-\d{2}\b', caseSensitive: false),
    RegExp(
      r'\b(?:le\s+)?\d{1,2}[\/.\-]\d{1,2}(?:[\/.\-]\d{2,4})?\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(?:le\s+)?\d{1,2}\s+(?:janvier|f[ée]vrier|mars|avril|mai|juin|juillet|ao[uû]t|septembre|octobre|novembre|d[ée]cembre)(?:\s+\d{4})?\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(?:pendant|pour\s+une\s+dur[ée]e\s+de)\s+(?:\d+|une?|deux|trois|quatre|cinq|six)\s*(?:h(?:eures?)?|minutes?)\b',
      caseSensitive: false,
    ),
  ];

  static const String _spokenHourPattern =
      r'\b(?:z[ée]ro|une?|deux|trois|quatre|cinq|six|sept|huit|neuf|dix|onze|douze|treize|quatorze|quinze|seize|dix\s+sept|dix\s+huit|dix\s+neuf|vingt(?:\s+et\s+un|\s+deux|\s+trois)?)';
}

final class _NaturalEventDetails {
  const _NaturalEventDetails({
    required this.motif,
    required this.location,
  });

  final String motif;
  final String location;
}
