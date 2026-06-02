import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/shopping_item_model.dart';

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

    notifyUpdate();
  }

  static Future<List<ShoppingItemModel>> getItems() async {
    final prefs = await SharedPreferences.getInstance();

    final data = prefs.getStringList(shoppingKey);

    if (data == null) {
      return [];
    }

    return data
        .map(
          (item) => ShoppingItemModel.fromJson(
            jsonDecode(item),
          ),
        )
        .toList();
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
