import 'natural_language_normalizer.dart';
import 'conversation_turn_intent_service.dart';

enum ConversationAnswer { positive, negative, ambiguous }

final class ConversationAnswerClassifier {
  const ConversationAnswerClassifier();

  ConversationAnswer classify(String input) {
    final normalized = _normalize(input);
    if (normalized.isEmpty) return ConversationAnswer.ambiguous;
    final turn = const ConversationTurnIntentService().interpret(input);
    if (turn.intent == ConversationTurnIntent.cancelCurrentFlow ||
        turn.intent == ConversationTurnIntent.rejectCurrentProposal) {
      return ConversationAnswer.negative;
    }
    if (turn.intent == ConversationTurnIntent.ambiguousControl ||
        turn.intent == ConversationTurnIntent.reviseCurrentAnswer ||
        turn.intent == ConversationTurnIntent.switchToNewRequest) {
      return ConversationAnswer.ambiguous;
    }
    final positive = _matchesPositive(normalized);
    final negative = _matchesNegative(normalized);
    if (positive == negative) return ConversationAnswer.ambiguous;
    return positive ? ConversationAnswer.positive : ConversationAnswer.negative;
  }

  bool _matchesPositive(String value) {
    const exact = {
      'oui',
      'ouais',
      'ouais vas y',
      'yep',
      'd accord',
      'vas y',
      'ok fais le',
      'confirme',
      'garde cette information',
      'tu peux la memoriser',
      'oui retiens le',
      'oui retiens la',
      'oui je confirme',
    };
    if (exact.contains(value)) return true;
    return value.startsWith('oui ') &&
        const ['retiens', 'garde', 'memorise', 'confirme']
            .any(value.substring(4).startsWith);
  }

  bool _matchesNegative(String value) {
    const exact = {
      'non',
      'nan',
      'non merci',
      'laisse tomber',
      'oublie',
      'annule',
      'ne retiens pas ca',
      'ne retiens pas cette information',
      'je ne veux pas que tu le memorises',
      'je ne veux pas que tu la memorises',
      'ne remplace pas',
      'garde l ancienne information',
    };
    if (exact.contains(value)) return true;
    return value.startsWith('ne retiens pas ');
  }

  String _normalize(String value) {
    return const NaturalLanguageNormalizer().normalize(value).normalizedText;
  }
}
