import 'natural_language_normalizer.dart';

enum ConversationTurnIntent {
  answerCurrentQuestion,
  rejectCurrentProposal,
  cancelCurrentFlow,
  reviseCurrentAnswer,
  switchToNewRequest,
  ambiguousControl,
}

final class ConversationTurnInterpretation {
  const ConversationTurnInterpretation({
    required this.intent,
    required this.semanticContent,
  });

  final ConversationTurnIntent intent;
  final String semanticContent;
}

/// Interprète le rôle d'un message avant de le consommer comme une valeur.
///
/// Cette barrière empêche par exemple une demande d'annulation d'être utilisée
/// comme titre de rendez-vous. Les règles restent volontairement fermées : une
/// négation ou une commande avec une cible précise n'annule jamais un brouillon
/// silencieusement.
final class ConversationTurnIntentService {
  const ConversationTurnIntentService();

  ConversationTurnInterpretation interpret(String input) {
    final normalized =
        const NaturalLanguageNormalizer().normalize(input).normalizedText;
    if (normalized.isEmpty) {
      return const ConversationTurnInterpretation(
        intent: ConversationTurnIntent.answerCurrentQuestion,
        semanticContent: '',
      );
    }

    if (_hasNegatedControl(normalized)) {
      return ConversationTurnInterpretation(
        intent: ConversationTurnIntent.ambiguousControl,
        semanticContent: normalized,
      );
    }

    if (_isStandaloneCancellation(normalized)) {
      return ConversationTurnInterpretation(
        intent: ConversationTurnIntent.cancelCurrentFlow,
        semanticContent: normalized,
      );
    }

    if (_isSimpleRejection(normalized)) {
      return ConversationTurnInterpretation(
        intent: ConversationTurnIntent.rejectCurrentProposal,
        semanticContent: normalized,
      );
    }

    final revised = _revisedContent(normalized);
    if (revised != null) {
      return ConversationTurnInterpretation(
        intent: ConversationTurnIntent.reviseCurrentAnswer,
        semanticContent: revised,
      );
    }

    if (_isExplicitNewRequest(normalized)) {
      return ConversationTurnInterpretation(
        intent: ConversationTurnIntent.switchToNewRequest,
        semanticContent: normalized,
      );
    }

    return ConversationTurnInterpretation(
      intent: ConversationTurnIntent.answerCurrentQuestion,
      semanticContent: normalized,
    );
  }

  static bool _hasNegatedControl(String value) => RegExp(
        r'\b(?:ne|n)\s+(?:veux\s+)?(?:annul\w*|arrete?\w*|abandonne?\w*|'
        r'ferme\w*|supprime\w*)\b.{0,24}\b(?:pas|plus|jamais)\b|'
        r'\b(?:annul\w*|arrete?\w*|abandonne?\w*|ferme\w*|supprime\w*)\s+pas\b',
      ).hasMatch(value);

  static String? _revisedContent(String value) {
    final match = RegExp(
      r'^(?:(?:non\s+)?plutot|en\s+fait|finalement|je\s+voulais\s+dire|'
      r'corrige(?:\s+ca)?(?:\s+en|\s+avec)?|remplace(?:\s+ca)?\s+par)\s+(.+)$',
    ).firstMatch(value);
    final actionMatch = RegExp(
      r'^(?:mets?|change|decale|deplace)(?:\s+ca)?\s+(?:a|au|pour|en)\s+(.+)$',
    ).firstMatch(value);
    final content = (match ?? actionMatch)?.group(1)?.trim() ?? '';
    return content.isEmpty ? null : content;
  }

  static bool _isStandaloneCancellation(String value) {
    final withoutPoliteness = value
        .replaceAll(
          RegExp(
            r'\s+(?:stp|svp|merci|s il te plait|s il vous plait)$',
          ),
          '',
        )
        .trim();
    return RegExp(
      r'^(?:ann?ul(?:e|er|ons|ez)?|stop(?:pe)?|arrete?|abandonne?|'
      r'laisse(?:r)?\s+tomber|on\s+laisse\s+tomber|on\s+arrete|'
      r'oublie\s+(?:ca|cette\s+demande)|pas\s+maintenant|'
      r'finalement\s+non|j\s+ai\s+change\s+d\s+avis|'
      r'(?:je\s+(?:veux|voudrais|souhaite|prefere)|tu\s+peux)\s+'
      r'(?:annuler|arreter|abandonner)(?:\s+(?:ca|cette\s+demande))?)$',
    ).hasMatch(withoutPoliteness);
  }

  static bool _isSimpleRejection(String value) => const {
        'non',
        'nan',
        'non merci',
      }.contains(value);

  static bool _isExplicitNewRequest(String value) =>
      RegExp(
        r'^(?:(?:je\s+veux|je\s+voudrais|tu\s+peux)\s+)?'
        r'(?:ajoute\w*|achete\w*|cree\w*|note\w*|rappelle\w*|'
        r'souviens\w*|memorise\w*|planifie\w*|programme\w*|cale\w*|'
        r'trouve\w*|cherche\w*|propose\w*|annule\w*|supprime\w*|'
        r'deplace\w*|decale\w*|modifie\w*|change\w*)\s+\S+',
      ).hasMatch(value) ||
      RegExp(r'^(?:quelle?s?|quels?|quand|ou|comment|pourquoi)\s+\S+')
          .hasMatch(value);
}
