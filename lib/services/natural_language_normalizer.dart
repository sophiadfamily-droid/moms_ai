import '../models/natural_language_models.dart';

/// Safe, bounded French normalization used before deterministic routing.
///
/// It deliberately preserves negation and the two meanings of "plus".
final class NaturalLanguageNormalizer {
  const NaturalLanguageNormalizer();

  static const Map<String, String> _safeTokens = {
    'prebdre': 'prendre',
    'ajoutr': 'ajouter',
    'demian': 'demain',
    'mtn': 'maintenant',
    'rapel': 'rappel',
    'rdv': 'rendez vous',
    'stp': 's il te plait',
    'aujourdhui': 'aujourd hui',
    'doeuf': 'd oeuf',
    'doeufs': 'd oeufs',
  };

  NaturalLanguageNormalization normalize(String input) {
    final codes = <String>[];
    final ambiguities = <String>[];
    var value = input.trim();
    if (value != input) codes.add('trimmed');
    final lower = value.toLowerCase();
    if (lower != value) codes.add('lowercased');
    value = lower.replaceAll(RegExp(r'[’‘`´]'), "'");
    if (value != lower) codes.add('apostrophe_normalized');

    final folded = _foldAccents(value);
    if (folded != value) codes.add('accents_folded');
    value = folded
        .replaceAll(RegExp(r"['-]"), ' ')
        .replaceAll(RegExp(r'[.!?;,:()\[\]{}"…]+'), ' ')
        .replaceAll(RegExp(r'[\u{1F300}-\u{1FAFF}]', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final beforeOral = value;
    value = value
        .replaceFirst(RegExp(r'^jai\b'), 'j ai')
        .replaceFirst(RegExp(r'^ya\b'), 'y a')
        .replaceFirst(RegExp(r'^jveu\b'), 'je veux')
        .replaceFirst(RegExp(r'^je veu\b'), 'je veux')
        .replaceAll(RegExp(r'\bneuf heure et demie\b'), '09:30')
        .replaceAll(RegExp(r'\bneuf heures trente\b'), '09:30')
        .replaceAll(RegExp(r'\bneuf heure\b'), '09:00');
    if (value != beforeOral) codes.add('oral_form_normalized');

    final tokens = value.isEmpty ? <String>[] : value.split(' ');
    var corrected = false;
    for (var index = 0; index < tokens.length; index++) {
      final replacement = _safeTokens[tokens[index]];
      if (replacement != null) {
        tokens[index] = replacement;
        corrected = true;
      }
    }
    value = tokens.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (corrected) codes.add('safe_typo_corrected');

    if (RegExp(r'\b(?:je veux|ajoute)\s+plus\b').hasMatch(value)) {
      ambiguities.add('positive_or_quantity_plus');
    }
    if (RegExp(r'\b(?:j ai|y a|on a)\s+plus\b').hasMatch(value) &&
        !RegExp(r'\b(?:ne|n)\b').hasMatch(value)) {
      ambiguities.add('stockout_or_additional_plus');
    }
    if (RegExp(
          r'\b(?:ne|n)\s+(?:cree|creer|ajoute|ajouter|annule|annuler|'
          r'supprime|supprimer|decale|deplacer|veux)\b.{0,40}\b(?:pas|plus)\b',
        ).hasMatch(value) ||
        RegExp(
          r'\b(?:cree|ajoute|annule|supprime|decale|veux)\s+pas\b',
        ).hasMatch(value)) {
      ambiguities.add('critical_negation_scope');
    }
    if (RegExp(r'^(?:mets|met|decale)\s+(?:le|la|l)\b').hasMatch(value)) {
      ambiguities.add('unresolved_reference');
    }
    final actionCount = RegExp(
      r'\b(?:cree|ajoute|achete|annule|decale|deplace|supprime|'
      r'rappelle|planifie|cale)\b',
    ).allMatches(value).length;
    if (actionCount > 1 && RegExp(r'\b(?:et|puis|ensuite)\b').hasMatch(value)) {
      ambiguities.add('multiple_actions');
    }
    if (_hasNegation(value)) codes.add('negation_preserved');

    return NaturalLanguageNormalization(
      originalText: input,
      normalizedText: value,
      tokens: List.unmodifiable(
        value.isEmpty ? const <String>[] : value.split(' '),
      ),
      detectedLanguage: _detectLanguage(value),
      normalizationCodes: List.unmodifiable(codes),
      preservedAmbiguities: List.unmodifiable(ambiguities),
    );
  }

  static bool hasNegation(String input) => _hasNegation(
      const NaturalLanguageNormalizer().normalize(input).normalizedText);

  static bool _hasNegation(String value) => RegExp(
        r'\b(?:ne|n|pas|jamais|aucun|aucune|rien|personne|plus)\b',
      ).hasMatch(value);

  static String _detectLanguage(String value) {
    if (value.isEmpty) return 'und';
    final frenchMarkers = RegExp(
      r'\b(?:je|tu|il|elle|nous|vous|les|des|une|pour|demain|rendez|tache)\b',
    ).allMatches(value).length;
    return frenchMarkers > 0 ? 'fr' : 'und';
  }

  static String _foldAccents(String input) {
    const replacements = {
      'à': 'a',
      'â': 'a',
      'ä': 'a',
      'á': 'a',
      'ç': 'c',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'î': 'i',
      'ï': 'i',
      'í': 'i',
      'ô': 'o',
      'ö': 'o',
      'ó': 'o',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ú': 'u',
      'ÿ': 'y',
      'œ': 'oe',
    };
    var result = input;
    replacements.forEach((source, target) {
      result = result.replaceAll(source, target);
    });
    return result;
  }
}
