import '../../models/priority/proactive_priority_models.dart';
import '../../models/priority/priority_suggestion_models.dart';

final class ProactiveSuggestionPresentation {
  const ProactiveSuggestionPresentation({
    required this.title,
    required this.message,
    required this.callToActionLabel,
    required this.assistantPrompt,
  });

  final String title;
  final String message;
  final String callToActionLabel;
  final String assistantPrompt;
}

/// Builds user-facing copy from a validated proactive suggestion and the
/// resolved source label. It has no persistence or navigation side effect.
final class ProactiveSuggestionPresentationBuilder {
  const ProactiveSuggestionPresentationBuilder();

  ProactiveSuggestionPresentation build({
    required ProactiveSuggestion suggestion,
    required String sourceLabel,
  }) {
    final label = sourceLabel.trim();
    if (label.isEmpty) {
      throw const FormatException('missing_proactive_source_label');
    }
    final quotedLabel = '“$label”';
    if (suggestion.reasonCodes.contains(
      PrioritySuggestionReason.missingDurationBlocksAssessment,
    )) {
      return ProactiveSuggestionPresentation(
        title: 'Durée à préciser',
        message: 'Il manque la durée de $quotedLabel. '
            'Ajoute une durée pour que je puisse vérifier si cette tâche '
            'est réalisable avant son échéance.',
        callToActionLabel: 'Ajouter une durée',
        assistantPrompt: 'Combien de temps veux-tu prévoir pour $quotedLabel ?',
      );
    }
    return ProactiveSuggestionPresentation(
      title: 'Priorité à vérifier',
      message: '${suggestion.message} Ouvre $quotedLabel pour agir.',
      callToActionLabel: _defaultCallToActionLabel(suggestion.callToAction),
      assistantPrompt: 'Ouvre $quotedLabel pour consulter cette priorité.',
    );
  }

  String _defaultCallToActionLabel(
    ProactiveSuggestionCallToActionType callToAction,
  ) =>
      switch (callToAction) {
        ProactiveSuggestionCallToActionType.openTask => 'Ouvrir la tâche',
        ProactiveSuggestionCallToActionType.openEvent =>
          'Ouvrir le rendez-vous',
        ProactiveSuggestionCallToActionType.reviewSchedule =>
          'Voir le planning',
        ProactiveSuggestionCallToActionType.completeInformation =>
          'Compléter les informations',
      };
}
