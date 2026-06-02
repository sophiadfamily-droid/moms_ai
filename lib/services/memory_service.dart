import 'package:cloud_firestore/cloud_firestore.dart';

class MemoryService {
  static final FirebaseFirestore firestore =
      FirebaseFirestore.instance;

  static Future<void> saveMemory({
    required String text,
    required String category,
  }) async {
    await firestore
        .collection("users")
        .doc("demo_user")
        .collection("memories")
        .add({
      "text": text,
      "category": category,
      "createdAt": Timestamp.now(),
    });
  }

  static Future<List<Map<String, dynamic>>> getMemories() async {
    final snapshot = await firestore
        .collection("users")
        .doc("demo_user")
        .collection("memories")
        .get();

    return snapshot.docs
        .map((doc) => doc.data())
        .toList();
  }
}
