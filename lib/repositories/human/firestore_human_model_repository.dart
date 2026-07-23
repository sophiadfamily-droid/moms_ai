import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/human/human_model.dart';
import '../../models/human/human_model_persistence.dart';
import 'human_model_cloud_repository.dart';

final class FirestoreHumanModelRepository implements HumanModelCloudRepository {
  FirestoreHumanModelRepository({
    required FirebaseFirestore firestore,
    required String? Function() currentUid,
  })  : _firestore = firestore,
        _currentUid = currentUid;

  static const documentName = 'humanModel';
  static const migrationVersion = 1;
  static const maximumPayloadBytes = 700000;

  final FirebaseFirestore _firestore;
  final String? Function() _currentUid;

  @override
  Future<RevisionedHumanModel?> read(String accountScopeId) async {
    final reference = _reference(accountScopeId);
    try {
      final snapshot = await reference.get();
      if (!snapshot.exists) return null;
      return _decode(snapshot.data());
    } on HumanModelException {
      rethrow;
    } on FirebaseException catch (error) {
      throw HumanModelException(_firebaseCode(error));
    } on Object {
      throw const HumanModelException('human_cloud_read_failure');
    }
  }

  @override
  Future<HumanModelWriteResult> createIfAbsent({
    required HumanModel model,
    required String mutationId,
    required String creationSource,
  }) async {
    try {
      _validateWrite(model, mutationId);
      final reference = _reference(model.accountScopeId);
      return await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(reference);
        if (snapshot.exists) {
          final current = _decode(snapshot.data());
          if (current.lastMutationId == mutationId &&
              _sameModel(current.model, model)) {
            return HumanModelWriteResult.success(current);
          }
          return const HumanModelWriteResult.status(
            HumanModelWriteStatus.alreadyExists,
          );
        }
        transaction.set(reference, {
          'schemaVersion': model.schemaVersion,
          'modelRevision': 1,
          'accountScopeId': model.accountScopeId,
          'payload': model.toJson(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'lastMutationId': mutationId,
          'migrationVersion': migrationVersion,
          'migrationStatus': HumanModelMigrationStatus.complete.name,
          'creationSource': creationSource,
        });
        return HumanModelWriteResult.success(
          RevisionedHumanModel(
            model: model,
            modelRevision: 1,
            lastMutationId: mutationId,
            migrationVersion: migrationVersion,
            migrationStatus: HumanModelMigrationStatus.complete,
          ),
        );
      });
    } on HumanModelException catch (error) {
      return HumanModelWriteResult.status(_statusFor(error.code));
    } on FirebaseException catch (error) {
      return HumanModelWriteResult.status(_firebaseStatus(error));
    } on Object {
      return const HumanModelWriteResult.status(
        HumanModelWriteStatus.persistenceFailure,
      );
    }
  }

  @override
  Future<HumanModelWriteResult> update({
    required HumanModel model,
    required int expectedRevision,
    required String mutationId,
  }) async {
    if (expectedRevision < 1) {
      return const HumanModelWriteResult.status(
        HumanModelWriteStatus.invalidModel,
      );
    }
    try {
      _validateWrite(model, mutationId);
      final reference = _reference(model.accountScopeId);
      return await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(reference);
        if (!snapshot.exists) {
          return const HumanModelWriteResult.status(
            HumanModelWriteStatus.notFound,
          );
        }
        final current = _decode(snapshot.data());
        if (current.lastMutationId == mutationId) {
          return _sameModel(current.model, model)
              ? HumanModelWriteResult.success(current)
              : const HumanModelWriteResult.status(
                  HumanModelWriteStatus.invalidModel,
                );
        }
        if (current.modelRevision != expectedRevision) {
          return const HumanModelWriteResult.status(
            HumanModelWriteStatus.revisionConflict,
          );
        }
        transaction.update(reference, {
          'schemaVersion': model.schemaVersion,
          'modelRevision': expectedRevision + 1,
          'payload': model.toJson(),
          'updatedAt': FieldValue.serverTimestamp(),
          'lastMutationId': mutationId,
          'migrationVersion': migrationVersion,
          'migrationStatus': HumanModelMigrationStatus.complete.name,
          'creationSource': 'canonicalMutation',
        });
        return HumanModelWriteResult.success(
          RevisionedHumanModel(
            model: model,
            modelRevision: expectedRevision + 1,
            lastMutationId: mutationId,
            migrationVersion: migrationVersion,
            migrationStatus: HumanModelMigrationStatus.complete,
          ),
        );
      });
    } on HumanModelException catch (error) {
      return HumanModelWriteResult.status(_statusFor(error.code));
    } on FirebaseException catch (error) {
      return HumanModelWriteResult.status(_firebaseStatus(error));
    } on Object {
      return const HumanModelWriteResult.status(
        HumanModelWriteStatus.persistenceFailure,
      );
    }
  }

  DocumentReference<Map<String, dynamic>> _reference(String accountScopeId) {
    final uid = _currentUid();
    if (uid == null || uid.trim().isEmpty) {
      throw const HumanModelException('human_cloud_unauthenticated');
    }
    if (accountScopeId != uid) {
      throw const HumanModelException('human_model_scope_mismatch');
    }
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('private')
        .doc(documentName);
  }

  void _validateWrite(HumanModel model, String mutationId) {
    model.validate();
    _reference(model.accountScopeId);
    if (mutationId.trim().isEmpty || mutationId.length > 128) {
      throw const HumanModelException('invalid_human_mutation_id');
    }
    final bytes = utf8.encode(jsonEncode(model.toJson())).length;
    if (bytes > maximumPayloadBytes) {
      throw const HumanModelException('human_model_too_large');
    }
  }

  RevisionedHumanModel _decode(Map<String, dynamic>? raw) {
    if (raw == null) {
      throw const HumanModelException('invalid_human_cloud_document');
    }
    final schemaVersion = raw['schemaVersion'];
    final revision = raw['modelRevision'];
    final accountScopeId = raw['accountScopeId'];
    final mutationId = raw['lastMutationId'];
    final version = raw['migrationVersion'];
    final migrationStatus = raw['migrationStatus'];
    if (schemaVersion != HumanModel.currentSchemaVersion ||
        revision is! int ||
        revision < 1 ||
        accountScopeId is! String ||
        mutationId is! String ||
        mutationId.isEmpty ||
        version != migrationVersion ||
        migrationStatus != HumanModelMigrationStatus.complete.name) {
      throw const HumanModelException('invalid_human_cloud_document');
    }
    final uid = _currentUid();
    if (uid == null || uid != accountScopeId) {
      throw const HumanModelException('human_model_scope_mismatch');
    }
    final model = HumanModel.fromJson(raw['payload']);
    if (model.accountScopeId != accountScopeId ||
        model.schemaVersion != schemaVersion) {
      throw const HumanModelException('human_model_scope_mismatch');
    }
    return RevisionedHumanModel(
      model: model,
      modelRevision: revision,
      lastMutationId: mutationId,
      migrationVersion: version as int,
      migrationStatus: HumanModelMigrationStatus.complete,
    );
  }

  bool _sameModel(HumanModel left, HumanModel right) =>
      jsonEncode(left.toJson()) == jsonEncode(right.toJson());

  HumanModelWriteStatus _statusFor(String code) => switch (code) {
        'human_model_scope_mismatch' => HumanModelWriteStatus.scopeMismatch,
        'human_cloud_unauthenticated' => HumanModelWriteStatus.unavailable,
        _ => HumanModelWriteStatus.invalidModel,
      };

  String _firebaseCode(FirebaseException error) => switch (error.code) {
        'permission-denied' => 'human_cloud_permission_denied',
        'unavailable' => 'human_cloud_unavailable',
        'deadline-exceeded' => 'human_cloud_unavailable',
        _ => 'human_cloud_read_failure',
      };

  HumanModelWriteStatus _firebaseStatus(FirebaseException error) =>
      switch (error.code) {
        'permission-denied' => HumanModelWriteStatus.scopeMismatch,
        'unavailable' ||
        'deadline-exceeded' =>
          HumanModelWriteStatus.unavailable,
        'aborted' ||
        'failed-precondition' =>
          HumanModelWriteStatus.revisionConflict,
        _ => HumanModelWriteStatus.persistenceFailure,
      };
}
