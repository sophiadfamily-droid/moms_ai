import 'package:cloud_firestore/cloud_firestore.dart';

import 'auth_service.dart';

class ChatService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<void> saveMessage({
    required String conversationId,
    required String role,
    required String text,
  }) async {
    if (text.trim().isEmpty) return;

    final userRef =
        _firestore.collection("users").doc(AuthService.requireUserId());

    final conversationRef =
        userRef.collection("conversations").doc(conversationId);

    await conversationRef.collection("messages").add({
      "role": role,
      "text": text,
      "createdAt": Timestamp.now(),
    });

    await conversationRef.set({
      "updatedAt": Timestamp.now(),
      "lastMessage": text,
    }, SetOptions(merge: true));
  }
}
