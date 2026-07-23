import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/memory_lifecycle.dart';
import '../models/memory_lifecycle_state.dart';
import '../models/life_context/memory_context.dart';
import '../models/life_context/life_context_provenance.dart';
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

final class FirestoreMemoryLifecycleRepository
    implements MemoryLifecycleRepository, MemoryLifecycleReceiptReader {
  final FirebaseFirestore _firestore;

  FirestoreMemoryLifecycleRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>>? _memoriesRef() {
    final uid = AuthService.currentUserId;
    if (uid == null || uid.isEmpty) return null;
    return _firestore.collection('users').doc(uid).collection('memories');
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
    final exact = await ref
        .where('normalizedText', isEqualTo: proposal.normalizedText)
        .limit(1)
        .get();
    for (final document in exact.docs) {
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
