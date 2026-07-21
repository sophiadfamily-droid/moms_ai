import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/memory_lifecycle.dart';
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
    for (final mutation in mutations) {
      batch.set(
        ref.doc(mutation.memoryId),
        MemoryLifecycleFirestoreSerializer.mutation(mutation),
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
}
