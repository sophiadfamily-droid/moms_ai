import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/identity/entity_identity.dart';
import '../models/revisioned_domain_models.dart';
import '../models/revisioned_sync_protocol.dart';
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

  static Future<RevisionedCloudWriteResult<RevisionedTask>> createRevisioned({
    required String accountScopeId,
    required TaskModel task,
    required String mutationId,
  }) async {
    final ref = _tasksRef;
    if (ref == null || accountScopeId != AuthService.currentUserId) {
      return const RevisionedCloudWriteResult(
        RevisionedCloudWriteStatus.accountMismatch,
      );
    }
    if (!EntityIdentity.isValid(task.id) || mutationId.trim().isEmpty) {
      throw const FormatException('task_revisioned_create_invalid');
    }
    final document = ref.doc(task.id);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(document);
      if (snapshot.exists) {
        final data = snapshot.data()!;
        if (data['lastMutationId'] == mutationId) {
          final remote = revisionedTaskFromDocument(
            documentId: document.id,
            data: data,
          );
          return RevisionedCloudWriteResult(
            _sameTask(remote.task, task)
                ? RevisionedCloudWriteStatus.idempotent
                : RevisionedCloudWriteStatus.mutationConflict,
            value: remote,
          );
        }
        return RevisionedCloudWriteResult(
          RevisionedCloudWriteStatus.revisionConflict,
          value: revisionedTaskFromDocument(
            documentId: document.id,
            data: data,
          ),
        );
      }
      final now = DateTime.now().toUtc();
      final created = RevisionedTask(
        accountScopeId: accountScopeId,
        entityId: task.id!,
        task: task,
        revision: 1,
        createdAt: now,
        updatedAt: now,
        lastMutationId: mutationId,
      );
      transaction.set(document, _firestoreData(created, create: true));
      return RevisionedCloudWriteResult(
        RevisionedCloudWriteStatus.success,
        value: created,
      );
    });
  }

  static Future<RevisionedCloudWriteResult<RevisionedTask>> updateRevisioned({
    required String accountScopeId,
    required TaskModel task,
    required int expectedRevision,
    required String mutationId,
    bool tombstone = false,
  }) async {
    final ref = _tasksRef;
    if (ref == null || accountScopeId != AuthService.currentUserId) {
      return const RevisionedCloudWriteResult(
        RevisionedCloudWriteStatus.accountMismatch,
      );
    }
    if (!EntityIdentity.isValid(task.id) ||
        expectedRevision < 1 ||
        mutationId.trim().isEmpty) {
      throw const FormatException('task_revisioned_update_invalid');
    }
    final document = ref.doc(task.id);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(document);
      if (!snapshot.exists) {
        return const RevisionedCloudWriteResult(
          RevisionedCloudWriteStatus.notFound,
        );
      }
      final remote = revisionedTaskFromDocument(
        documentId: document.id,
        data: snapshot.data()!,
      );
      if (remote.lastMutationId == mutationId) {
        return RevisionedCloudWriteResult(
          _sameTask(remote.task, task) && remote.isTombstone == tombstone
              ? RevisionedCloudWriteStatus.idempotent
              : RevisionedCloudWriteStatus.mutationConflict,
          value: remote,
        );
      }
      if (remote.revision != expectedRevision || remote.isTombstone) {
        return RevisionedCloudWriteResult(
          RevisionedCloudWriteStatus.revisionConflict,
          value: remote,
        );
      }
      final updated = remote.copyWith(
        task: task,
        revision: expectedRevision + 1,
        updatedAt: DateTime.now().toUtc(),
        lastMutationId: mutationId,
        isTombstone: tombstone,
      );
      transaction.update(document, _firestoreData(updated, create: false));
      return RevisionedCloudWriteResult(
        RevisionedCloudWriteStatus.success,
        value: updated,
      );
    });
  }

  static Future<List<RevisionedTask>> getRevisioned({
    int limit = 100,
  }) async {
    final ref = _tasksRef;
    if (ref == null) return const [];
    if (limit < 1 || limit > 200) {
      throw const FormatException('task_page_limit_invalid');
    }
    final snapshot =
        await ref.orderBy('updatedAt', descending: true).limit(limit).get();
    return snapshot.docs
        .map(
          (doc) => revisionedTaskFromDocument(
            documentId: doc.id,
            data: doc.data(),
          ),
        )
        .toList(growable: false);
  }

  static RevisionedTask revisionedTaskFromDocument({
    required String documentId,
    required Map<String, dynamic> data,
  }) {
    if (data['revision'] == null) {
      final legacy = taskFromDocument(documentId: documentId, data: data);
      final created = legacy.createdAt.toUtc();
      return RevisionedTask(
        accountScopeId: AuthService.currentUserId ?? 'legacy-local',
        entityId: documentId,
        task: legacy,
        revision: 1,
        createdAt: created,
        updatedAt: _date(data['updatedAt']) ?? created,
        lastMutationId: 'legacy:$documentId',
        legacyProvenance: 'legacyCloud',
      );
    }
    final payload = Map<String, dynamic>.from(data['payload'] as Map);
    payload['id'] = documentId;
    return RevisionedTask(
      schemaVersion: data['schemaVersion'] as int? ?? -1,
      accountScopeId: data['accountScopeId'] as String? ?? '',
      entityId: data['entityId'] as String? ?? '',
      task: TaskModel.fromJson(payload),
      revision: data['revision'] as int? ?? -1,
      createdAt: _date(data['createdAt'])!,
      updatedAt: _date(data['updatedAt'])!,
      lastMutationId: data['lastMutationId'] as String? ?? '',
      isTombstone: data['isTombstone'] as bool? ?? false,
    );
  }

  static Map<String, dynamic> _firestoreData(
    RevisionedTask value, {
    required bool create,
  }) =>
      {
        'schemaVersion': value.schemaVersion,
        'accountScopeId': value.accountScopeId,
        'entityId': value.entityId,
        'payload': firestoreDataForTask(value.task),
        'revision': value.revision,
        'createdAt': create ? FieldValue.serverTimestamp() : value.createdAt,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastMutationId': value.lastMutationId,
        'syncStatus': RevisionedSyncStatus.synced.name,
        'isTombstone': value.isTombstone,
      };

  static bool _sameTask(TaskModel first, TaskModel second) =>
      jsonEncode(first.toJson()) == jsonEncode(second.toJson());

  static DateTime? _date(Object? value) => switch (value) {
        Timestamp() => value.toDate().toUtc(),
        String() => DateTime.tryParse(value)?.toUtc(),
        _ => null,
      };

  @Deprecated('Use createRevisioned/updateRevisioned through TaskService.')
  static Future<void> saveTasks(List<TaskModel> tasks) async {
    throw const FormatException('task_full_rewrite_unsupported');
  }

  static Future<List<TaskModel>> getTasks() async {
    final ref = _tasksRef;

    if (ref == null) {
      return [];
    }

    final snapshot = await ref.orderBy("createdAt", descending: true).get();

    return snapshot.docs
        .where((doc) => doc.data()['isTombstone'] != true)
        .map(
          (doc) => doc.data()['payload'] is Map
              ? revisionedTaskFromDocument(
                  documentId: doc.id,
                  data: doc.data(),
                ).task
              : taskFromDocument(documentId: doc.id, data: doc.data()),
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

  @Deprecated('Use tombstone mutations through TaskService.')
  static Future<void> clearTasks() async {
    throw const FormatException('task_physical_clear_unsupported');
  }
}
