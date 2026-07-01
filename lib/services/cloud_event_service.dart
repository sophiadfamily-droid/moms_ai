import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/event_model.dart';
import 'auth_service.dart';

class CloudEventService {
  CloudEventService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>>? get _eventsRef {
    final uid = AuthService.currentUserId;

    if (uid == null || uid.isEmpty) {
      return null;
    }

    return _firestore.collection("users").doc(uid).collection("events");
  }

  static String _eventId(EventModel event) {
    final raw = [
      event.createdAt.toIso8601String(),
      event.startDateTimeIso,
      event.title,
      event.parentRecurringId,
    ].join("|");

    return base64Url.encode(utf8.encode(raw)).replaceAll("=", "");
  }

  static Future<void> saveEvents(List<EventModel> events) async {
    final ref = _eventsRef;

    if (ref == null) {
      return;
    }

    final existing = await ref.get();
    final batch = _firestore.batch();

    for (final doc in existing.docs) {
      batch.delete(doc.reference);
    }

    for (final event in events) {
      final data = event.toJson()
        ..addAll({
          "schemaVersion": 1,
          "updatedAt": FieldValue.serverTimestamp(),
        });

      batch.set(ref.doc(_eventId(event)), data);
    }

    await batch.commit();
  }

  static Future<List<EventModel>> getEvents() async {
    final ref = _eventsRef;

    if (ref == null) {
      return [];
    }

    final snapshot = await ref.orderBy("startDateTimeIso").get();

    return snapshot.docs.map((doc) => EventModel.fromJson(doc.data())).toList();
  }
}
