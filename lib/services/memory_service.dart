import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'auth_service.dart';

class MemoryService {
  static final FirebaseFirestore firestore = FirebaseFirestore.instance;

  static String normalizeMemoryText(String text) {
    return text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  static CollectionReference<Map<String, dynamic>>? _memoriesRef() {
    final uid = AuthService.currentUserId;

    if (uid == null || uid.isEmpty) {
      return null;
    }

    return firestore.collection("users").doc(uid).collection("memories");
  }

  static Future<bool> memoryAlreadyExists(String text) async {
    final normalizedText = normalizeMemoryText(text);
    if (normalizedText.isEmpty) return true;

    final ref = _memoriesRef();

    if (ref == null) {
      return true;
    }

    try {
      final indexedSnapshot = await ref
          .where("normalizedText", isEqualTo: normalizedText)
          .limit(1)
          .get();

      if (indexedSnapshot.docs.isNotEmpty) return true;

      final legacySnapshot = await ref.get();

      for (final doc in legacySnapshot.docs) {
        final existingText = doc.data()["text"]?.toString() ?? "";
        if (normalizeMemoryText(existingText) == normalizedText) {
          return true;
        }
      }
    } catch (error, stackTrace) {
      debugPrint("Memory duplicate check failed: $error");
      debugPrint("$stackTrace");
      return true;
    }

    return false;
  }

  static Future<void> saveMemory({
    required String text,
    required String category,
    int importance = 0,
  }) async {
    final cleanText = text.trim();
    final normalizedText = normalizeMemoryText(cleanText);

    if (cleanText.isEmpty || normalizedText.isEmpty) return;

    final ref = _memoriesRef();

    if (ref == null) {
      return;
    }

    final exists = await memoryAlreadyExists(cleanText);
    if (exists) return;

    final now = Timestamp.now();

    try {
      await ref.add({
        "text": cleanText,
        "normalizedText": normalizedText,
        "category": category.trim().isEmpty ? "personal" : category.trim(),
        "importance": importance,
        "createdAt": now,
        "updatedAt": now,
        "source": "chat",
      });
    } catch (error, stackTrace) {
      debugPrint("Memory save failed: $error");
      debugPrint("$stackTrace");
    }
  }

  static Future<List<Map<String, dynamic>>> getMemories() async {
    final ref = _memoriesRef();

    if (ref == null) {
      return [];
    }

    try {
      final snapshot = await ref.orderBy("createdAt", descending: true).get();

      return snapshot.docs.map((doc) {
        final data = doc.data();

        return {
          ...data,
          "id": doc.id,
        };
      }).toList();
    } catch (error, stackTrace) {
      debugPrint("Memory load failed: $error");
      debugPrint("$stackTrace");
      return [];
    }
  }
}
