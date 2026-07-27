import '../../models/priority/priority_suggestion_models.dart';

final class PrioritySuggestionConversationItem {
  const PrioritySuggestionConversationItem({
    required this.suggestionType,
    required this.horizon,
    required this.severity,
    required this.reasonCodes,
    required this.missingInformationCodes,
    required this.proposedNextStep,
    required this.confirmationRequired,
    required this.message,
  });

  final PrioritySuggestionType suggestionType;
  final PrioritySuggestionHorizon horizon;
  final PrioritySuggestionSeverity severity;
  final List<PrioritySuggestionReason> reasonCodes;
  final List<String> missingInformationCodes;
  final PrioritySuggestionNextStep proposedNextStep;
  final bool confirmationRequired;
  final String message;
}

final class PrioritySuggestionConversationContext {
  const PrioritySuggestionConversationContext({
    required this.items,
    required this.warningCodes,
    required this.calculatedAt,
  });

  final List<PrioritySuggestionConversationItem> items;
  final List<PrioritySuggestionWarning> warningCodes;
  final DateTime calculatedAt;
}

/// Local read-only presentation boundary. It never calls the backend and never
/// creates a structured action.
final class PrioritySuggestionConversationContextBuilder {
  const PrioritySuggestionConversationContextBuilder();

  PrioritySuggestionConversationContext build(PrioritySuggestionResult result) {
    return PrioritySuggestionConversationContext(
      items: result.suggestions
          .map(
            (suggestion) => PrioritySuggestionConversationItem(
              suggestionType: suggestion.suggestionType,
              horizon: suggestion.horizon,
              severity: suggestion.severity,
              reasonCodes: suggestion.reasonCodes,
              missingInformationCodes: suggestion.missingInformationCodes
                  .map((item) => item.name)
                  .toList(growable: false),
              proposedNextStep: suggestion.proposedNextStep,
              confirmationRequired: suggestion.confirmationRequired,
              message: _message(suggestion),
            ),
          )
          .toList(growable: false),
      warningCodes: result.warnings.toList()
        ..sort((a, b) => a.name.compareTo(b.name)),
      calculatedAt: result.referenceDate,
    );
  }

  String _message(PrioritySuggestion suggestion) =>
      switch (suggestion.suggestionType) {
        PrioritySuggestionType.actSoon =>
          'Une échéance prouvée approche. Tu peux ouvrir cet élément pour le vérifier.',
        PrioritySuggestionType.prepare =>
          'Cet engagement fixe commence bientôt et le trajet aller est renseigné.',
        PrioritySuggestionType.clarifyMissingInformation =>
          'La durée manque pour évaluer si cet élément reste réalisable à temps.',
        PrioritySuggestionType.reviewConflict =>
          'Deux engagements confirmés se chevauchent. Vérifie-les avant de modifier ton planning.',
        PrioritySuggestionType.protectFixedCommitment =>
          'Cet engagement commence bientôt et son horaire est fixe.',
        PrioritySuggestionType.reviewOverdueItem =>
          'Cette échéance est dépassée et comporte une conséquence structurée.',
        PrioritySuggestionType.monitorDeadline =>
          'Une échéance significative approche dans les prochains jours.',
      };
}
