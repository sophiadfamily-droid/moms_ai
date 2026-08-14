import 'natural_language_normalizer.dart';
import 'natural_time_service.dart';

enum ConversationTurnIntent {
  answerCurrentQuestion,
  rejectCurrentProposal,
  cancelCurrentFlow,
  reviseCurrentAnswer,
  switchToNewRequest,
  ambiguousControl,
}

enum ConversationTurnSemanticField {
  currentQuestion,
  eventTitle,
  date,
  time,
  dateAndTime,
  duration,
  travelGo,
  travelBack,
  margin,
}

final class ConversationTurnInterpretation {
  const ConversationTurnInterpretation({
    required this.intent,
    required this.semanticContent,
    this.semanticField = ConversationTurnSemanticField.currentQuestion,
  });

  final ConversationTurnIntent intent;
  final String semanticContent;
  final ConversationTurnSemanticField semanticField;
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
        semanticField: _semanticField(revised),
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
      semanticField: _semanticField(normalized),
    );
  }

  static ConversationTurnSemanticField _semanticField(String value) {
    if (RegExp(
      r'\b(?:trajet\s+)?retour\b|\bpour\s+(?:le\s+)?retour\b|'
      r'\bpour\s+revenir\b',
    ).hasMatch(value)) {
      return ConversationTurnSemanticField.travelBack;
    }
    if (RegExp(
      r'\b(?:trajet\s+)?aller\b|\bpour\s+(?:l\s+)?aller\b|'
      r'\bpour\s+y\s+aller\b',
    ).hasMatch(value)) {
      return ConversationTurnSemanticField.travelGo;
    }
    if (RegExp(r'\b(?:marge|temps\s+de\s+securite)\b').hasMatch(value)) {
      return ConversationTurnSemanticField.margin;
    }
    if (RegExp(
      r'\b(?:duree|dure|durera|pendant|combien\s+de\s+temps)\b',
    ).hasMatch(value)) {
      return ConversationTurnSemanticField.duration;
    }

    final hasDate = RegExp(
      r'\b(?:aujourd\s+hui|demain|apres\s+demain|lundi|mardi|mercredi|'
      r'jeudi|vendredi|samedi|dimanche|jour|date)\b|'
      r'\b\d{1,2}[/.\-]\d{1,2}(?:[/.\-]\d{2,4})?\b|'
      r'\b\d{1,2}\s+(?:janvier|fevrier|mars|avril|mai|juin|juillet|'
      r'aout|septembre|octobre|novembre|decembre)\b',
    ).hasMatch(value);
    final parsedClock = NaturalTimeService.parseTime(value);
    final parsedHour = int.tryParse(parsedClock.split(':').first);
    final hasExplicitClockCue = RegExp(
      r'\b(?:a|vers|horaire|l\s+heure|midi|minuit)\b',
    ).hasMatch(value);
    final hasTime = parsedClock.isNotEmpty &&
        (hasDate || hasExplicitClockCue || (parsedHour ?? -1) >= 6);
    if (hasDate && hasTime) {
      return ConversationTurnSemanticField.dateAndTime;
    }
    if (hasDate) return ConversationTurnSemanticField.date;
    if (hasTime) return ConversationTurnSemanticField.time;
    if (RegExp(r'\b(?:motif|c\s+est\s+pour)\b').hasMatch(value)) {
      return ConversationTurnSemanticField.eventTitle;
    }
    return ConversationTurnSemanticField.currentQuestion;
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
