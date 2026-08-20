import '../mental_load_anticipation_suggestion_service.dart';

typedef MentalLoadConsultationSuggestionLoader
    = Future<List<MentalLoadAnticipationSuggestion>> Function();

final class MentalLoadConsultationResponse {
  const MentalLoadConsultationResponse({
    required this.reply,
    required this.suggestionCount,
  });

  final String reply;
  final int suggestionCount;
}

/// Read-only conversational view of already-proven mental-load anticipations.
///
/// It neither records a proactive display receipt nor creates an action. The
/// user explicitly asked to consult the information, so the same result may be
/// requested again without a presentation cooldown.
final class MentalLoadConsultationService {
  const MentalLoadConsultationService({
    required MentalLoadConsultationSuggestionLoader loadSuggestions,
  }) : _loadSuggestions = loadSuggestions;

  final MentalLoadConsultationSuggestionLoader _loadSuggestions;

  Future<MentalLoadConsultationResponse> respond() async {
    try {
      final suggestions = await _loadSuggestions();
      final visible = <MentalLoadAnticipationSuggestion>[];
      final seen = <String>{};
      for (final suggestion in suggestions) {
        if (!seen.add(suggestion.canonicalKey)) continue;
        visible.add(suggestion);
        if (visible.length == 3) break;
      }
      if (visible.isEmpty) {
        return const MentalLoadConsultationResponse(
          reply: 'Je ne vois rien à préparer en avance pour le moment. '
              'Je garde un œil sur ce qui arrive.',
          suggestionCount: 0,
        );
      }

      final lines = <String>[
        visible.length == 1
            ? 'Oui, il y a une chose à prévoir :'
            : 'Oui, voici ce que tu peux prévoir :',
        '',
        for (final suggestion in visible)
          '• Avant « ${suggestion.eventLabel.trim()} », pense à '
              '« ${suggestion.preparationLabel.trim()} ».',
      ];
      return MentalLoadConsultationResponse(
        reply: lines.join('\n'),
        suggestionCount: visible.length,
      );
    } on Object {
      return const MentalLoadConsultationResponse(
        reply: "Je n'arrive pas à vérifier ce qu'il faut anticiper pour le "
            'moment. Tu peux réessayer un peu plus tard.',
        suggestionCount: 0,
      );
    }
  }
}
