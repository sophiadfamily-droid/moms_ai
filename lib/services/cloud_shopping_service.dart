import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/identity/entity_identity.dart';
import '../models/revisioned_domain_models.dart';
import '../models/revisioned_sync_protocol.dart';
import '../models/shopping_item_model.dart';
import 'auth_service.dart';

class CloudShoppingService {
  CloudShoppingService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>>? get _shoppingRef {
    final uid = AuthService.currentUserId;

    if (uid == null || uid.isEmpty) {
      return null;
    }

    return _firestore.collection("users").doc(uid).collection("shopping_items");
  }

  static String documentIdForShoppingItem(ShoppingItemModel item) {
    if (EntityIdentity.isValid(item.id)) return item.id!;

    final raw = [
      item.createdAt.toIso8601String(),
      item.title,
      item.category,
    ].join("|");

    return base64Url.encode(utf8.encode(raw)).replaceAll("=", "");
  }

  static Future<RevisionedCloudWriteResult<RevisionedShoppingItem>>
      createRevisioned({
    required String accountScopeId,
    required ShoppingItemModel item,
    required String mutationId,
  }) async {
    final ref = _shoppingRef;
    if (ref == null || accountScopeId != AuthService.currentUserId) {
      return const RevisionedCloudWriteResult(
        RevisionedCloudWriteStatus.accountMismatch,
      );
    }
    if (!EntityIdentity.isValid(item.id) || mutationId.trim().isEmpty) {
      throw const FormatException('shopping_revisioned_create_invalid');
    }
    final document = ref.doc(item.id);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(document);
      if (snapshot.exists) {
        final remote = revisionedShoppingFromDocument(
          documentId: document.id,
          data: snapshot.data()!,
        );
        if (remote.lastMutationId == mutationId) {
          return RevisionedCloudWriteResult(
            _sameItem(remote.item, item)
                ? RevisionedCloudWriteStatus.idempotent
                : RevisionedCloudWriteStatus.mutationConflict,
            value: remote,
          );
        }
        return RevisionedCloudWriteResult(
          RevisionedCloudWriteStatus.revisionConflict,
          value: remote,
        );
      }
      final now = DateTime.now().toUtc();
      final created = RevisionedShoppingItem(
        accountScopeId: accountScopeId,
        entityId: item.id!,
        item: item,
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

  static Future<RevisionedCloudWriteResult<RevisionedShoppingItem>>
      updateRevisioned({
    required String accountScopeId,
    required ShoppingItemModel item,
    required int expectedRevision,
    required String mutationId,
    bool tombstone = false,
    int clearGeneration = 0,
  }) async {
    final ref = _shoppingRef;
    if (ref == null || accountScopeId != AuthService.currentUserId) {
      return const RevisionedCloudWriteResult(
        RevisionedCloudWriteStatus.accountMismatch,
      );
    }
    if (!EntityIdentity.isValid(item.id) ||
        expectedRevision < 1 ||
        mutationId.trim().isEmpty ||
        clearGeneration < 0) {
      throw const FormatException('shopping_revisioned_update_invalid');
    }
    final document = ref.doc(item.id);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(document);
      if (!snapshot.exists) {
        return const RevisionedCloudWriteResult(
          RevisionedCloudWriteStatus.notFound,
        );
      }
      final remote = revisionedShoppingFromDocument(
        documentId: document.id,
        data: snapshot.data()!,
      );
      if (remote.lastMutationId == mutationId) {
        return RevisionedCloudWriteResult(
          _sameItem(remote.item, item) &&
                  remote.isTombstone == tombstone &&
                  remote.clearGeneration == clearGeneration
              ? RevisionedCloudWriteStatus.idempotent
              : RevisionedCloudWriteStatus.mutationConflict,
          value: remote,
        );
      }
      if (remote.revision != expectedRevision ||
          remote.isTombstone ||
          clearGeneration < remote.clearGeneration) {
        return RevisionedCloudWriteResult(
          RevisionedCloudWriteStatus.revisionConflict,
          value: remote,
        );
      }
      final updated = RevisionedShoppingItem(
        accountScopeId: remote.accountScopeId,
        entityId: remote.entityId,
        item: item,
        revision: expectedRevision + 1,
        createdAt: remote.createdAt,
        updatedAt: DateTime.now().toUtc(),
        lastMutationId: mutationId,
        isTombstone: tombstone,
        clearGeneration: clearGeneration,
      );
      transaction.update(document, _firestoreData(updated, create: false));
      return RevisionedCloudWriteResult(
        RevisionedCloudWriteStatus.success,
        value: updated,
      );
    });
  }

  static Future<List<RevisionedShoppingItem>> getRevisioned({
    int limit = 100,
  }) async {
    final ref = _shoppingRef;
    if (ref == null) return const [];
    if (limit < 1 || limit > 200) {
      throw const FormatException('shopping_page_limit_invalid');
    }
    final snapshot =
        await ref.orderBy('updatedAt', descending: true).limit(limit).get();
    return snapshot.docs
        .map(
          (doc) => revisionedShoppingFromDocument(
            documentId: doc.id,
            data: doc.data(),
          ),
        )
        .toList(growable: false);
  }

  static RevisionedShoppingItem revisionedShoppingFromDocument({
    required String documentId,
    required Map<String, dynamic> data,
  }) {
    if (data['revision'] == null) {
      final legacy =
          shoppingItemFromDocument(documentId: documentId, data: data);
      final created = legacy.createdAt.toUtc();
      return RevisionedShoppingItem(
        accountScopeId: AuthService.currentUserId ?? 'legacy-local',
        entityId: documentId,
        item: legacy,
        revision: 1,
        createdAt: created,
        updatedAt: _date(data['updatedAt']) ?? created,
        lastMutationId: 'legacy:$documentId',
        legacyProvenance: 'legacyCloud',
      );
    }
    final payload = Map<String, dynamic>.from(data['payload'] as Map);
    payload['id'] = documentId;
    return RevisionedShoppingItem(
      schemaVersion: data['schemaVersion'] as int? ?? -1,
      accountScopeId: data['accountScopeId'] as String? ?? '',
      entityId: data['entityId'] as String? ?? '',
      item: ShoppingItemModel.fromJson(payload),
      revision: data['revision'] as int? ?? -1,
      createdAt: _date(data['createdAt'])!,
      updatedAt: _date(data['updatedAt'])!,
      lastMutationId: data['lastMutationId'] as String? ?? '',
      isTombstone: data['isTombstone'] as bool? ?? false,
      clearGeneration: data['clearGeneration'] as int? ?? 0,
    );
  }

  static Map<String, dynamic> _firestoreData(
    RevisionedShoppingItem value, {
    required bool create,
  }) =>
      {
        'schemaVersion': value.schemaVersion,
        'accountScopeId': value.accountScopeId,
        'entityId': value.entityId,
        'payload': firestoreDataForShoppingItem(value.item),
        'revision': value.revision,
        'createdAt': create ? FieldValue.serverTimestamp() : value.createdAt,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastMutationId': value.lastMutationId,
        'syncStatus': RevisionedSyncStatus.synced.name,
        'isTombstone': value.isTombstone,
        'clearGeneration': value.clearGeneration,
      };

  static bool _sameItem(
    ShoppingItemModel first,
    ShoppingItemModel second,
  ) =>
      jsonEncode(first.toJson()) == jsonEncode(second.toJson());

  static DateTime? _date(Object? value) => switch (value) {
        Timestamp() => value.toDate().toUtc(),
        String() => DateTime.tryParse(value)?.toUtc(),
        _ => null,
      };

  @Deprecated('Use revisioned mutations through ShoppingService.')
  static Future<void> saveItems(List<ShoppingItemModel> items) async {
    throw const FormatException('shopping_full_rewrite_unsupported');
  }

  static Future<List<ShoppingItemModel>> getItems() async {
    final ref = _shoppingRef;

    if (ref == null) {
      return [];
    }

    final snapshot = await ref.orderBy("createdAt", descending: true).get();

    return snapshot.docs
        .where((doc) => doc.data()['isTombstone'] != true)
        .map(
          (doc) => doc.data()['payload'] is Map
              ? revisionedShoppingFromDocument(
                  documentId: doc.id,
                  data: doc.data(),
                ).item
              : shoppingItemFromDocument(
                  documentId: doc.id,
                  data: doc.data(),
                ),
        )
        .toList();
  }

  static ShoppingItemModel shoppingItemFromDocument({
    required String documentId,
    required Map<String, dynamic> data,
  }) {
    return ShoppingItemModel.fromJson({...data, "id": documentId});
  }

  static Map<String, dynamic> firestoreDataForShoppingItem(
    ShoppingItemModel item,
  ) {
    return Map<String, dynamic>.from(item.toJson())..remove("id");
  }
}
