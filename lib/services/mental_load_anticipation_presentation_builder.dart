import '../models/mental_load_anticipation.dart';

final class MentalLoadAnticipationPresentation {
  const MentalLoadAnticipationPresentation({
    required this.title,
    required this.message,
    required this.callToActionLabel,
  });

  final String title;
  final String message;
  final String callToActionLabel;
}

/// Converts a proven anticipation into short, human-facing copy.
///
/// It never invents a preparation or an event label: both labels must come
/// from the canonical Task and Event domains.
final class MentalLoadAnticipationPresentationBuilder {
  const MentalLoadAnticipationPresentationBuilder();

  MentalLoadAnticipationPresentation build({
    required MentalLoadAnticipation anticipation,
    required String preparationLabel,
    required String eventLabel,
  }) {
    final preparation = preparationLabel.trim();
    final event = eventLabel.trim();
    if (preparation.isEmpty || event.isEmpty) {
      throw const FormatException('mental_load_presentation_label_missing');
    }
    return MentalLoadAnticipationPresentation(
      title: anticipation.priority == MentalLoadAnticipationPriority.urgent
          ? 'À prévoir bientôt'
          : 'À prévoir',
      message: 'Avant « $event », pense à « $preparation ».',
      callToActionLabel: 'Voir la préparation',
    );
  }
}
