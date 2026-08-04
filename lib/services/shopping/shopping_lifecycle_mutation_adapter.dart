import 'dart:convert';

import '../../models/revisioned_domain_models.dart';
import '../../models/shopping/shopping_lifecycle_models.dart';
import '../../models/shopping_item_model.dart';
import 'shopping_lifecycle_engine.dart';

/// SH.2 maps a validated SH.1 transition to the existing revisioned protocol.
/// It plans a mutation but never persists it.
final class ShoppingLifecycleMutationPlan {
  const ShoppingLifecycleMutationPlan({
    required this.transition,
    required this.mutationType,
    required this.persistencePayload,
  });

  final ShoppingLifecycleTransition transition;
  final ShoppingMutationType mutationType;
  final ShoppingItemModel persistencePayload;
}

final class ShoppingLifecycleMutationAdapter {
  const ShoppingLifecycleMutationAdapter();

  ShoppingLifecycleMutationPlan add(
    ShoppingItemModel proposed, {
    required int clearGeneration,
  }) {
    final transition = const ShoppingLifecycleEngine().transition(
      ShoppingLifecycleRequest(
        operation: ShoppingLifecycleOperation.add,
        expectedRevision: 0,
        clearGeneration: clearGeneration,
        proposed: proposed,
      ),
    );
    return ShoppingLifecycleMutationPlan(
      transition: transition,
      mutationType: ShoppingMutationType.addItem,
      persistencePayload: transition.item!,
    );
  }

  ShoppingLifecycleMutationPlan? change({
    required RevisionedShoppingItem current,
    required ShoppingItemModel? proposed,
  }) {
    if (current.isTombstone) return null;
    if (proposed != null &&
        jsonEncode(current.item.toJson()) == jsonEncode(proposed.toJson())) {
      return null;
    }
    final operation = proposed == null
        ? ShoppingLifecycleOperation.remove
        : current.item.isBought == proposed.isBought
            ? ShoppingLifecycleOperation.update
            : proposed.isBought
                ? ShoppingLifecycleOperation.markBought
                : ShoppingLifecycleOperation.markNeeded;
    final transition = const ShoppingLifecycleEngine().transition(
      ShoppingLifecycleRequest(
        operation: operation,
        expectedRevision: current.revision,
        clearGeneration: current.clearGeneration,
        current: current.item,
        proposed:
            operation == ShoppingLifecycleOperation.remove ? null : proposed,
      ),
    );
    return ShoppingLifecycleMutationPlan(
      transition: transition,
      // The existing persistence protocol represents all non-removal edits
      // with updateItem; the lifecycle transition keeps the intent explicit.
      mutationType: operation == ShoppingLifecycleOperation.remove
          ? ShoppingMutationType.removeItem
          : ShoppingMutationType.updateItem,
      // The legacy tombstone protocol retains the previous payload.
      persistencePayload: transition.item ?? current.item,
    );
  }
}
