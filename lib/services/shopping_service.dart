import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/identity/entity_id_generator.dart';
import '../core/identity/entity_identity.dart';
import '../core/identity/entity_matcher.dart';
import '../core/identity/uuid_v7_entity_id_generator.dart';
import '../models/shopping_item_model.dart';
import 'cloud_shopping_service.dart';
import 'app_diagnostics.dart';

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

  static void notifyUpdate() {
    shoppingVersion.value++;
  }

  static Future<void> saveItems(
    List<ShoppingItemModel> items,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    final encoded = items
        .map(
          (item) => jsonEncode(item.toJson()),
        )
        .toList();

    await prefs.setStringList(
      shoppingKey,
      encoded,
    );

    try {
      await CloudShoppingService.saveItems(items);
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

    final data = prefs.getStringList(shoppingKey);

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
      final cloudItems = await CloudShoppingService.getItems();

      if (cloudItems.isNotEmpty) {
        final encoded = cloudItems
            .map(
              (item) => jsonEncode(item.toJson()),
            )
            .toList();

        await prefs.setStringList(
          shoppingKey,
          encoded,
        );

        return cloudItems;
      }

      if (localItems.isNotEmpty) {
        await CloudShoppingService.saveItems(localItems);
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
}
