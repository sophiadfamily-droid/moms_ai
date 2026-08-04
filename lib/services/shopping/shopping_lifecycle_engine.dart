import '../../core/identity/entity_identity.dart';
import '../../models/shopping/shopping_lifecycle_models.dart';
import '../../models/shopping_item_model.dart';

/// V1-SH.1 validates one Shopping item transition without side effects.
final class ShoppingLifecycleEngine {
  const ShoppingLifecycleEngine();

  ShoppingLifecycleTransition transition(ShoppingLifecycleRequest request) =>
      switch (request.operation) {
        ShoppingLifecycleOperation.add => _add(request),
        ShoppingLifecycleOperation.update => _update(request),
        ShoppingLifecycleOperation.markBought => _markBought(request),
        ShoppingLifecycleOperation.markNeeded => _markNeeded(request),
        ShoppingLifecycleOperation.remove => _remove(request),
      };

  ShoppingLifecycleTransition _add(ShoppingLifecycleRequest request) {
    final proposed = request.proposed;
    if (request.current != null ||
        request.expectedRevision != 0 ||
        proposed == null ||
        proposed.isBought) {
      throw const ShoppingLifecycleException(
        'invalid_shopping_add_transition',
      );
    }
    _validateItem(proposed);
    return _result(
      request: request,
      item: proposed,
      before: null,
      after: ShoppingLifecycleState.needed,
    );
  }

  ShoppingLifecycleTransition _update(ShoppingLifecycleRequest request) {
    final current = _existing(request);
    final proposed = request.proposed;
    if (proposed == null ||
        proposed.id != current.id ||
        proposed.createdAt != current.createdAt ||
        proposed.isBought != current.isBought) {
      throw const ShoppingLifecycleException(
        'invalid_shopping_update_transition',
      );
    }
    _validateItem(proposed);
    return _result(
      request: request,
      item: proposed,
      before: _stateOf(current),
      after: _stateOf(proposed),
    );
  }

  ShoppingLifecycleTransition _markBought(ShoppingLifecycleRequest request) {
    final current = _existing(request);
    if (request.proposed != null || current.isBought) {
      throw const ShoppingLifecycleException(
        'invalid_shopping_mark_bought_transition',
      );
    }
    return _result(
      request: request,
      item: current.copyWith(isBought: true),
      before: ShoppingLifecycleState.needed,
      after: ShoppingLifecycleState.bought,
    );
  }

  ShoppingLifecycleTransition _markNeeded(ShoppingLifecycleRequest request) {
    final current = _existing(request);
    if (request.proposed != null || !current.isBought) {
      throw const ShoppingLifecycleException(
        'invalid_shopping_mark_needed_transition',
      );
    }
    return _result(
      request: request,
      item: current.copyWith(isBought: false),
      before: ShoppingLifecycleState.bought,
      after: ShoppingLifecycleState.needed,
    );
  }

  ShoppingLifecycleTransition _remove(ShoppingLifecycleRequest request) {
    final current = _existing(request);
    if (request.proposed != null) {
      throw const ShoppingLifecycleException(
        'invalid_shopping_remove_transition',
      );
    }
    return _result(
      request: request,
      item: null,
      before: _stateOf(current),
      after: ShoppingLifecycleState.removed,
    );
  }

  ShoppingItemModel _existing(ShoppingLifecycleRequest request) {
    final current = request.current;
    if (current == null || request.expectedRevision < 1) {
      throw const ShoppingLifecycleException(
        'shopping_current_state_required',
      );
    }
    _validateItem(current);
    return current;
  }

  void _validateItem(ShoppingItemModel item) {
    if (!EntityIdentity.isValid(item.id) ||
        item.title.trim().isEmpty ||
        item.title.length > 500 ||
        item.category.length > 100 ||
        item.notes.length > 4000 ||
        item.section.length > 100) {
      throw const ShoppingLifecycleException(
        'invalid_shopping_lifecycle_payload',
      );
    }
  }

  ShoppingLifecycleState _stateOf(ShoppingItemModel item) => item.isBought
      ? ShoppingLifecycleState.bought
      : ShoppingLifecycleState.needed;

  ShoppingLifecycleTransition _result({
    required ShoppingLifecycleRequest request,
    required ShoppingItemModel? item,
    required ShoppingLifecycleState? before,
    required ShoppingLifecycleState after,
  }) =>
      ShoppingLifecycleTransition(
        operation: request.operation,
        itemId: (item ?? request.current)!.id!,
        expectedRevision: request.expectedRevision,
        nextRevision: request.expectedRevision + 1,
        clearGeneration: request.clearGeneration,
        beforeState: before,
        afterState: after,
        item: item,
      );
}
