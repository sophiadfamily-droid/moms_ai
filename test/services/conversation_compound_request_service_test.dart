import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/services/conversation_compound_request_service.dart';

void main() {
  final referenceDate = DateTime(2026, 8, 14, 12);
  const service = ConversationCompoundRequestService();

  group('ConversationCompoundRequestService', () {
    test('separates two explicit requests from different domains', () {
      final result = service.split(
        'Dentiste demain à 14h puis ajoute du lait aux courses',
        referenceDate: referenceDate,
      );

      expect(result, isNotNull);
      expect(
        result!.parts,
        ['Dentiste demain à 14h', 'ajoute du lait aux courses'],
      );
      expect(
        result.domains,
        [ConversationRequestDomain.event, ConversationRequestDomain.shopping],
      );
    });

    test('separates a task followed by an explicit memory request', () {
      final result = service.split(
        'Crée une tâche appeler maman ensuite souviens-toi que je préfère '
        'les rendez-vous le matin',
        referenceDate: referenceDate,
      );

      expect(result, isNotNull);
      expect(result!.domains, [
        ConversationRequestDomain.task,
        ConversationRequestDomain.memory,
      ]);
    });

    test('allows a contextual first answer only during an active request', () {
      final result = service.split(
        'dentiste et ajoute du lait aux courses',
        referenceDate: referenceDate,
        allowContextualLeadingPart: true,
      );

      expect(result, isNotNull);
      expect(result!.parts, ['dentiste', 'ajoute du lait aux courses']);
      expect(result.domains.first, isNull);
      expect(result.domains.last, ConversationRequestDomain.shopping);
    });

    test('keeps a shopping list in one request', () {
      final result = service.split(
        'ajoute du lait et du pain aux courses',
        referenceDate: referenceDate,
      );

      expect(result, isNull);
    });

    test('keeps same-domain wording in its specialist parser', () {
      final result = service.split(
        'ajoute un rendez-vous dentiste demain à 14h puis programme le '
        'médecin vendredi à 10h',
        referenceDate: referenceDate,
      );

      expect(result, isNull);
    });

    test('refuses to segment a request containing a negation', () {
      final result = service.split(
        "n'ajoute pas de lait puis crée une tâche appeler maman",
        referenceDate: referenceDate,
      );

      expect(result, isNull);
    });

    test('refuses more clauses than the bounded queue accepts', () {
      final result = service.split(
        'Dentiste demain à 14h puis ajoute du lait aux courses puis crée une '
        'tâche appeler maman puis souviens-toi que je préfère le matin',
        referenceDate: referenceDate,
      );

      expect(result, isNull);
    });
  });
}
