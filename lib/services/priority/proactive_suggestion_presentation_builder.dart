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
      PrioritySuggestionReason.missingDeadlineBlocksAssessment,
    )) {
      return ProactiveSuggestionPresentation(
        title: 'Pour ne pas l’oublier',
        message: 'Tu dois faire $quotedLabel avant quand ?',
        callToActionLabel: 'Ajouter une date',
        assistantPrompt: 'Tu dois faire $quotedLabel avant quand ?',
      );
    }
    if (suggestion.reasonCodes.contains(
      PrioritySuggestionReason.missingDurationBlocksAssessment,
    )) {
      return ProactiveSuggestionPresentation(
        title: 'Combien de temps prévoir ?',
        message: 'Dis-moi combien de temps prend $quotedLabel et je pourrai '
            'te proposer un bon moment.',
        callToActionLabel: 'Ajouter le temps',
        assistantPrompt: 'Combien de temps te faut-il pour $quotedLabel ?',
      );
    }
    if (suggestion.reasonCodes.contains(PrioritySuggestionReason.overdue)) {
      return ProactiveSuggestionPresentation(
        title: 'Toujours d’actualité ?',
        message: '$quotedLabel a une ancienne date. C’est toujours à faire ?',
        callToActionLabel: 'Vérifier la tâche',
        assistantPrompt: '$quotedLabel est-il toujours à faire ?',
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
