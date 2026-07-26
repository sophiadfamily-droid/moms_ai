import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

import '../models/memory_lifecycle.dart';
import '../models/memory_lifecycle_state.dart';
import '../models/life_context/memory_context.dart';
import '../models/life_context/life_context_provenance.dart';
import '../models/memory_contradiction.dart';
import 'auth_service.dart';
import 'life_context/life_context_memory_projection.dart';

final class MemoryLifecycleTechnicalReceipt {
  const MemoryLifecycleTechnicalReceipt({
    required this.revision,
    required this.lastMutationId,
    required this.tombstone,
  });

  final int revision;
  final String? lastMutationId;
  final bool tombstone;
}

abstract interface class MemoryLifecycleReceiptReader {
  Future<MemoryLifecycleTechnicalReceipt?> readTechnicalReceipt(
    String memoryId,
  );
}

abstract interface class MemoryLifecycleRepository {
  Future<String?> allocateProposalId();

  Future<List<LifeMemoryFact>> findCandidates(
    MemoryProposal proposal, {
    int limit = 25,
  });

  Future<void> createProposal(
    MemoryProposal proposal,
    MemoryLifecycleMutation mutation,
  );

  Future<LifeMemoryFact?> getById(String memoryId);

  Future<void> applyMutations(List<MemoryLifecycleMutation> mutations);
}

final class MemoryReplacementPersistenceResult {
  const MemoryReplacementPersistenceResult({
    required this.action,
    required this.candidate,
  });
  final MemoryReplacementPendingAction action;
  final MemoryContradictionCandidate candidate;
}

abstract interface class MemoryReplacementPendingRepository {
  Future<MemoryReplacementPersistenceResult?> persistReplacementProposal({
    required MemoryProposal proposal,
    required MemoryLifecycleMutation mutation,
    required MemoryContradictionMatch match,
    required String accountScopeId,
    required String logicalRequestId,
    required DateTime createdAt,
  });

  Future<MemoryReplacementPendingAction?> findPendingReplacement({
    required String accountScopeId,
    required String logicalRequestId,
  });

  Future<MemoryReplacementPendingAction> updatePendingReplacementState({
    required MemoryReplacementPendingAction action,
    required MemoryReplacementActionState state,
    required DateTime updatedAt,
  });
}

final class FirestoreMemoryLifecycleRepository
    implements
        MemoryLifecycleRepository,
        MemoryLifecycleReceiptReader,
        MemoryReplacementPendingRepository {
  final FirebaseFirestore _firestore;

  FirestoreMemoryLifecycleRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>>? _memoriesRef() {
    final uid = AuthService.currentUserId;
    if (uid == null || uid.isEmpty) return null;
    return _firestore.collection('users').doc(uid).collection('memories');
  }

  CollectionReference<Map<String, dynamic>>? _replacementActionsRef() {
    final uid = AuthService.currentUserId;
    if (uid == null || uid.isEmpty) return null;
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('memoryReplacementActions');
  }

  @override
  Future<String?> allocateProposalId() async => _memoriesRef()?.doc().id;

  @override
  Future<List<LifeMemoryFact>> findCandidates(
    MemoryProposal proposal, {
    int limit = 25,
  }) async {
    final ref = _memoriesRef();
    if (ref == null || limit <= 0) return const [];
    final documents = <String, Map<String, dynamic>>{};
    final canonicalKey = proposal.semanticIdentity?.canonicalKey;
    if (canonicalKey != null && canonicalKey.isNotEmpty) {
      final comparable = await ref
          .where('canonicalKey', isEqualTo: canonicalKey)
          .limit(limit)
          .get();
      for (final document in comparable.docs) {
        documents[document.id] = {...document.data(), 'id': document.id};
      }
    }
    final exact = documents.length >= limit
        ? null
        : await ref
            .where('normalizedText', isEqualTo: proposal.normalizedText)
            .limit(1)
            .get();
    for (final document in exact?.docs ?? const []) {
      documents[document.id] = {...document.data(), 'id': document.id};
    }
    if (proposal.category.trim().isNotEmpty && documents.length < limit) {
      final sameCategory = await ref
          .where('category', isEqualTo: proposal.category)
          .limit(limit)
          .get();
      for (final document in sameCategory.docs) {
        documents[document.id] = {...document.data(), 'id': document.id};
      }
    }
    return const HistoricalMemoryContextProjection()
        .project(documents.values.take(limit))
        .memories;
  }

  @override
  Future<LifeMemoryFact?> getById(String memoryId) async {
    final ref = _memoriesRef();
    if (ref == null || memoryId.trim().isEmpty) return null;
    final document = await ref.doc(memoryId).get();
    final data = document.data();
    if (!document.exists || data == null) return null;
    return const HistoricalMemoryContextProjection()
        .project([
          {...data, 'id': document.id},
        ])
        .memories
        .single;
  }

  @override
  Future<MemoryLifecycleTechnicalReceipt?> readTechnicalReceipt(
    String memoryId,
  ) async {
    final ref = _memoriesRef();
    if (ref == null || memoryId.trim().isEmpty) return null;
    final document = await ref.doc(memoryId).get();
    final data = document.data();
    if (!document.exists || data == null) return null;
    final revision = data['memoryRevision'];
    if (revision is! int || revision < 1) {
      throw const FormatException('memory_revision_invalid');
    }
    return MemoryLifecycleTechnicalReceipt(
      revision: revision,
      lastMutationId:
          data['lastMutationId'] is String ? data['lastMutationId'] : null,
      tombstone: data['tombstone'] == true,
    );
  }

  @override
  Future<void> createProposal(
    MemoryProposal proposal,
    MemoryLifecycleMutation mutation,
  ) async {
    final ref = _memoriesRef();
    if (ref == null) return;
    final uid = AuthService.currentUserId!;
    final reference = ref.doc(proposal.id);
    await _firestore.runTransaction((transaction) async {
      final current = await transaction.get(reference);
      final mutationId = mutation.record.idempotencyKey;
      if (current.exists) {
        if (current.data()?['lastMutationId'] == mutationId) return;
        throw StateError('memory_revision_conflict');
      }
      transaction.set(
        reference,
        MemoryLifecycleFirestoreSerializer.proposal(
          proposal,
          mutation,
          accountScopeId: uid,
        ),
      );
    });
  }

  @override
  Future<MemoryReplacementPersistenceResult?> persistReplacementProposal({
    required MemoryProposal proposal,
    required MemoryLifecycleMutation mutation,
    required MemoryContradictionMatch match,
    required String accountScopeId,
    required String logicalRequestId,
    required DateTime createdAt,
  }) async {
    final memories = _memoriesRef();
    final actions = _replacementActionsRef();
    final uid = AuthService.currentUserId;
    if (memories == null ||
        actions == null ||
        uid == null ||
        uid != accountScopeId ||
        logicalRequestId.trim().isEmpty) {
      return null;
    }
    final scopeFingerprint = _hash(
      'zelia-memory-replacement-account-v1',
      accountScopeId,
    );
    final requestFingerprint = _hash(
      'zelia-memory-replacement-request-v1',
      logicalRequestId,
    );
    final actionId = _hash(
      'zelia-memory-replacement-action-v1',
      '$scopeFingerprint|$requestFingerprint|${proposal.id}|'
          '${match.existingMemoryId}|${match.canonicalKey}|'
          '${match.existingRevision}',
    );
    final proposalRef = memories.doc(proposal.id);
    final actionRef = actions.doc(actionId);
    return _firestore.runTransaction((transaction) async {
      final proposalSnapshot = await transaction.get(proposalRef);
      final actionSnapshot = await transaction.get(actionRef);
      final proposalData = proposalSnapshot.data();
      int proposedRevision;
      if (proposalSnapshot.exists) {
        if (proposalData == null ||
            proposalData['memoryId'] != proposal.id ||
            proposalData['accountScopeId'] != accountScopeId ||
            proposalData['canonicalKey'] != match.canonicalKey ||
            proposalData['lifecycleState'] !=
                MemoryLifecycleState.proposed.name ||
            proposalData['logicalRequestFingerprint'] != requestFingerprint) {
          throw const FormatException(
            'memory_replacement_partial_proposal_incoherent',
          );
        }
        final revision = proposalData['memoryRevision'];
        if (revision is! int || revision < 1) {
          throw const FormatException('memory_revision_invalid');
        }
        proposedRevision = revision;
      } else {
        proposedRevision = 1;
      }
      final contradictionId = _hash(
        'zelia-memory-contradiction-id-v1',
        '$scopeFingerprint|${match.existingMemoryId}|${proposal.id}|'
            '${match.canonicalKey}|${match.existingRevision}|'
            '$proposedRevision',
      );
      final candidate = MemoryContradictionCandidate(
        contradictionId: contradictionId,
        existingMemoryId: match.existingMemoryId,
        proposedMemoryId: proposal.id,
        canonicalKey: match.canonicalKey,
        existingRevision: match.existingRevision,
        proposedRevision: proposedRevision,
        existingValueFingerprint: match.existingValueFingerprint,
        proposedValueFingerprint: match.proposedValueFingerprint,
        subjectScope: match.subjectScope,
        detectedAt: createdAt.toUtc(),
        reasonCode: match.reasonCode,
        eligibleForReplacement: true,
      );
      final action = MemoryReplacementPendingAction(
        actionId: actionId,
        accountScopeFingerprint: scopeFingerprint,
        existingMemoryId: match.existingMemoryId,
        proposedMemoryId: proposal.id,
        canonicalKey: match.canonicalKey,
        expectedExistingRevision: match.existingRevision,
        expectedProposedRevision: proposedRevision,
        contradictionId: contradictionId,
        reasonCode: match.reasonCode,
        state: MemoryReplacementActionState.pending,
        logicalRequestFingerprint: requestFingerprint,
        createdAt: createdAt.toUtc(),
        updatedAt: createdAt.toUtc(),
      );
      if (actionSnapshot.exists) {
        final current =
            MemoryReplacementPendingAction.fromJson(actionSnapshot.data());
        if (current.proposedMemoryId != proposal.id ||
            current.contradictionId != contradictionId ||
            current.expectedProposedRevision != proposedRevision) {
          throw const FormatException(
            'memory_replacement_action_idempotency_conflict',
          );
        }
        return MemoryReplacementPersistenceResult(
          action: current,
          candidate: candidate,
        );
      }
      if (!proposalSnapshot.exists) {
        transaction.set(proposalRef, {
          ...MemoryLifecycleFirestoreSerializer.proposal(
            proposal,
            mutation,
            accountScopeId: accountScopeId,
          ),
          'logicalRequestFingerprint': requestFingerprint,
        });
      }
      transaction.set(actionRef, {
        ...action.toJson(),
        'contradictionCandidate': candidate.toJson(),
      });
      return MemoryReplacementPersistenceResult(
        action: action,
        candidate: candidate,
      );
    });
  }

  @override
  Future<MemoryReplacementPendingAction?> findPendingReplacement({
    required String accountScopeId,
    required String logicalRequestId,
  }) async {
    if (AuthService.currentUserId != accountScopeId) return null;
    final ref = _replacementActionsRef();
    if (ref == null) return null;
    final fingerprint = _hash(
      'zelia-memory-replacement-request-v1',
      logicalRequestId,
    );
    final snapshot = await ref
        .where('logicalRequestFingerprint', isEqualTo: fingerprint)
        .limit(2)
        .get();
    if (snapshot.docs.length > 1) {
      throw const FormatException('multiple_memory_replacement_actions');
    }
    return snapshot.docs.isEmpty
        ? null
        : MemoryReplacementPendingAction.fromJson(
            snapshot.docs.single.data(),
          );
  }

  @override
  Future<MemoryReplacementPendingAction> updatePendingReplacementState({
    required MemoryReplacementPendingAction action,
    required MemoryReplacementActionState state,
    required DateTime updatedAt,
  }) async {
    final ref = _replacementActionsRef();
    if (ref == null) {
      throw const FormatException('memory_replacement_repository_unavailable');
    }
    final next = action.withState(state, updatedAt);
    await _firestore.runTransaction((transaction) async {
      final reference = ref.doc(action.actionId);
      final snapshot = await transaction.get(reference);
      if (!snapshot.exists) {
        throw const FormatException('memory_replacement_action_not_found');
      }
      final current = MemoryReplacementPendingAction.fromJson(snapshot.data());
      if (current.state == state) return;
      if (current.state != MemoryReplacementActionState.pending) {
        throw const FormatException('memory_replacement_action_terminal');
      }
      transaction.update(reference, {
        'state': state.name,
        'updatedAt': next.updatedAt.toIso8601String(),
      });
    });
    return next;
  }

  static String _hash(String namespace, String value) =>
      sha256.convert(utf8.encode('$namespace|$value')).toString();

  @override
  Future<void> applyMutations(List<MemoryLifecycleMutation> mutations) async {
    final ref = _memoriesRef();
    if (ref == null || mutations.isEmpty) return;
    final grouped = <String, List<MemoryLifecycleMutation>>{};
    for (final mutation in mutations) {
      grouped.putIfAbsent(mutation.memoryId, () => []).add(mutation);
    }
    for (final entry in grouped.entries) {
      final reference = ref.doc(entry.key);
      await _firestore.runTransaction((transaction) async {
        final current = await transaction.get(reference);
        final data = current.data();
        if (!current.exists || data == null) {
          throw StateError('memory_not_found');
        }
        final revision = data['memoryRevision'];
        if (revision is! int || revision < 1) {
          throw StateError('memory_legacy_requires_migration');
        }
        final mutationId = entry.value.last.record.idempotencyKey;
        if (data['lastMutationId'] == mutationId) return;
        transaction.update(reference, {
          ...MemoryLifecycleFirestoreSerializer.mutations(entry.value),
          'memoryRevision': revision + 1,
          'lastMutationId': mutationId,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    }
  }
}

final class MemoryLifecycleFirestoreSerializer {
  const MemoryLifecycleFirestoreSerializer._();

  static Map<String, dynamic> proposal(
    MemoryProposal proposal,
    MemoryLifecycleMutation mutation, {
    String accountScopeId = 'test-scope',
  }) =>
      {
        'schemaVersion': 1,
        'memoryId': proposal.id,
        'accountScopeId': accountScopeId,
        'memoryRevision': 1,
        'text': proposal.text,
        'normalizedText': proposal.normalizedText,
        'category': proposal.category,
        'semanticType': proposal.semanticType.name,
        'importance': proposal.importance,
        'sensitivity': const {'health', 'medical', 'sante'}
                .contains(proposal.category.trim().toLowerCase())
            ? 'sensitive'
            : proposal.sensitivity.name,
        'provenance': LifeContextSourceType.memory.name,
        'isHealth': const {'health', 'medical', 'sante'}
            .contains(proposal.category.trim().toLowerCase()),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'confirmationStatus': 'unconfirmed',
        'lifecycleState': mutation.newState.name,
        'lifecycleStatus': mutation.newState.name,
        'evidenceClassification': proposal.evidenceClassification.name,
        'evidenceSubjectType': proposal.evidenceSubjectType.name,
        'evidenceRisks':
            proposal.evidenceRisks.map((risk) => risk.name).toList(),
        'isCorrection': proposal.isCorrection,
        if (proposal.subjectEntityId != null)
          'subjectEntityId': proposal.subjectEntityId,
        if (proposal.semanticIdentity != null) ...{
          'semanticIdentity': proposal.semanticIdentity!.toJson(),
          'canonicalKey': proposal.semanticIdentity!.canonicalKey,
          'semanticValue': proposal.semanticValue,
          'eligibleForAutomaticContradiction':
              proposal.semanticIdentity!.eligibleForAutomaticContradiction,
        },
        'lastMutationId': mutation.record.idempotencyKey,
        'tombstone': false,
        if (proposal.validFrom != null) 'validFrom': proposal.validFrom,
        if (proposal.validUntil != null) 'validUntil': proposal.validUntil,
        if (proposal.expiresAt != null) 'expiresAt': proposal.expiresAt,
        'lifecycleHistory': [mutation.record.toJson()],
      };

  static Map<String, dynamic> mutation(MemoryLifecycleMutation mutation) => {
        'lifecycleState': mutation.newState.name,
        'lifecycleStatus': mutation.newState.name,
        'tombstone': mutation.newState == MemoryLifecycleState.deleted,
        if (mutation.newState == MemoryLifecycleState.confirmed ||
            mutation.newState == MemoryLifecycleState.active)
          'confirmationStatus': 'confirmed',
        if (mutation.newState == MemoryLifecycleState.rejected)
          'confirmationStatus': 'rejected',
        if (mutation.newState == MemoryLifecycleState.obsolete ||
            mutation.newState == MemoryLifecycleState.superseded ||
            mutation.newState == MemoryLifecycleState.expired)
          'confirmationStatus': 'obsolete',
        if (mutation.confirmedAt != null) 'confirmedAt': mutation.confirmedAt,
        if (mutation.rejectedAt != null) 'rejectedAt': mutation.rejectedAt,
        if (mutation.deletedAt != null) 'deletedAt': mutation.deletedAt,
        if (mutation.expiresAt != null) 'expiresAt': mutation.expiresAt,
        if (mutation.replacedByMemoryId != null)
          'replacedByMemoryId': mutation.replacedByMemoryId,
        if (mutation.supersedesMemoryId != null)
          'supersedesMemoryId': mutation.supersedesMemoryId,
        'lifecycleHistory': FieldValue.arrayUnion([mutation.record.toJson()]),
      };

  static Map<String, dynamic> mutations(
    List<MemoryLifecycleMutation> mutations,
  ) {
    if (mutations.isEmpty) return const {};
    final result = mutation(mutations.last);
    DateTime? confirmedAt;
    DateTime? rejectedAt;
    DateTime? deletedAt;
    DateTime? expiresAt;
    String? replacedByMemoryId;
    String? supersedesMemoryId;
    for (final item in mutations) {
      confirmedAt ??= item.confirmedAt;
      rejectedAt ??= item.rejectedAt;
      deletedAt ??= item.deletedAt;
      expiresAt ??= item.expiresAt;
      replacedByMemoryId ??= item.replacedByMemoryId;
      supersedesMemoryId ??= item.supersedesMemoryId;
    }
    if (confirmedAt != null) result['confirmedAt'] = confirmedAt;
    if (rejectedAt != null) result['rejectedAt'] = rejectedAt;
    if (deletedAt != null) result['deletedAt'] = deletedAt;
    if (expiresAt != null) result['expiresAt'] = expiresAt;
    if (replacedByMemoryId != null) {
      result['replacedByMemoryId'] = replacedByMemoryId;
    }
    if (supersedesMemoryId != null) {
      result['supersedesMemoryId'] = supersedesMemoryId;
    }
    result['lifecycleHistory'] = FieldValue.arrayUnion(
      mutations.map((item) => item.record.toJson()).toList(growable: false),
    );
    return result;
  }
}
