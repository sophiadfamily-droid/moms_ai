import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/identity/life_entity.dart';
import 'firestore_identity_serialization.dart';
import 'identity_read_repository.dart';
import 'identity_write_repository.dart';

final class FirestoreIdentityWriteRepository
    implements IdentityWriteRepository {
  final FirebaseFirestore _firestore;

  const FirestoreIdentityWriteRepository({
    required FirebaseFirestore firestore,
  }) : _firestore = firestore;

  @override
  Future<RevisionedIdentity> create({
    required IdentityAccountScope scope,
    required LifeEntity entity,
  }) async {
    _validateBoundary(scope: scope, entityId: entity.id);
    IdentityWriteValidator.validateCreate(entity);
    final data = FirestoreIdentitySerialization.toDocument(
      entity: entity,
      revision: 1,
    );
    try {
      return await _firestore.runTransaction((transaction) async {
        final reference = _reference(scope, entity.id);
        final existing = await transaction.get(reference);
        if (existing.exists) {
          throw const IdentityRepositoryException('identity_already_exists');
        }
        transaction.set(reference, data);
        return RevisionedIdentity(entity: entity, revision: 1);
      });
    } on IdentityRepositoryException {
      rethrow;
    } on FirebaseException catch (error) {
      throw _mapFirebaseError(error);
    } catch (_) {
      throw const IdentityRepositoryException('transaction_failed');
    }
  }

  @override
  Future<RevisionedIdentity> update({
    required IdentityAccountScope scope,
    required LifeEntity entity,
    required int expectedRevision,
  }) async {
    _validateBoundary(scope: scope, entityId: entity.id);
    if (expectedRevision < 1) {
      throw const IdentityRepositoryException('invalid_revision');
    }
    try {
      return await _firestore.runTransaction((transaction) async {
        final reference = _reference(scope, entity.id);
        final snapshot = await transaction.get(reference);
        final current = _readExisting(snapshot);
        final revision = _revision(snapshot.data()!);
        if (revision != expectedRevision) {
          throw const IdentityRepositoryException('revision_conflict');
        }
        IdentityWriteValidator.validateUpdate(
          current: current,
          next: entity,
          expectedRevision: expectedRevision,
        );
        final nextRevision = revision + 1;
        transaction.set(
          reference,
          FirestoreIdentitySerialization.toDocument(
            entity: entity,
            revision: nextRevision,
          ),
        );
        return RevisionedIdentity(entity: entity, revision: nextRevision);
      });
    } on IdentityRepositoryException {
      rethrow;
    } on FirebaseException catch (error) {
      throw _mapFirebaseError(error);
    } catch (_) {
      throw const IdentityRepositoryException('transaction_failed');
    }
  }

  @override
  Future<RevisionedIdentity> softDelete({
    required IdentityAccountScope scope,
    required String entityId,
    required int expectedRevision,
    required DateTime updatedAt,
  }) async {
    _validateBoundary(scope: scope, entityId: entityId);
    if (expectedRevision < 1) {
      throw const IdentityRepositoryException('invalid_revision');
    }
    try {
      return await _firestore.runTransaction((transaction) async {
        final reference = _reference(scope, entityId);
        final snapshot = await transaction.get(reference);
        final current = _readExisting(snapshot);
        final revision = _revision(snapshot.data()!);
        if (revision != expectedRevision) {
          throw const IdentityRepositoryException('revision_conflict');
        }
        final deleted = IdentityWriteValidator.deletedEntity(
          current: current,
          updatedAt: updatedAt,
        );
        final nextRevision = revision + 1;
        transaction.set(
          reference,
          FirestoreIdentitySerialization.toDocument(
            entity: deleted,
            revision: nextRevision,
          ),
        );
        return RevisionedIdentity(entity: deleted, revision: nextRevision);
      });
    } on IdentityRepositoryException {
      rethrow;
    } on FirebaseException catch (error) {
      throw _mapFirebaseError(error);
    } catch (_) {
      throw const IdentityRepositoryException('transaction_failed');
    }
  }

  DocumentReference<Map<String, dynamic>> _reference(
    IdentityAccountScope scope,
    String entityId,
  ) =>
      _firestore
          .collection('users')
          .doc(scope.accountId)
          .collection('identities')
          .doc(entityId);

  void _validateBoundary({
    required IdentityAccountScope scope,
    required String entityId,
  }) {
    FirestoreIdentitySerialization.validateDocumentId(
      scope.accountId,
      field: 'accountId',
    );
    FirestoreIdentitySerialization.validateDocumentId(entityId);
  }

  LifeEntity _readExisting(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      throw const IdentityRepositoryException('identity_not_found');
    }
    return FirestoreIdentitySerialization.fromDocument(
      documentId: snapshot.id,
      data: Map<String, Object?>.from(data),
    );
  }

  int _revision(Map<String, dynamic> data) {
    final value = data['revision'];
    if (value is! int || value < 1) {
      throw const IdentityRepositoryException(
        'corrupt_identity_document',
        field: 'revision',
      );
    }
    return value;
  }

  IdentityRepositoryException _mapFirebaseError(FirebaseException error) {
    final code = switch (error.code) {
      'permission-denied' => 'permission_denied',
      'deadline-exceeded' => 'repository_timeout',
      'unavailable' => 'repository_unavailable',
      'unauthenticated' => 'unauthenticated',
      'aborted' => 'revision_conflict',
      _ => 'transaction_failed',
    };
    return IdentityRepositoryException(code, causeCode: error.code);
  }
}
