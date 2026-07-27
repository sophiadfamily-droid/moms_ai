import '../../models/life_context/life_context_projection.dart';
import '../../models/priority/priority_models.dart';
import 'priority_candidate_adapter.dart';
import 'priority_engine.dart';
import 'priority_suggestion_builder.dart';
import 'priority_suggestion_conversation_context.dart';

typedef PriorityConsultationProjectionLoader = Future<LifeContextProjection>
    Function();

final class PriorityConsultationResponse {
  const PriorityConsultationResponse({
    required this.reply,
    required this.suggestionCount,
  });

  final String reply;
  final int suggestionCount;
}

/// Read-only production route from the canonical Life Context projection to
/// the canonical ranking and suggestion builders.
final class PriorityConsultationService {
  const PriorityConsultationService({
    required PriorityConsultationProjectionLoader loadProjection,
    DateTime Function()? clock,
    PriorityCandidateAdapter candidateAdapter =
        const PriorityCandidateAdapter(),
    PrioritySuggestionBuilder suggestionBuilder =
        const PrioritySuggestionBuilder(),
    PrioritySuggestionConversationContextBuilder contextBuilder =
        const PrioritySuggestionConversationContextBuilder(),
  })  : _loadProjection = loadProjection,
        _clock = clock,
        _candidateAdapter = candidateAdapter,
        _suggestionBuilder = suggestionBuilder,
        _contextBuilder = contextBuilder;

  final PriorityConsultationProjectionLoader _loadProjection;
  final DateTime Function()? _clock;
  final PriorityCandidateAdapter _candidateAdapter;
  final PrioritySuggestionBuilder _suggestionBuilder;
  final PrioritySuggestionConversationContextBuilder _contextBuilder;

  Future<PriorityConsultationResponse> respond() async {
    final referenceDate = (_clock ?? DateTime.now)().toUtc();
    try {
      final projection = await _loadProjection();
      final accountScopeId = projection.accountScopeId.trim();
      if (accountScopeId.isEmpty) return _unavailable();
      final candidates = _candidateAdapter.fromProjection(
        projection,
        evaluatedAt: referenceDate,
      );
      final ranking = PriorityEngine().rank(
        candidates,
        evaluatedAt: referenceDate,
        expectedAccountScopeId: accountScopeId,
      );
      final result = _suggestionBuilder.build(
        ranking: ranking,
        accountScopeId: accountScopeId,
        referenceDate: referenceDate,
      );
      final context = _contextBuilder.build(result);
      if (context.items.isEmpty) {
        final hasBlockingMissingInformation = ranking.items.any(
          (item) => item.score.missingData.any(
            (code) => {
              PriorityMissingData.deadline,
              PriorityMissingData.effort,
            }.contains(code),
          ),
        );
        return PriorityConsultationResponse(
          reply: hasBlockingMissingInformation
              ? "Je n'ai pas assez d'informations pour établir une priorité "
                  'fiable. Tu peux préciser une échéance ou une durée sur les '
                  'éléments concernés.'
              : 'Je ne vois rien de critique nécessitant ton attention '
                  'immédiate avec les informations disponibles.',
          suggestionCount: 0,
        );
      }
      final lines = <String>[
        'Voici ce qui mérite ton attention maintenant :',
        '',
        for (var index = 0; index < context.items.length; index++)
          '${index + 1}. ${context.items[index].message}',
        '',
        "Je peux ensuite t'aider à examiner l'un de ces éléments.",
      ];
      return PriorityConsultationResponse(
        reply: lines.join('\n'),
        suggestionCount: context.items.length,
      );
    } on Object {
      return _unavailable();
    }
  }

  PriorityConsultationResponse _unavailable() =>
      const PriorityConsultationResponse(
        reply: "Je n'ai pas assez d'informations pour établir une priorité "
            'fiable pour le moment.',
        suggestionCount: 0,
      );
}
