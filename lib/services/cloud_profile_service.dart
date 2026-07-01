import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_profile.dart';
import 'auth_service.dart';

class CloudProfileService {
  CloudProfileService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>>? get _profileRef {
    final uid = AuthService.currentUserId;

    if (uid == null || uid.isEmpty) {
      return null;
    }

    return _firestore
        .collection("users")
        .doc(uid)
        .collection("private")
        .doc("profile");
  }

  static Future<void> saveProfile(UserProfile profile) async {
    final ref = _profileRef;

    if (ref == null) {
      return;
    }

    final data = profile.toJson()
      ..addAll({
        "schemaVersion": 1,
        "updatedAt": FieldValue.serverTimestamp(),
      });

    await ref.set(data, SetOptions(merge: true));
  }

  static Future<UserProfile?> getProfile() async {
    final ref = _profileRef;

    if (ref == null) {
      return null;
    }

    final snapshot = await ref.get();

    if (!snapshot.exists) {
      return null;
    }

    final data = snapshot.data();

    if (data == null) {
      return null;
    }

    return UserProfile.fromJson(data);
  }
}
