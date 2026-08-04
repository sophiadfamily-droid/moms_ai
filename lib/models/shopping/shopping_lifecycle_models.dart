import '../shopping_item_model.dart';

enum ShoppingLifecycleState { needed, bought, removed }

enum ShoppingLifecycleOperation {
  add,
  update,
  markBought,
  markNeeded,
  remove,
}

final class ShoppingLifecycleException implements Exception {
  const ShoppingLifecycleException(this.code);

  final String code;

  @override
  String toString() => 'ShoppingLifecycleException($code)';
}

final class ShoppingLifecycleRequest {
  const ShoppingLifecycleRequest({
    required this.operation,
    required this.expectedRevision,
    required this.clearGeneration,
    this.current,
    this.proposed,
  });

  final ShoppingLifecycleOperation operation;
  final int expectedRevision;
  final int clearGeneration;
  final ShoppingItemModel? current;
  final ShoppingItemModel? proposed;
}

/// Pure item transition. Collection-wide clear remains a separate boundary.
final class ShoppingLifecycleTransition {
  static const int currentSchemaVersion = 1;

  ShoppingLifecycleTransition({
    this.schemaVersion = currentSchemaVersion,
    required this.operation,
    required this.itemId,
    required this.expectedRevision,
    required this.nextRevision,
    required this.clearGeneration,
    required this.beforeState,
    required this.afterState,
    required this.item,
  }) {
    if (schemaVersion != currentSchemaVersion) {
      throw const ShoppingLifecycleException(
        'unsupported_shopping_lifecycle_version',
      );
    }
    if (itemId.trim().isEmpty ||
        expectedRevision < 0 ||
        nextRevision != expectedRevision + 1 ||
        clearGeneration < 0 ||
        (item != null && item!.id != itemId) ||
        !_matchesOperation()) {
      throw const ShoppingLifecycleException(
        'invalid_shopping_lifecycle_result',
      );
    }
  }

  final int schemaVersion;
  final ShoppingLifecycleOperation operation;
  final String itemId;
  final int expectedRevision;
  final int nextRevision;
  final int clearGeneration;
  final ShoppingLifecycleState? beforeState;
  final ShoppingLifecycleState afterState;
  final ShoppingItemModel? item;

  bool _matchesOperation() => switch (operation) {
        ShoppingLifecycleOperation.add => expectedRevision == 0 &&
            beforeState == null &&
            afterState == ShoppingLifecycleState.needed &&
            item != null &&
            !item!.isBought,
        ShoppingLifecycleOperation.update => expectedRevision >= 1 &&
            beforeState != null &&
            beforeState == afterState &&
            afterState != ShoppingLifecycleState.removed &&
            item != null &&
            item!.isBought == (afterState == ShoppingLifecycleState.bought),
        ShoppingLifecycleOperation.markBought => expectedRevision >= 1 &&
            beforeState == ShoppingLifecycleState.needed &&
            afterState == ShoppingLifecycleState.bought &&
            item != null &&
            item!.isBought,
        ShoppingLifecycleOperation.markNeeded => expectedRevision >= 1 &&
            beforeState == ShoppingLifecycleState.bought &&
            afterState == ShoppingLifecycleState.needed &&
            item != null &&
            !item!.isBought,
        ShoppingLifecycleOperation.remove => expectedRevision >= 1 &&
            beforeState != null &&
            beforeState != ShoppingLifecycleState.removed &&
            afterState == ShoppingLifecycleState.removed &&
            item == null,
      };

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'operation': operation.name,
        'itemId': itemId,
        'expectedRevision': expectedRevision,
        'nextRevision': nextRevision,
        'clearGeneration': clearGeneration,
        'beforeState': beforeState?.name,
        'afterState': afterState.name,
        if (item != null) 'item': item!.toJson(),
      };
}
