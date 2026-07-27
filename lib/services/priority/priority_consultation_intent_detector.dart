final class PriorityConsultationIntentDetector {
  const PriorityConsultationIntentDetector();

  bool matches(String message) {
    final value = _normalize(message);
    if (value.isEmpty || _isMutationOrDefinition(value)) return false;

    return RegExp(
          r'\bquelles? (?:sont )?mes priorites\b',
        ).hasMatch(value) ||
        RegExp(
          r'\bsur quoi (?:est ce que )?je (?:dois |devrais )?'
          r'(?:me )?concentrer\b',
        ).hasMatch(value) ||
        RegExp(
          r'\bqu est ce (?:que je dois faire|qui est) '
          r'(?:en priorite|d urgent|urgent|en premier)\b',
        ).hasMatch(value) ||
        RegExp(
          r'\bque dois je faire (?:en priorite|en premier)\b',
        ).hasMatch(value) ||
        RegExp(
          r'\best ce que j oublie quelque chose d important\b',
        ).hasMatch(value) ||
        RegExp(
          r'\bdonne moi (?:mes |les )?(?:(?:trois|3) )?priorites\b',
        ).hasMatch(value) ||
        RegExp(
          r'\bqu est ce qui est urgent\b',
        ).hasMatch(value);
  }

  bool _isMutationOrDefinition(String value) =>
      RegExp(
        r'\b(?:cree|creer|ajoute|ajouter|mets|mettre|deplace|deplacer|'
        r'annule|annuler|supprime|supprimer|modifie|modifier|organise|'
        r'organiser|planifie|planifier|previens|prevenir|notifie|notifier|'
        r'rappelle|rappeler)\b',
      ).hasMatch(value) ||
      RegExp(
        r'\b(?:definition|definis|definir|signifie|veut dire)\b',
      ).hasMatch(value) ||
      RegExp(r'\b(?:prefere|preference)\b').hasMatch(value);

  String _normalize(String input) {
    const replacements = {
      'à': 'a',
      'â': 'a',
      'ä': 'a',
      'ç': 'c',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'î': 'i',
      'ï': 'i',
      'ô': 'o',
      'ö': 'o',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ÿ': 'y',
      'œ': 'oe',
    };
    var value = input.toLowerCase().replaceAll(RegExp(r'[’‘`´]'), "'");
    replacements.forEach((source, target) {
      value = value.replaceAll(source, target);
    });
    return value
        .replaceAll("'", ' ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }
}
