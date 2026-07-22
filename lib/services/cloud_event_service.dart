import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/identity/entity_identity.dart';
import '../models/event_model.dart';
import '../models/event_sync_models.dart';
import 'auth_service.dart';
import 'event_mutation_result.dart';

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
    final existingById = {for (final doc in existing.docs) doc.id: doc};

    if (existing.docs.any(
      (doc) => !events.any((event) => documentIdForEvent(event) == doc.id),
    )) {
      throw const FormatException('event_deletion_precondition_required');
    }

    for (final event in events) {
      final documentId = documentIdForEvent(event);
      final currentDocument = existingById[documentId];
      if (currentDocument != null) {
        final current = eventFromDocument(
          documentId: currentDocument.id,
          data: currentDocument.data(),
        );
        if (_samePersistedEvent(current, event)) continue;
        throw const FormatException('event_mutation_revision_required');
      }
      final data = firestoreDataForEvent(event)
        ..addAll({
          "schemaVersion": 1,
          "updatedAt": FieldValue.serverTimestamp(),
        });

      batch.set(ref.doc(documentId), data);
    }

    await batch.commit();
  }

  static bool _samePersistedEvent(EventModel first, EventModel second) {
    return jsonEncode(firestoreDataForEvent(first)) ==
        jsonEncode(firestoreDataForEvent(second));
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

  static Future<EventModel?> getEventById(String eventId) async {
    final ref = _eventsRef;
    if (ref == null || !EntityIdentity.isValid(eventId)) return null;
    final snapshot = await ref.doc(eventId).get();
    if (!snapshot.exists) return null;
    return eventFromDocument(
      documentId: snapshot.id,
      data: snapshot.data()!,
    );
  }

  static Future<EventMutationResult?> createEvent(EventModel event) async {
    final ref = _eventsRef;
    if (ref == null) return null;
    if (event.eventRevision != 1) {
      return const EventMutationResult.invalid();
    }
    try {
      return await _firestore.runTransaction((transaction) async {
        final document = ref.doc(documentIdForEvent(event));
        final snapshot = await transaction.get(document);
        if (snapshot.exists) {
          final current = eventFromDocument(
            documentId: snapshot.id,
            data: snapshot.data()!,
          );
          return _samePersistedEvent(current, event)
              ? EventMutationResult.success(current)
              : const EventMutationResult.alreadyExists();
        }
        final data = firestoreDataForEvent(event)
          ..addAll({
            'schemaVersion': 1,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        transaction.set(document, data);
        return EventMutationResult.success(event);
      });
    } on FirebaseException {
      return const EventMutationResult.persistenceFailure();
    } on FormatException {
      return const EventMutationResult.invalid();
    }
  }

  static Future<EventMutationResult> executeSyncOperation(
    PendingEventSyncOperation operation,
  ) async {
    final currentAccountId = AuthService.currentUserId;
    if (currentAccountId == null || currentAccountId.isEmpty) {
      return const EventMutationResult.persistenceFailure();
    }
    if (operation.accountScopeId == null ||
        currentAccountId != operation.accountScopeId) {
      return const EventMutationResult.scopeMismatch();
    }
    final result = switch (operation.type) {
      EventSyncOperationType.create => createEvent(operation.event!),
      EventSyncOperationType.update => mutateEvent(
          existing: operation.event!.copyWith(
            eventRevision: operation.expectedEventRevision,
          ),
          proposed: operation.event!,
          expectedEventRevision: operation.expectedEventRevision!,
        ),
      EventSyncOperationType.delete => deleteEventById(
          eventId: operation.eventId,
          expectedEventRevision: operation.expectedEventRevision!,
        ),
    };
    return await result ?? const EventMutationResult.persistenceFailure();
  }

  /// Atomically applies one existing-event mutation when cloud persistence is
  /// active. A null result means there is no authenticated cloud boundary and
  /// the caller may use the documented local-only protocol.
  static Future<EventMutationResult?> mutateEvent({
    required EventModel existing,
    required EventModel proposed,
    required int expectedEventRevision,
  }) async {
    final ref = _eventsRef;
    if (ref == null) return null;
    if (expectedEventRevision < 0 ||
        proposed.eventRevision != expectedEventRevision + 1) {
      return const EventMutationResult.invalid();
    }
    final documentId = documentIdForEvent(existing);
    if (documentIdForEvent(proposed) != documentId) {
      return const EventMutationResult.invalid();
    }
    try {
      return await _firestore.runTransaction((transaction) async {
        final document = ref.doc(documentId);
        final snapshot = await transaction.get(document);
        if (!snapshot.exists) return const EventMutationResult.notFound();
        final current = eventFromDocument(
          documentId: snapshot.id,
          data: snapshot.data()!,
        );
        if (current.eventRevision != expectedEventRevision) {
          if (current.eventRevision == proposed.eventRevision &&
              _samePersistedEvent(current, proposed)) {
            return EventMutationResult.success(current);
          }
          return const EventMutationResult.revisionConflict();
        }
        final data = firestoreDataForEvent(proposed)
          ..addAll({
            'schemaVersion': 1,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        transaction.update(document, data);
        return EventMutationResult.success(proposed);
      });
    } on FirebaseException catch (error) {
      if (error.code == 'aborted' || error.code == 'failed-precondition') {
        return const EventMutationResult.revisionConflict();
      }
      return const EventMutationResult.persistenceFailure();
    } on FormatException {
      return const EventMutationResult.invalid();
    }
  }

  static Future<EventMutationResult?> deleteEvent({
    required EventModel existing,
    required int expectedEventRevision,
  }) async {
    final ref = _eventsRef;
    if (ref == null) return null;
    try {
      return await _firestore.runTransaction((transaction) async {
        final document = ref.doc(documentIdForEvent(existing));
        final snapshot = await transaction.get(document);
        if (!snapshot.exists) return const EventMutationResult.notFound();
        final current = eventFromDocument(
          documentId: snapshot.id,
          data: snapshot.data()!,
        );
        if (current.eventRevision != expectedEventRevision) {
          return const EventMutationResult.revisionConflict();
        }
        transaction.delete(document);
        return EventMutationResult.success(current);
      });
    } on FirebaseException catch (error) {
      if (error.code == 'aborted' || error.code == 'failed-precondition') {
        return const EventMutationResult.revisionConflict();
      }
      return const EventMutationResult.persistenceFailure();
    } on FormatException {
      return const EventMutationResult.invalid();
    }
  }

  static Future<EventMutationResult?> deleteEventById({
    required String eventId,
    required int expectedEventRevision,
  }) async {
    final ref = _eventsRef;
    if (ref == null) return null;
    try {
      return await _firestore.runTransaction((transaction) async {
        final document = ref.doc(eventId);
        final snapshot = await transaction.get(document);
        if (!snapshot.exists) return const EventMutationResult.notFound();
        final current = eventFromDocument(
          documentId: snapshot.id,
          data: snapshot.data()!,
        );
        if (current.eventRevision != expectedEventRevision) {
          return const EventMutationResult.revisionConflict();
        }
        transaction.delete(document);
        return EventMutationResult.success(current);
      });
    } on FirebaseException {
      return const EventMutationResult.persistenceFailure();
    } on FormatException {
      return const EventMutationResult.invalid();
    }
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
