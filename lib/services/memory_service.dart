import 'package:cloud_firestore/cloud_firestore.dart';

import 'auth_service.dart';

class MemoryService {
  static final FirebaseFirestore firestore = FirebaseFirestore.instance;

  static String normalizeMemoryText(String text) {
    return text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  static Future<bool> memoryAlreadyExists(String text) async {
    final normalizedText = normalizeMemoryText(text);

    final snapshot = await firestore
        .collection("users")
        .doc(AuthService.requireUserId())
        .collection("memories")
        .get();

    for (final doc in snapshot.docs) {
      final existingText = doc.data()["text"]?.toString() ?? "";
      if (normalizeMemoryText(existingText) == normalizedText) {
        return true;
      }
    }

    return false;
  }

  static Future<void> saveMemory({
    required String text,
    required String category,
    int importance = 0,
  }) async {
    final cleanText = text.trim();

    if (cleanText.isEmpty) return;

    final exists = await memoryAlreadyExists(cleanText);
    if (exists) return;

    await firestore
        .collection("users")
        .doc(AuthService.requireUserId())
        .collection("memories")
        .add({
      "text": cleanText,
      "category": category,
      "importance": importance,
      "createdAt": Timestamp.now(),
    });
  }

  static Future<List<Map<String, dynamic>>> getMemories() async {
    final snapshot = await firestore
        .collection("users")
        .doc(AuthService.requireUserId())
        .collection("memories")
        .get();

    return snapshot.docs.map((doc) => doc.data()).toList();
  }
}
