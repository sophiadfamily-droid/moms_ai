import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/shopping_item_model.dart';
import 'cloud_shopping_service.dart';

class ShoppingService {
  static const String shoppingKey = "shopping_items";

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
      // Les courses restent disponibles hors ligne ou sans compte connecté.
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
      // Si Firestore est indisponible, on utilise les courses locales.
    }

    return localItems;
  }

  static Future<void> addItem(
    ShoppingItemModel item,
  ) async {
    final items = await getItems();

    items.add(item);

    await saveItems(items);
  }

  static Future<void> updateItems(
    List<ShoppingItemModel> items,
  ) async {
    await saveItems(items);
  }
}
