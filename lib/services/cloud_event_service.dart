import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/identity/entity_identity.dart';
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

  static String documentIdForEvent(EventModel event) {
    if (EntityIdentity.isValid(event.id)) return event.id!;

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
      final data = firestoreDataForEvent(event)
        ..addAll({
          "schemaVersion": 1,
          "updatedAt": FieldValue.serverTimestamp(),
        });

      batch.set(ref.doc(documentIdForEvent(event)), data);
    }

    await batch.commit();
  }

  static Future<List<EventModel>> getEvents() async {
    final ref = _eventsRef;

    if (ref == null) {
      return [];
    }

    final snapshot = await ref.orderBy("startDateTimeIso").get();

    return snapshot.docs
        .map(
          (doc) => eventFromDocument(
            documentId: doc.id,
            data: doc.data(),
          ),
        )
        .toList();
  }

  static EventModel eventFromDocument({
    required String documentId,
    required Map<String, dynamic> data,
  }) {
    return EventModel.fromJson({...data, "id": documentId});
  }

  static Map<String, dynamic> firestoreDataForEvent(EventModel event) {
    return Map<String, dynamic>.from(event.toJson())..remove("id");
  }
}
