import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/services/conversation_turn_intent_service.dart';

void main() {
  const service = ConversationTurnIntentService();

  test('understands bounded ways to abandon the current conversation', () {
    for (final message in <String>[
      'annul',
      'annuler',
      'stop',
      'arrête',
      'laisse tomber',
      "j'ai changé d'avis",
      'je préfère arrêter',
      'je voudrais annuler',
      'tu peux abandonner cette demande',
      'pas maintenant',
    ]) {
      expect(
        service.interpret(message).intent,
        ConversationTurnIntent.cancelCurrentFlow,
        reason: message,
      );
    }
  });

  test('separates a targeted action from abandoning the current flow', () {
    for (final message in <String>[
      'annule mon rendez-vous de lundi',
      'ajoute du lait aux courses',
      'rappelle-moi de téléphoner à maman',
      'quelle est ma date de mariage',
    ]) {
      expect(
        service.interpret(message).intent,
        ConversationTurnIntent.switchToNewRequest,
        reason: message,
      );
    }
  });

  test('extracts the useful content from a conversational correction', () {
    final cases = <String, String>{
      'en fait dentiste': 'dentiste',
      'finalement mardi': 'mardi',
      'je voulais dire 15h': '15h',
      'non plutôt jeudi': 'jeudi',
      'remplace ça par 45 minutes': '45 minutes',
      'change pour vendredi': 'vendredi',
    };

    for (final entry in cases.entries) {
      final result = service.interpret(entry.key);
      expect(
        result.intent,
        ConversationTurnIntent.reviseCurrentAnswer,
        reason: entry.key,
      );
      expect(result.semanticContent, entry.value, reason: entry.key);
    }
  });

  test('never turns a negated control command into a cancellation', () {
    for (final message in <String>[
      "n'annule pas",
      'annule pas',
      "n'arrête pas",
      'ne supprime jamais',
    ]) {
      expect(
        service.interpret(message).intent,
        ConversationTurnIntent.ambiguousControl,
        reason: message,
      );
    }
  });

  test('identifies which Event field the user is talking about', () {
    final cases = <String, ConversationTurnSemanticField>{
      '15h': ConversationTurnSemanticField.time,
      '15 heures': ConversationTurnSemanticField.time,
      'seize heures': ConversationTurnSemanticField.time,
      'à cinq heures': ConversationTurnSemanticField.time,
      'mardi': ConversationTurnSemanticField.date,
      'mardi à 15 heures': ConversationTurnSemanticField.dateAndTime,
      'mardi à cinq heures': ConversationTurnSemanticField.dateAndTime,
      'le rendez-vous dure 45 minutes': ConversationTurnSemanticField.duration,
      "20 minutes pour l'aller": ConversationTurnSemanticField.travelGo,
      '10 minutes pour le trajet retour':
          ConversationTurnSemanticField.travelBack,
      '5 minutes de marge': ConversationTurnSemanticField.margin,
      "le motif c'est dentiste": ConversationTurnSemanticField.eventTitle,
      '1h': ConversationTurnSemanticField.currentQuestion,
      'une heure': ConversationTurnSemanticField.currentQuestion,
    };

    for (final entry in cases.entries) {
      expect(
        service.interpret(entry.key).semanticField,
        entry.value,
        reason: entry.key,
      );
    }
  });
}
