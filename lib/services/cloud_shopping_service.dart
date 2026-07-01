import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/shopping_item_model.dart';
import 'auth_service.dart';

class CloudShoppingService {
  CloudShoppingService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>>? get _shoppingRef {
    final uid = AuthService.currentUserId;

    if (uid == null || uid.isEmpty) {
      return null;
    }

    return _firestore.collection("users").doc(uid).collection("shopping_items");
  }

  static String _itemId(ShoppingItemModel item) {
    final raw = [
      item.createdAt.toIso8601String(),
      item.title,
      item.category,
    ].join("|");

    return base64Url.encode(utf8.encode(raw)).replaceAll("=", "");
  }

  static Future<void> saveItems(List<ShoppingItemModel> items) async {
    final ref = _shoppingRef;

    if (ref == null) {
      return;
    }

    final existing = await ref.get();
    final batch = _firestore.batch();

    for (final doc in existing.docs) {
      batch.delete(doc.reference);
    }

    for (final item in items) {
      final data = item.toJson()
        ..addAll({
          "schemaVersion": 1,
          "updatedAt": FieldValue.serverTimestamp(),
        });

      batch.set(ref.doc(_itemId(item)), data);
    }

    await batch.commit();
  }

  static Future<List<ShoppingItemModel>> getItems() async {
    final ref = _shoppingRef;

    if (ref == null) {
      return [];
    }

    final snapshot = await ref.orderBy("createdAt", descending: true).get();

    return snapshot.docs.map((doc) {
      return ShoppingItemModel.fromJson(doc.data());
    }).toList();
  }
}
