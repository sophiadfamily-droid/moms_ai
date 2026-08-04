import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/shopping/shopping_lifecycle_models.dart';
import 'package:moms_ai/models/shopping_item_model.dart';
import 'package:moms_ai/services/shopping/shopping_lifecycle_engine.dart';

void main() {
  const engine = ShoppingLifecycleEngine();

  test('add creates one needed item at revision one', () {
    final transition = engine.transition(
      ShoppingLifecycleRequest(
        operation: ShoppingLifecycleOperation.add,
        expectedRevision: 0,
        clearGeneration: 2,
        proposed: _item(),
      ),
    );

    expect(transition.beforeState, isNull);
    expect(transition.afterState, ShoppingLifecycleState.needed);
    expect(transition.nextRevision, 1);
    expect(transition.clearGeneration, 2);
  });

  test('update preserves identity, creation time and bought state', () {
    final current = _item();
    final transition = engine.transition(
      ShoppingLifecycleRequest(
        operation: ShoppingLifecycleOperation.update,
        expectedRevision: 4,
        clearGeneration: 1,
        current: current,
        proposed: current.copyWith(notes: 'Deux bouteilles'),
      ),
    );

    expect(transition.nextRevision, 5);
    expect(transition.afterState, ShoppingLifecycleState.needed);
    expect(transition.item!.notes, 'Deux bouteilles');
  });

  test('bought and needed are explicit reversible transitions', () {
    final bought = engine.transition(
      ShoppingLifecycleRequest(
        operation: ShoppingLifecycleOperation.markBought,
        expectedRevision: 1,
        clearGeneration: 0,
        current: _item(),
      ),
    );
    final needed = engine.transition(
      ShoppingLifecycleRequest(
        operation: ShoppingLifecycleOperation.markNeeded,
        expectedRevision: 2,
        clearGeneration: 0,
        current: bought.item,
      ),
    );

    expect(bought.afterState, ShoppingLifecycleState.bought);
    expect(bought.item!.isBought, isTrue);
    expect(needed.afterState, ShoppingLifecycleState.needed);
    expect(needed.item!.isBought, isFalse);
  });

  test('remove carries no Shopping content', () {
    final transition = engine.transition(
      ShoppingLifecycleRequest(
        operation: ShoppingLifecycleOperation.remove,
        expectedRevision: 6,
        clearGeneration: 3,
        current: _item(),
      ),
    );

    expect(transition.afterState, ShoppingLifecycleState.removed);
    expect(transition.item, isNull);
    expect(transition.toJson(), isNot(containsPair('item', anything)));
  });

  test('generic update cannot hide a bought-state transition', () {
    final current = _item();
    expect(
      () => engine.transition(
        ShoppingLifecycleRequest(
          operation: ShoppingLifecycleOperation.update,
          expectedRevision: 1,
          clearGeneration: 0,
          current: current,
          proposed: current.copyWith(isBought: true),
        ),
      ),
      throwsA(
        isA<ShoppingLifecycleException>().having(
          (error) => error.code,
          'code',
          'invalid_shopping_update_transition',
        ),
      ),
    );
  });

  test('rejects missing identity and negative clear generation', () {
    expect(
      () => engine.transition(
        ShoppingLifecycleRequest(
          operation: ShoppingLifecycleOperation.add,
          expectedRevision: 0,
          clearGeneration: 0,
          proposed: _item(id: null),
        ),
      ),
      throwsA(isA<ShoppingLifecycleException>()),
    );
    expect(
      () => engine.transition(
        ShoppingLifecycleRequest(
          operation: ShoppingLifecycleOperation.add,
          expectedRevision: 0,
          clearGeneration: -1,
          proposed: _item(),
        ),
      ),
      throwsA(isA<ShoppingLifecycleException>()),
    );
  });
}

ShoppingItemModel _item({String? id = 'shopping-1'}) => ShoppingItemModel(
      id: id,
      title: 'Lait',
      isBought: false,
      createdAt: DateTime.utc(2026, 8, 4, 18),
      category: 'Frais',
      section: 'Aujourd’hui',
    );
