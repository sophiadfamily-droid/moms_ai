import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_profile.dart';
import '../models/revisioned_domain_models.dart';
import '../models/revisioned_sync_protocol.dart';
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

    final snapshot = await ref.get();
    if (snapshot.exists && snapshot.data()?['profileRevision'] is int) {
      final data = snapshot.data()!;
      final result = await updateRevisioned(
        accountScopeId: AuthService.requireUserId(),
        profile: profile,
        changedFields: ProfileFieldOwnership.profileOwnedFields,
        expectedRevision: data['profileRevision'] as int,
        mutationId: 'legacy-profile:${DateTime.now().microsecondsSinceEpoch}',
      );
      if (result.status != RevisionedCloudWriteStatus.success &&
          result.status != RevisionedCloudWriteStatus.idempotent) {
        throw const FormatException('profile_revision_conflict');
      }
      return;
    }
    final result = await createRevisioned(
      accountScopeId: AuthService.requireUserId(),
      profile: profile,
      mutationId: 'legacy-profile:${DateTime.now().microsecondsSinceEpoch}',
    );
    if (result.status != RevisionedCloudWriteStatus.success &&
        result.status != RevisionedCloudWriteStatus.idempotent) {
      throw const FormatException('profile_revision_conflict');
    }
  }

  static Future<RevisionedCloudWriteResult<RevisionedProfileState>>
      createRevisioned({
    required String accountScopeId,
    required UserProfile profile,
    required String mutationId,
  }) async {
    final ref = _profileRef;
    if (ref == null || accountScopeId != AuthService.currentUserId) {
      return const RevisionedCloudWriteResult(
        RevisionedCloudWriteStatus.accountMismatch,
      );
    }
    if (mutationId.trim().isEmpty) {
      throw const FormatException('profile_mutation_id_required');
    }
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (snapshot.exists) {
        final data = snapshot.data()!;
        if (data['lastMutationId'] == mutationId) {
          return RevisionedCloudWriteResult(
            RevisionedCloudWriteStatus.idempotent,
            value: revisionedProfileFromData(data),
          );
        }
        return RevisionedCloudWriteResult(
          RevisionedCloudWriteStatus.revisionConflict,
          value: revisionedProfileFromData(data),
        );
      }
      final now = DateTime.now().toUtc();
      final created = RevisionedProfileState(
        accountScopeId: accountScopeId,
        profile: profile,
        revision: 1,
        createdAt: now,
        updatedAt: now,
        lastMutationId: mutationId,
        legacyExtensions: profile.legacyExtensions,
      );
      transaction.set(ref, _firestoreData(created, create: true));
      return RevisionedCloudWriteResult(
        RevisionedCloudWriteStatus.success,
        value: created,
      );
    });
  }

  static Future<RevisionedCloudWriteResult<RevisionedProfileState>>
      updateRevisioned({
    required String accountScopeId,
    required UserProfile profile,
    required Set<String> changedFields,
    required int expectedRevision,
    required String mutationId,
  }) async {
    ProfileFieldOwnership.validatePatch(changedFields);
    final ref = _profileRef;
    if (ref == null || accountScopeId != AuthService.currentUserId) {
      return const RevisionedCloudWriteResult(
        RevisionedCloudWriteStatus.accountMismatch,
      );
    }
    if (changedFields.isEmpty ||
        expectedRevision < 1 ||
        mutationId.trim().isEmpty) {
      throw const FormatException('profile_revisioned_update_invalid');
    }
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) {
        return const RevisionedCloudWriteResult(
          RevisionedCloudWriteStatus.notFound,
        );
      }
      final remote = revisionedProfileFromData(snapshot.data()!);
      if (remote.lastMutationId == mutationId) {
        return RevisionedCloudWriteResult(
          RevisionedCloudWriteStatus.idempotent,
          value: remote,
        );
      }
      if (remote.revision != expectedRevision) {
        return RevisionedCloudWriteResult(
          RevisionedCloudWriteStatus.revisionConflict,
          value: remote,
        );
      }
      final updated = RevisionedProfileState(
        accountScopeId: remote.accountScopeId,
        profile: profile,
        revision: expectedRevision + 1,
        createdAt: remote.createdAt,
        updatedAt: DateTime.now().toUtc(),
        lastMutationId: mutationId,
        legacyExtensions: {
          ...remote.legacyExtensions,
          ...profile.legacyExtensions,
        },
      );
      transaction.update(ref, _firestoreData(updated, create: false));
      return RevisionedCloudWriteResult(
        RevisionedCloudWriteStatus.success,
        value: updated,
      );
    });
  }

  static RevisionedProfileState revisionedProfileFromData(
    Map<String, dynamic> data,
  ) {
    if (data['profileRevision'] == null) {
      final profile = UserProfile.fromJson(data);
      final now = _date(data['updatedAt']) ?? DateTime.now().toUtc();
      return RevisionedProfileState(
        accountScopeId: AuthService.currentUserId ?? 'legacy-local',
        profile: profile,
        revision: 1,
        createdAt: now,
        updatedAt: now,
        lastMutationId: 'legacy:profile',
        legacyExtensions: profile.legacyExtensions,
        projectionProvenance: 'legacyCloud',
      );
    }
    return RevisionedProfileState(
      schemaVersion: data['schemaVersion'] as int? ?? -1,
      accountScopeId: data['accountScopeId'] as String? ?? '',
      profile: UserProfile.fromJson(
        Map<String, dynamic>.from(data['payload'] as Map),
      ),
      revision: data['profileRevision'] as int? ?? -1,
      createdAt: _date(data['createdAt'])!,
      updatedAt: _date(data['updatedAt'])!,
      lastMutationId: data['lastMutationId'] as String? ?? '',
      syncStatus: RevisionedSyncStatus.values.singleWhere(
        (value) => value.name == data['syncStatus'],
      ),
      legacyExtensions: Map<String, dynamic>.from(
        data['legacyExtensions'] as Map? ?? const {},
      ),
      projectionProvenance:
          data['projectionProvenance'] as String? ?? 'profileOwned',
    );
  }

  static Map<String, dynamic> _firestoreData(
    RevisionedProfileState value, {
    required bool create,
  }) =>
      {
        'schemaVersion': value.schemaVersion,
        'accountScopeId': value.accountScopeId,
        'entityId': RevisionedProfileState.entityId,
        'payload': ProfileFieldOwnership.ownedPayload(value.profile),
        'profileRevision': value.revision,
        'createdAt': create ? FieldValue.serverTimestamp() : value.createdAt,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastMutationId': value.lastMutationId,
        'syncStatus': RevisionedSyncStatus.synced.name,
        'legacyExtensions': value.legacyExtensions,
        'projectionProvenance': value.projectionProvenance,
      };

  static DateTime? _date(Object? value) => switch (value) {
        Timestamp() => value.toDate().toUtc(),
        String() => DateTime.tryParse(value)?.toUtc(),
        _ => null,
      };

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

    return data['profileRevision'] is int
        ? revisionedProfileFromData(data).profile
        : UserProfile.fromJson(data);
  }

  static Future<RevisionedProfileState?> getRevisioned() async {
    final ref = _profileRef;
    if (ref == null) return null;
    final snapshot = await ref.get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    return revisionedProfileFromData(data);
  }
}
