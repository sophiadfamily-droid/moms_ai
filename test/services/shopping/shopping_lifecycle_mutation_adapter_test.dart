import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/revisioned_domain_models.dart';
import 'package:moms_ai/models/shopping/shopping_lifecycle_models.dart';
import 'package:moms_ai/models/shopping_item_model.dart';
import 'package:moms_ai/services/shopping/shopping_lifecycle_mutation_adapter.dart';

void main() {
  const adapter = ShoppingLifecycleMutationAdapter();

  test('maps add to the existing add mutation and clear generation', () {
    final plan = adapter.add(_item(), clearGeneration: 2);

    expect(plan.mutationType, ShoppingMutationType.addItem);
    expect(plan.transition.afterState, ShoppingLifecycleState.needed);
    expect(plan.transition.clearGeneration, 2);
  });

  test('maps update, bought and needed through SH.1', () {
    final current = _revisioned(_item(), revision: 3);
    final update = adapter.change(
      current: current,
      proposed: current.item.copyWith(title: 'Lait entier'),
    );
    final bought = adapter.change(
      current: current,
      proposed: current.item.copyWith(notes: 'Acheté', isBought: true),
    );
    final needed = adapter.change(
      current: _revisioned(_item(isBought: true), revision: 4),
      proposed: _item(isBought: false),
    );

    expect(update!.mutationType, ShoppingMutationType.updateItem);
    expect(bought!.mutationType, ShoppingMutationType.updateItem);
    expect(bought.transition.afterState, ShoppingLifecycleState.bought);
    expect(bought.persistencePayload.notes, 'Acheté');
    expect(needed!.transition.afterState, ShoppingLifecycleState.needed);
  });

  test('maps removal while retaining the legacy tombstone payload', () {
    final current = _revisioned(_item(), revision: 5, clearGeneration: 3);
    final plan = adapter.change(current: current, proposed: null)!;

    expect(plan.mutationType, ShoppingMutationType.removeItem);
    expect(plan.transition.item, isNull);
    expect(plan.transition.clearGeneration, 3);
    expect(plan.persistencePayload, same(current.item));
  });

  test('identical and tombstoned values produce no mutation', () {
    final current = _revisioned(_item(), revision: 2);
    expect(adapter.change(current: current, proposed: current.item), isNull);
    expect(
      adapter.change(
        current: _revisioned(_item(), revision: 2, tombstone: true),
        proposed: _item(),
      ),
      isNull,
    );
  });
}

ShoppingItemModel _item({bool isBought = false}) => ShoppingItemModel(
      id: 'shopping-1',
      title: 'Lait',
      isBought: isBought,
      createdAt: DateTime.utc(2026, 8, 4),
      category: 'Frais',
      section: 'Aujourd’hui',
    );

RevisionedShoppingItem _revisioned(
  ShoppingItemModel item, {
  required int revision,
  bool tombstone = false,
  int clearGeneration = 0,
}) =>
    RevisionedShoppingItem(
      accountScopeId: 'account-a',
      entityId: item.id!,
      item: item,
      revision: revision,
      createdAt: DateTime.utc(2026, 8, 4),
      updatedAt: DateTime.utc(2026, 8, 4),
      lastMutationId: 'mutation-$revision',
      isTombstone: tombstone,
      clearGeneration: clearGeneration,
    );
