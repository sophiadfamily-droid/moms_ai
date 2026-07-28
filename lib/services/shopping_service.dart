import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/identity/entity_id_generator.dart';
import '../core/identity/entity_identity.dart';
import '../core/identity/entity_matcher.dart';
import '../core/identity/uuid_v7_entity_id_generator.dart';
import '../models/shopping_item_model.dart';
import '../models/revisioned_domain_models.dart';
import '../models/revisioned_sync_protocol.dart';
import 'auth_service.dart';
import 'app_diagnostics.dart';
import 'revisioned_cloud_repositories.dart';
import 'revisioned_domain_sync_service.dart';
import 'revisioned_action_ledger_observer.dart';

class ShoppingService {
  static const String shoppingKey = "shopping_items";

  static final EntityMatcher<ShoppingItemModel> _shoppingItemMatcher =
      EntityMatcher(
    idOf: (item) => item.id,
    legacyEquals: (first, second) {
      return first.title == second.title && first.createdAt == second.createdAt;
    },
  );

  static final ValueNotifier<int> shoppingVersion = ValueNotifier<int>(0);
  static final ShoppingRevisionSyncService _sync = ShoppingRevisionSyncService(
    cloud: const FirestoreRevisionedShoppingRepository(),
    currentAccountScope: () => AuthService.currentUserId,
  );

  static void notifyUpdate() {
    shoppingVersion.value++;
  }

  static Future<void> saveItems(
    List<ShoppingItemModel> items,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final scope = _currentAccountScope();

    final encoded = items
        .map(
          (item) => jsonEncode(item.toJson()),
        )
        .toList();

    if (scope == null) {
      await prefs.setStringList(
        shoppingKey,
        encoded,
      );
    }

    try {
      if (scope != null) await _reconcileRevisioned(scope, items);
    } catch (_) {
      AppDiagnostics.record(
        component: 'shopping_storage',
        step: 'cloud_sync',
        code: AppErrorCode.syncFailure,
      );
    }

    notifyUpdate();
  }

  static Future<List<ShoppingItemModel>> getItems() async {
    final prefs = await SharedPreferences.getInstance();
    final scope = _currentAccountScope();

    final data = scope == null ? prefs.getStringList(shoppingKey) : null;

    final localItems = data == null
        ? <ShoppingItemModel>[]
        : data
            .map(
              (item) => ShoppingItemModel.fromJson(
                jsonDecode(item),
              ),
            )
            .toList();

    try {
      final cloudValues = scope == null
          ? const <RevisionedShoppingItem>[]
          : await _sync.bootstrap(scope);
      final cloudItems = cloudValues
          .where((value) => !value.isTombstone)
          .map((value) => value.item)
          .toList(growable: false);

      if (scope != null) {
        return cloudItems;
      }
    } catch (_) {
      AppDiagnostics.record(
        component: 'shopping_storage',
        step: 'cloud_load',
        code: AppErrorCode.syncFailure,
      );
    }

    return localItems;
  }

  static Future<void> addItem(
    ShoppingItemModel item, {
    EntityIdGenerator idGenerator = const UuidV7EntityIdGenerator(),
  }) async {
    final items = await getItems();

    items.add(_withIdForCreation(item, idGenerator));

    await saveItems(items);
  }

  static ShoppingItemModel _withIdForCreation(
    ShoppingItemModel item,
    EntityIdGenerator idGenerator,
  ) {
    if (EntityIdentity.isValid(item.id)) return item;
    final generatedId = idGenerator.generate();
    return item.copyWith(id: generatedId);
  }

  static bool areSameShoppingItem(
    ShoppingItemModel first,
    ShoppingItemModel second,
  ) {
    return _shoppingItemMatcher.matches(first, second);
  }

  static Future<void> updateItems(
    List<ShoppingItemModel> items,
  ) async {
    await saveItems(items);
  }

  static Future<void> _reconcileRevisioned(
    String scope,
    List<ShoppingItemModel> proposed,
  ) async {
    final current = await _sync.bootstrap(scope);
    final currentById = {for (final value in current) value.entityId: value};
    final proposedById = {
      for (final item in proposed)
        if (EntityIdentity.isValid(item.id)) item.id!: item,
    };
    const mutationIds = UuidV7EntityIdGenerator();
    for (final entry in proposedById.entries) {
      final existing = currentById[entry.key];
      final mutation = ShoppingMutation(
        mutationId: mutationIds.generate(),
        targetId: entry.key,
        expectedRevision: existing?.revision ?? 0,
        createdAt: DateTime.now().toUtc(),
        attempt: 0,
        nextRetryAt: null,
        state: RevisionedMutationState.queued,
        type: existing == null
            ? ShoppingMutationType.addItem
            : ShoppingMutationType.updateItem,
        item: entry.value,
        clearGeneration: existing?.clearGeneration ?? 0,
      );
      if (existing == null ||
          !existing.isTombstone &&
              jsonEncode(existing.item.toJson()) !=
                  jsonEncode(entry.value.toJson())) {
        await RevisionedActionLedgerObserver.shopping(
          scope,
          mutation,
          () => _sync.apply(scope, mutation),
        );
      }
    }
    for (final existing in current.where(
      (value) =>
          !value.isTombstone && !proposedById.containsKey(value.entityId),
    )) {
      final mutation = ShoppingMutation(
        mutationId: mutationIds.generate(),
        targetId: existing.entityId,
        expectedRevision: existing.revision,
        createdAt: DateTime.now().toUtc(),
        attempt: 0,
        nextRetryAt: null,
        state: RevisionedMutationState.queued,
        type: ShoppingMutationType.removeItem,
        item: existing.item,
        clearGeneration: existing.clearGeneration,
      );
      await RevisionedActionLedgerObserver.shopping(
        scope,
        mutation,
        () => _sync.apply(scope, mutation),
      );
    }
  }

  static String? _currentAccountScope() {
    try {
      return AuthService.currentUserId;
    } on Object {
      return null;
    }
  }
}
