import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/identity/entity_identity.dart';
import '../models/task_model.dart';
import 'auth_service.dart';

class CloudTaskService {
  CloudTaskService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>>? get _tasksRef {
    final uid = AuthService.currentUserId;

    if (uid == null || uid.isEmpty) {
      return null;
    }

    return _firestore.collection("users").doc(uid).collection("tasks");
  }

  static String documentIdForTask(TaskModel task) {
    if (EntityIdentity.isValid(task.id)) return task.id!;

    final raw = [
      task.createdAt.toIso8601String(),
      task.title,
      task.category,
    ].join("|");

    return base64Url.encode(utf8.encode(raw)).replaceAll("=", "");
  }

  static Future<void> saveTasks(List<TaskModel> tasks) async {
    final ref = _tasksRef;

    if (ref == null) {
      return;
    }

    final existing = await ref.get();
    final batch = _firestore.batch();

    for (final doc in existing.docs) {
      batch.delete(doc.reference);
    }

    for (final task in tasks) {
      final data = firestoreDataForTask(task)
        ..addAll({
          "schemaVersion": 1,
          "updatedAt": FieldValue.serverTimestamp(),
        });

      batch.set(ref.doc(documentIdForTask(task)), data);
    }

    await batch.commit();
  }

  static Future<List<TaskModel>> getTasks() async {
    final ref = _tasksRef;

    if (ref == null) {
      return [];
    }

    final snapshot = await ref.orderBy("createdAt", descending: true).get();

    return snapshot.docs
        .map(
          (doc) => taskFromDocument(
            documentId: doc.id,
            data: doc.data(),
          ),
        )
        .toList();
  }

  static TaskModel taskFromDocument({
    required String documentId,
    required Map<String, dynamic> data,
  }) {
    return TaskModel.fromJson({...data, "id": documentId});
  }

  static Map<String, dynamic> firestoreDataForTask(TaskModel task) {
    return Map<String, dynamic>.from(task.toJson())..remove("id");
  }

  static Future<void> clearTasks() async {
    final ref = _tasksRef;

    if (ref == null) {
      return;
    }

    final existing = await ref.get();
    final batch = _firestore.batch();

    for (final doc in existing.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();
  }
}
