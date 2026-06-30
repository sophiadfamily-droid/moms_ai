import 'package:cloud_firestore/cloud_firestore.dart';

import 'auth_service.dart';

class MemoryService {
  static final FirebaseFirestore firestore = FirebaseFirestore.instance;

  static String normalizeMemoryText(String text) {
    return text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  static CollectionReference<Map<String, dynamic>> _memoriesRef() {
    return firestore
        .collection("users")
        .doc(AuthService.requireUserId())
        .collection("memories");
  }

  static Future<bool> memoryAlreadyExists(String text) async {
    final normalizedText = normalizeMemoryText(text);
    if (normalizedText.isEmpty) return true;

    final indexedSnapshot = await _memoriesRef()
        .where("normalizedText", isEqualTo: normalizedText)
        .limit(1)
        .get();

    if (indexedSnapshot.docs.isNotEmpty) return true;

    final legacySnapshot = await _memoriesRef().get();

    for (final doc in legacySnapshot.docs) {
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
    final normalizedText = normalizeMemoryText(cleanText);

    if (cleanText.isEmpty || normalizedText.isEmpty) return;

    final exists = await memoryAlreadyExists(cleanText);
    if (exists) return;

    final now = Timestamp.now();

    await _memoriesRef().add({
      "text": cleanText,
      "normalizedText": normalizedText,
      "category": category.trim().isEmpty ? "personal" : category.trim(),
      "importance": importance,
      "createdAt": now,
      "updatedAt": now,
      "source": "chat",
    });
  }

  static Future<List<Map<String, dynamic>>> getMemories() async {
    final snapshot =
        await _memoriesRef().orderBy("createdAt", descending: true).get();

    return snapshot.docs.map((doc) {
      final data = doc.data();

      return {
        ...data,
        "id": doc.id,
      };
    }).toList();
  }
}
