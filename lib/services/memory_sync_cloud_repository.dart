import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/memory_policy.dart';
import '../models/memory_sync.dart';

abstract interface class MemorySyncCloudRepository {
  Future<RevisionedMemoryPolicy?> readPolicy(String scope);
  Future<MemoryCloudWriteResult> createPolicy({
    required RevisionedMemoryPolicy policy,
  });
  Future<MemoryCloudWriteResult> updatePolicy({
    required RevisionedMemoryPolicy policy,
    required int expectedRevision,
  });
  Future<RevisionedMemory?> readMemory(String scope, String memoryId);
  Future<List<RevisionedMemory>> readMemoryPage(
    String scope, {
    int limit,
    String? afterMemoryId,
  });
  Future<MemoryCloudWriteResult> createMemory(RevisionedMemory memory);
  Future<MemoryCloudWriteResult> updateMemory({
    required RevisionedMemory memory,
    required int expectedRevision,
  });
}

final class FirestoreMemorySyncRepository implements MemorySyncCloudRepository {
  FirestoreMemorySyncRepository({
    required FirebaseFirestore firestore,
    required String? Function() currentUid,
  })  : _firestore = firestore,
        _currentUid = currentUid;

  static const policyDocument = 'memoryPolicy';
  static const maxPageSize = 100;
  static const maxDocumentBytes = 300000;

  final FirebaseFirestore _firestore;
  final String? Function() _currentUid;

  @override
  Future<RevisionedMemoryPolicy?> readPolicy(String scope) async {
    try {
      final snapshot = await _policyRef(scope).get();
      return snapshot.exists ? _decodePolicy(snapshot.data(), scope) : null;
    } on MemorySyncException {
      rethrow;
    } on FirebaseException catch (error) {
      throw MemorySyncException(_firebaseCode(error));
    }
  }

  @override
  Future<MemoryCloudWriteResult> createPolicy({
    required RevisionedMemoryPolicy policy,
  }) async {
    if (policy.policyRevision != 1) {
      return const MemoryCloudWriteResult(MemoryCloudWriteStatus.invalid);
    }
    try {
      final ref = _policyRef(policy.policy.accountScopeId);
      return await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);
        if (snapshot.exists) {
          final current = _decodePolicy(
            snapshot.data(),
            policy.policy.accountScopeId,
          );
          return current.lastMutationId == policy.lastMutationId
              ? MemoryCloudWriteResult(
                  MemoryCloudWriteStatus.idempotentSuccess,
                  policy: current,
                )
              : const MemoryCloudWriteResult(
                  MemoryCloudWriteStatus.revisionConflict,
                );
        }
        transaction.set(ref, _policyWrite(policy, create: true));
        return MemoryCloudWriteResult(
          MemoryCloudWriteStatus.success,
          policy: policy,
        );
      });
    } on Object catch (error) {
      return _writeFailure(error);
    }
  }

  @override
  Future<MemoryCloudWriteResult> updatePolicy({
    required RevisionedMemoryPolicy policy,
    required int expectedRevision,
  }) async {
    if (expectedRevision < 1 || policy.policyRevision != expectedRevision + 1) {
      return const MemoryCloudWriteResult(MemoryCloudWriteStatus.invalid);
    }
    try {
      final ref = _policyRef(policy.policy.accountScopeId);
      return await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);
        if (!snapshot.exists) {
          return const MemoryCloudWriteResult(
            MemoryCloudWriteStatus.notFound,
          );
        }
        final current =
            _decodePolicy(snapshot.data(), policy.policy.accountScopeId);
        if (current.lastMutationId == policy.lastMutationId) {
          return _samePolicy(current, policy)
              ? MemoryCloudWriteResult(
                  MemoryCloudWriteStatus.idempotentSuccess,
                  policy: current,
                )
              : const MemoryCloudWriteResult(
                  MemoryCloudWriteStatus.mutationMismatch,
                );
        }
        if (current.policyRevision != expectedRevision) {
          return const MemoryCloudWriteResult(
            MemoryCloudWriteStatus.revisionConflict,
          );
        }
        transaction.set(ref, _policyWrite(policy, create: false));
        return MemoryCloudWriteResult(
          MemoryCloudWriteStatus.success,
          policy: policy,
        );
      });
    } on Object catch (error) {
      return _writeFailure(error);
    }
  }

  @override
  Future<RevisionedMemory?> readMemory(
    String scope,
    String memoryId,
  ) async {
    try {
      final snapshot = await _memoryRef(scope, memoryId).get();
      return snapshot.exists
          ? RevisionedMemory.fromJson(
              Map<String, Object?>.from(snapshot.data()!),
              expectedScope: scope,
              expectedId: memoryId,
            )
          : null;
    } on MemorySyncException {
      rethrow;
    } on FirebaseException catch (error) {
      throw MemorySyncException(_firebaseCode(error));
    }
  }

  @override
  Future<List<RevisionedMemory>> readMemoryPage(
    String scope, {
    int limit = 50,
    String? afterMemoryId,
  }) async {
    if (limit < 1 || limit > maxPageSize) {
      throw const MemorySyncException('invalid_memory_page_limit');
    }
    _assertScope(scope);
    Query<Map<String, dynamic>> query = _firestore
        .collection('users')
        .doc(scope)
        .collection('memories')
        .orderBy(FieldPath.documentId)
        .limit(limit);
    if (afterMemoryId != null) query = query.startAfter([afterMemoryId]);
    final snapshot = await query.get();
    return snapshot.docs
        .where((document) => document.data()['schemaVersion'] == 1)
        .map(
          (document) => RevisionedMemory.fromJson(
            Map<String, Object?>.from(document.data()),
            expectedScope: scope,
            expectedId: document.id,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<MemoryCloudWriteResult> createMemory(
    RevisionedMemory memory,
  ) async {
    if (memory.memoryRevision != 1) {
      return const MemoryCloudWriteResult(MemoryCloudWriteStatus.invalid);
    }
    return _writeMemory(memory, expectedRevision: 0, create: true);
  }

  @override
  Future<MemoryCloudWriteResult> updateMemory({
    required RevisionedMemory memory,
    required int expectedRevision,
  }) {
    if (expectedRevision < 1 || memory.memoryRevision != expectedRevision + 1) {
      return Future.value(
        const MemoryCloudWriteResult(MemoryCloudWriteStatus.invalid),
      );
    }
    return _writeMemory(
      memory,
      expectedRevision: expectedRevision,
      create: false,
    );
  }

  Future<MemoryCloudWriteResult> _writeMemory(
    RevisionedMemory memory, {
    required int expectedRevision,
    required bool create,
  }) async {
    try {
      memory.validate();
      _assertSize(memory.toJson());
      final ref = _memoryRef(memory.accountScopeId, memory.memoryId);
      return await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);
        if (create && snapshot.exists) {
          final current = RevisionedMemory.fromJson(
            Map<String, Object?>.from(snapshot.data()!),
            expectedScope: memory.accountScopeId,
            expectedId: memory.memoryId,
          );
          if (current.lastMutationId == memory.lastMutationId) {
            return _sameMemory(current, memory)
                ? MemoryCloudWriteResult(
                    MemoryCloudWriteStatus.idempotentSuccess,
                    memory: current,
                  )
                : const MemoryCloudWriteResult(
                    MemoryCloudWriteStatus.mutationMismatch,
                  );
          }
          return const MemoryCloudWriteResult(
            MemoryCloudWriteStatus.revisionConflict,
          );
        }
        if (!create && !snapshot.exists) {
          return const MemoryCloudWriteResult(
            MemoryCloudWriteStatus.notFound,
          );
        }
        if (!create) {
          final current = RevisionedMemory.fromJson(
            Map<String, Object?>.from(snapshot.data()!),
            expectedScope: memory.accountScopeId,
            expectedId: memory.memoryId,
          );
          if (current.lastMutationId == memory.lastMutationId) {
            return _sameMemory(current, memory)
                ? MemoryCloudWriteResult(
                    MemoryCloudWriteStatus.idempotentSuccess,
                    memory: current,
                  )
                : const MemoryCloudWriteResult(
                    MemoryCloudWriteStatus.mutationMismatch,
                  );
          }
          if (current.memoryRevision != expectedRevision ||
              current.createdAt != memory.createdAt) {
            return const MemoryCloudWriteResult(
              MemoryCloudWriteStatus.revisionConflict,
            );
          }
        }
        transaction.set(ref, {
          ...memory.toJson(),
          'createdAt':
              create ? FieldValue.serverTimestamp() : memory.createdAt.toUtc(),
          'updatedAt': FieldValue.serverTimestamp(),
          if (memory.validFrom != null) 'validFrom': memory.validFrom!.toUtc(),
          if (memory.validUntil != null)
            'validUntil': memory.validUntil!.toUtc(),
          if (memory.expiresAt != null) 'expiresAt': memory.expiresAt!.toUtc(),
        });
        return MemoryCloudWriteResult(
          MemoryCloudWriteStatus.success,
          memory: memory,
        );
      });
    } on Object catch (error) {
      return _writeFailure(error);
    }
  }

  DocumentReference<Map<String, dynamic>> _policyRef(String scope) {
    _assertScope(scope);
    return _firestore
        .collection('users')
        .doc(scope)
        .collection('private')
        .doc(policyDocument);
  }

  DocumentReference<Map<String, dynamic>> _memoryRef(
    String scope,
    String id,
  ) {
    _assertScope(scope);
    if (id.trim().isEmpty) {
      throw const MemorySyncException('invalid_memory_id');
    }
    return _firestore.collection('users').doc(scope).collection('memories').doc(
          id,
        );
  }

  void _assertScope(String scope) {
    final uid = _currentUid();
    if (uid == null || uid.isEmpty) {
      throw const MemorySyncException('memory_cloud_unauthenticated');
    }
    if (uid != scope) {
      throw const MemorySyncException('memory_account_mismatch');
    }
  }

  void _assertSize(Map<String, Object?> json) {
    if (utf8.encode(jsonEncode(json)).length > maxDocumentBytes) {
      throw const MemorySyncException('memory_document_too_large');
    }
  }

  Map<String, Object?> _policyWrite(
    RevisionedMemoryPolicy value, {
    required bool create,
  }) {
    final result = <String, Object?>{
      ...value.toJson(),
      'changedAt': value.policy.changedAt.toUtc(),
      'createdAt':
          create ? FieldValue.serverTimestamp() : value.createdAt.toUtc(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (value.explicitHealthConsentAt == null) {
      result.remove('explicitHealthConsentAt');
    } else {
      result['explicitHealthConsentAt'] =
          value.explicitHealthConsentAt!.toUtc();
    }
    return result;
  }

  RevisionedMemoryPolicy _decodePolicy(
    Map<String, dynamic>? raw,
    String scope,
  ) {
    if (raw == null) {
      throw const MemorySyncException('corrupted_memory_policy');
    }
    final policyJson = Map<String, Object?>.from(raw)
      ..['changedAt'] = _date(raw['changedAt']).toIso8601String()
      ..['explicitHealthConsentAt'] = raw['explicitHealthConsentAt'] == null
          ? null
          : _date(raw['explicitHealthConsentAt']).toIso8601String();
    final policy = MemoryPolicy.fromJson(
      policyJson,
      expectedAccountScopeId: scope,
    );
    return RevisionedMemoryPolicy(
      policy: policy,
      policyRevision: raw['policyRevision'] as int,
      createdAt: _date(raw['createdAt']),
      updatedAt: _date(raw['updatedAt']),
      explicitHealthConsentAt: raw['explicitHealthConsentAt'] == null
          ? null
          : _date(raw['explicitHealthConsentAt']),
      lastMutationId: raw['lastMutationId'].toString(),
    );
  }

  DateTime _date(Object? value) {
    if (value is Timestamp) return value.toDate().toUtc();
    if (value is DateTime) return value.toUtc();
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) {
      throw const MemorySyncException('corrupted_memory_date');
    }
    return parsed.toUtc();
  }

  bool _sameMemory(RevisionedMemory left, RevisionedMemory right) {
    final l = left.toJson()..remove('updatedAt');
    final r = right.toJson()..remove('updatedAt');
    return jsonEncode(l) == jsonEncode(r);
  }

  bool _samePolicy(
    RevisionedMemoryPolicy left,
    RevisionedMemoryPolicy right,
  ) {
    final l = left.toJson()..remove('updatedAt');
    final r = right.toJson()..remove('updatedAt');
    return jsonEncode(l) == jsonEncode(r);
  }

  MemoryCloudWriteResult _writeFailure(Object error) {
    if (error is MemorySyncException) {
      return MemoryCloudWriteResult(
        error.code.contains('scope')
            ? MemoryCloudWriteStatus.scopeMismatch
            : MemoryCloudWriteStatus.invalid,
      );
    }
    if (error is FirebaseException) {
      return MemoryCloudWriteResult(
        switch (error.code) {
          'aborted' ||
          'failed-precondition' =>
            MemoryCloudWriteStatus.revisionConflict,
          'permission-denied' => MemoryCloudWriteStatus.scopeMismatch,
          _ => MemoryCloudWriteStatus.unavailable,
        },
      );
    }
    return const MemoryCloudWriteResult(MemoryCloudWriteStatus.unavailable);
  }

  String _firebaseCode(FirebaseException error) => switch (error.code) {
        'permission-denied' => 'memory_cloud_permission_denied',
        'unavailable' || 'deadline-exceeded' => 'memory_cloud_unavailable',
        _ => 'memory_cloud_failure',
      };
}
