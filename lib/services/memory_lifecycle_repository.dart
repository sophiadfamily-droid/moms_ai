import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/memory_lifecycle.dart';
import '../models/memory_lifecycle_state.dart';
import '../models/life_context/memory_context.dart';
import 'auth_service.dart';
import 'life_context/life_context_memory_projection.dart';

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
    implements MemoryLifecycleRepository {
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
  Future<void> createProposal(
    MemoryProposal proposal,
    MemoryLifecycleMutation mutation,
  ) async {
    final ref = _memoriesRef();
    if (ref == null) return;
    await ref.doc(proposal.id).set(
          MemoryLifecycleFirestoreSerializer.proposal(
            proposal,
            mutation,
          ),
          SetOptions(merge: true),
        );
  }

  @override
  Future<void> applyMutations(List<MemoryLifecycleMutation> mutations) async {
    final ref = _memoriesRef();
    if (ref == null || mutations.isEmpty) return;
    final batch = _firestore.batch();
    final grouped = <String, List<MemoryLifecycleMutation>>{};
    for (final mutation in mutations) {
      grouped.putIfAbsent(mutation.memoryId, () => []).add(mutation);
    }
    for (final entry in grouped.entries) {
      batch.set(
        ref.doc(entry.key),
        MemoryLifecycleFirestoreSerializer.mutations(entry.value),
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }
}

final class MemoryLifecycleFirestoreSerializer {
  const MemoryLifecycleFirestoreSerializer._();

  static Map<String, dynamic> proposal(
    MemoryProposal proposal,
    MemoryLifecycleMutation mutation,
  ) =>
      {
        'text': proposal.text,
        'normalizedText': proposal.normalizedText,
        'category': proposal.category,
        'semanticType': proposal.semanticType.name,
        'importance': proposal.importance,
        'sensitivity': proposal.sensitivity.name,
        'source': proposal.source,
        'createdAt': proposal.proposedAt,
        'updatedAt': proposal.proposedAt,
        'confirmationStatus': 'unconfirmed',
        'lifecycleState': mutation.newState.name,
        'confirmationRequired': proposal.confirmationRequired,
        if (proposal.potentiallyReplacesMemoryId != null)
          'potentiallyReplacesMemoryId': proposal.potentiallyReplacesMemoryId,
        if (proposal.validFrom != null) 'validFrom': proposal.validFrom,
        if (proposal.validUntil != null) 'validUntil': proposal.validUntil,
        if (proposal.expiresAt != null) 'expiresAt': proposal.expiresAt,
        if (proposal.evidence != null) 'evidence': proposal.evidence,
        if (proposal.confidence != null) 'confidence': proposal.confidence,
        'lifecycleHistory': [mutation.record.toJson()],
      };

  static Map<String, dynamic> mutation(MemoryLifecycleMutation mutation) => {
        'lifecycleState': mutation.newState.name,
        if (mutation.newState == MemoryLifecycleState.confirmed ||
            mutation.newState == MemoryLifecycleState.active)
          'confirmationStatus': 'confirmed',
        if (mutation.newState == MemoryLifecycleState.rejected)
          'confirmationStatus': 'rejected',
        if (mutation.newState == MemoryLifecycleState.obsolete ||
            mutation.newState == MemoryLifecycleState.superseded ||
            mutation.newState == MemoryLifecycleState.expired)
          'confirmationStatus': 'obsolete',
        'updatedAt': mutation.record.occurredAt,
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
