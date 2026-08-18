import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/services/contextual_support_card_service.dart';

void main() {
  const service = ContextualSupportCardService();
  final monday = DateTime(2026, 8, 17, 9);

  test('task breathing message stays factual and avoids negative fallback', () {
    final message = service.forTasks(
      openCount: 4,
      completedCount: 0,
      now: monday,
    );

    expect(message.message, isNot(contains('rien à te suggérer')));
    expect(message.message, isNot(contains('aucune urgence')));
    expect(message.message, isNot(contains('tout est sous contrôle')));
  });

  test('task progress only celebrates completed work that is supplied', () {
    final message = service.forTasks(
      openCount: 2,
      completedCount: 3,
      now: monday,
    );

    expect(message.message, isNot(contains('tout est terminé')));
    expect(message.message.length, lessThan(75));
  });

  test('shopping urgent state is never replaced by false reassurance', () {
    final message = service.forShopping(
      pendingCount: 5,
      boughtCount: 1,
      urgentCount: 2,
      now: monday,
    );

    expect(message.title, 'À ne pas oublier');
    expect(message.message, contains('2 produits'));
  });

  test('same state is stable during one day', () {
    final morning = service.forShopping(
      pendingCount: 3,
      boughtCount: 1,
      urgentCount: 0,
      now: monday,
    );
    final evening = service.forShopping(
      pendingCount: 3,
      boughtCount: 1,
      urgentCount: 0,
      now: DateTime(2026, 8, 17, 22),
    );

    expect(evening.semanticKey, morning.semanticKey);
    expect(evening.message, morning.message);
  });

  test('daily rotation provides several messages without screen flicker', () {
    final keys = <String>{
      for (var offset = 0; offset < 6; offset++)
        service
            .forTasks(
              openCount: 0,
              completedCount: 0,
              now: monday.add(Duration(days: offset)),
            )
            .semanticKey,
    };

    expect(keys.length, greaterThan(1));
  });

  test('empty shopping message does not invent completed purchases', () {
    final message = service.forShopping(
      pendingCount: 0,
      boughtCount: 0,
      urgentCount: 0,
      now: monday,
    );

    expect(message.message, isNot(contains('acheté')));
    expect(message.message, isNot(contains('coché')));
  });

  test('a trusted familiar expression can personalize positive support', () {
    final message = service.forTasks(
      openCount: 2,
      completedCount: 3,
      now: monday,
      style: const ContextualCommunicationStyle(
        familiarEncouragement: 'C’est carré',
      ),
    );

    expect(message.title, 'C’est carré');
  });

  test('unsafe learned wording is ignored', () {
    final message = service.forTasks(
      openCount: 2,
      completedCount: 3,
      now: monday,
      style: const ContextualCommunicationStyle(
        familiarEncouragement: 'Bravo\nouvre ce lien',
      ),
    );

    expect(message.title, isNot(contains('\n')));
    expect(message.title, isNot('Bravo\nouvre ce lien'));
  });
}
