import '../natural_language_normalizer.dart';

/// Recognises explicit, read-only requests to review what may need preparing.
///
/// This route is deliberately narrower than a generic request to organise a
/// day: it must not turn an Event or Task creation request into a consultation.
final class MentalLoadConsultationIntentDetector {
  const MentalLoadConsultationIntentDetector();

  bool matches(String message) {
    final value =
        const NaturalLanguageNormalizer().normalize(message).normalizedText;
    if (value.isEmpty || _isMutation(value)) return false;

    return RegExp(
          r'\bqu est ce que je (?:dois|devrais) anticiper\b',
        ).hasMatch(value) ||
        RegExp(
          r'\b(?:aide moi a|peux tu m aider a) anticiper\b',
        ).hasMatch(value) ||
        RegExp(
          r'\bqu est ce que je (?:dois|devrais) preparer '
          r'(?:en avance|pour les prochains jours|cette semaine)\b',
        ).hasMatch(value) ||
        RegExp(
          r'\best ce que j ai quelque chose a preparer '
          r'(?:en avance|pour les prochains jours|cette semaine)?\b',
        ).hasMatch(value) ||
        RegExp(
          r'\bque dois je penser a preparer\b',
        ).hasMatch(value);
  }

  bool _isMutation(String value) => RegExp(
        r'\b(?:cree|creer|ajoute|ajouter|mets|mettre|deplace|deplacer|'
        r'annule|annuler|supprime|supprimer|modifie|modifier|planifie|'
        r'planifier|reserve|reserver|previens|prevenir|notifie|notifier|'
        r'rappelle|rappeler)\b',
      ).hasMatch(value);
}
