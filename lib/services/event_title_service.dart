class EventTitleService {
  static const String clarificationQuestion =
      'Quel est le motif du rendez-vous ?';
  static const String precisionQuestion =
      'Peux-tu préciser le motif du rendez-vous ?';

  static bool isGeneric(String title) {
    final value = _normalize(title);
    if (value.isEmpty) return true;
    return RegExp(
      r'^(?:(?:mon|un|le)\s+)?(?:rendez vous|rdv|appointment)'
      r'(?:\s+(?:demain|aujourd hui|vendredi|lundi|mardi|mercredi|jeudi|samedi|dimanche))?$',
    ).hasMatch(value);
  }

  static String? titleFromMotif(String answer) {
    final clean = answer.trim().replaceAll(RegExp(r'\s+'), ' ');
    final normalized = _normalize(clean);
    if (clean.isEmpty || clean.length > 120 || isGeneric(clean)) return null;
    if (const {
      'ca',
      'lui',
      'elle',
      'pareil',
      'un truc',
      'je sais pas',
      'je ne sais pas',
    }.contains(normalized)) {
      return null;
    }
    if (_looksLikeIndependentRequest(normalized)) return null;

    final beginsWithEventLabel = RegExp(
      r'^(rendez vous|rdv|consultation|entretien|controle technique)\b',
    ).hasMatch(normalized);
    final title = beginsWithEventLabel ? clean : 'Rendez-vous $clean';
    return _capitalize(title);
  }

  static bool shouldRouteIndependently(String answer) {
    return _looksLikeIndependentRequest(_normalize(answer));
  }

  static bool _looksLikeIndependentRequest(String value) {
    return RegExp(
      r'^(quelles?|quels?|ajoute|achete|acheter|mets|annule|annuler|supprime|supprimer|deplace|deplacer|modifie|modifier)\b',
    ).hasMatch(value);
  }

  static String _capitalize(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  static String _normalize(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('’', "'")
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'[.!?,;:]+$'), '')
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('ë', 'e')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ù', 'u')
        .replaceAll('û', 'u')
        .replaceAll('î', 'i')
        .replaceAll('ï', 'i')
        .replaceAll('ô', 'o')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'\s+'), ' ');
  }
}
