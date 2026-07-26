import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/routine_model.dart';
import 'auth_service.dart';

abstract interface class RoutineRepository {
  Future<RoutineProposal?> createOrVerifyProposal(RoutineProposal proposal);
  Future<RoutineProposal?> findProposal({
    required String accountScopeId,
    required String proposalId,
  });
  Future<RoutineProposal?> findActiveProposal(String accountScopeId);
  Future<RoutineProposal?> findLatestProposal(String accountScopeId);
  Future<RoutineProposal?> updateProposal(RoutineProposal proposal);
  Future<RoutineCommitResult> commitProposal(
    RoutineProposal proposal,
    DateTime committedAt,
  );
  Future<RoutineModel?> createOrVerify(RoutineModel routine);
  Future<List<RoutineModel>> listForAccount(String accountScopeId);
}

enum RoutineCommitCode {
  committed,
  alreadyCommitted,
  conflict,
  expired,
  unavailable,
}

final class RoutineCommitResult {
  const RoutineCommitResult(this.code, {this.routine});

  final RoutineCommitCode code;
  final RoutineModel? routine;

  bool get isSuccess =>
      code == RoutineCommitCode.committed ||
      code == RoutineCommitCode.alreadyCommitted;
}

final class FirestoreRoutineRepository implements RoutineRepository {
  FirestoreRoutineRepository({FirebaseFirestore? firestore})
      : _injectedFirestore = firestore;

  final FirebaseFirestore? _injectedFirestore;
  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _ref(String scope) =>
      _firestore.collection('users').doc(scope).collection('routines');

  CollectionReference<Map<String, dynamic>> _proposalsRef(String scope) =>
      _firestore.collection('users').doc(scope).collection('routineProposals');

  bool _owns(String accountScopeId) =>
      AuthService.currentUserId == accountScopeId;

  static Map<String, dynamic> _proposalData(RoutineProposal proposal) => {
        ...proposal.toJson(),
        'createdAt': Timestamp.fromDate(proposal.createdAt),
        'updatedAt': Timestamp.fromDate(proposal.updatedAt),
        'expiresAt': Timestamp.fromDate(proposal.expiresAt),
      };

  static RoutineProposal _proposalFrom(Map<String, dynamic>? data) {
    if (data == null) {
      throw const FormatException('invalid_routine_proposal_v1');
    }
    return RoutineProposal.fromJson(_datesToIso(data));
  }

  static Map<String, dynamic> _routineData(RoutineModel routine) => {
        ...routine.toJson(),
        'createdAt': Timestamp.fromDate(routine.createdAt),
        'updatedAt': Timestamp.fromDate(routine.updatedAt),
      };

  static RoutineModel _routineFrom(Map<String, dynamic>? data) {
    if (data == null) throw const FormatException('invalid_routine_v1');
    return RoutineModel.fromJson(_datesToIso(data));
  }

  static Map<String, dynamic> _datesToIso(Map<String, dynamic> data) {
    final normalized = Map<String, dynamic>.of(data);
    for (final key in ['createdAt', 'updatedAt', 'expiresAt']) {
      final value = normalized[key];
      if (value is Timestamp) {
        normalized[key] = value.toDate().toUtc().toIso8601String();
      }
    }
    return normalized;
  }

  @override
  Future<RoutineProposal?> createOrVerifyProposal(
    RoutineProposal proposal,
  ) async {
    if (!_owns(proposal.accountScopeId)) return null;
    final reference =
        _proposalsRef(proposal.accountScopeId).doc(proposal.proposalId);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      if (snapshot.exists) {
        final current = _proposalFrom(snapshot.data());
        return current.logicalRequestId == proposal.logicalRequestId &&
                current.accountScopeId == proposal.accountScopeId
            ? current
            : null;
      }
      transaction.set(reference, _proposalData(proposal));
      return proposal;
    });
  }

  @override
  Future<RoutineProposal?> findProposal({
    required String accountScopeId,
    required String proposalId,
  }) async {
    if (!_owns(accountScopeId)) return null;
    final snapshot = await _proposalsRef(accountScopeId).doc(proposalId).get();
    return snapshot.exists ? _proposalFrom(snapshot.data()) : null;
  }

  @override
  Future<RoutineProposal?> findActiveProposal(String accountScopeId) async {
    if (!_owns(accountScopeId)) return null;
    final snapshot = await _proposalsRef(accountScopeId).limit(20).get();
    final active = snapshot.docs
        .map((document) => _proposalFrom(document.data()))
        .where(
          (proposal) =>
              !proposal.isTerminal &&
              proposal.expiresAt.isAfter(DateTime.now().toUtc()),
        )
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return active.firstOrNull;
  }

  @override
  Future<RoutineProposal?> findLatestProposal(String accountScopeId) async {
    if (!_owns(accountScopeId)) return null;
    final snapshot = await _proposalsRef(accountScopeId).limit(20).get();
    final proposals = snapshot.docs
        .map((document) => _proposalFrom(document.data()))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return proposals.firstOrNull;
  }

  @override
  Future<RoutineProposal?> updateProposal(RoutineProposal proposal) async {
    if (!_owns(proposal.accountScopeId)) return null;
    final reference =
        _proposalsRef(proposal.accountScopeId).doc(proposal.proposalId);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      if (!snapshot.exists) return null;
      final current = _proposalFrom(snapshot.data());
      if (current.accountScopeId != proposal.accountScopeId ||
          current.logicalRequestId != proposal.logicalRequestId ||
          current.isTerminal ||
          proposal.updatedAt.isBefore(current.updatedAt)) {
        return null;
      }
      transaction.set(reference, _proposalData(proposal));
      return proposal;
    });
  }

  @override
  Future<RoutineCommitResult> commitProposal(
    RoutineProposal proposal,
    DateTime committedAt,
  ) async {
    if (!_owns(proposal.accountScopeId)) {
      return const RoutineCommitResult(RoutineCommitCode.unavailable);
    }
    final proposalReference =
        _proposalsRef(proposal.accountScopeId).doc(proposal.proposalId);
    final routineReference = _ref(proposal.accountScopeId).doc(
      proposal.proposalId,
    );
    try {
      return await _firestore.runTransaction((transaction) async {
        final proposalSnapshot = await transaction.get(proposalReference);
        final routineSnapshot = await transaction.get(routineReference);
        if (!proposalSnapshot.exists) {
          return const RoutineCommitResult(RoutineCommitCode.conflict);
        }
        final current = _proposalFrom(proposalSnapshot.data());
        if (current.accountScopeId != proposal.accountScopeId ||
            current.logicalRequestId != proposal.logicalRequestId ||
            current.proposalId != proposal.proposalId ||
            !current.isComplete) {
          return const RoutineCommitResult(RoutineCommitCode.conflict);
        }
        if (current.state == RoutineProposalState.committed) {
          if (!routineSnapshot.exists) {
            return const RoutineCommitResult(RoutineCommitCode.conflict);
          }
          final routine = _routineFrom(routineSnapshot.data());
          final expected = current.toRoutine(routine.createdAt);
          return routine.hasSameCanonicalPayload(expected)
              ? RoutineCommitResult(
                  RoutineCommitCode.alreadyCommitted,
                  routine: routine,
                )
              : const RoutineCommitResult(RoutineCommitCode.conflict);
        }
        if (current.state != RoutineProposalState.awaitingConfirmation) {
          return const RoutineCommitResult(RoutineCommitCode.conflict);
        }
        final at = committedAt.toUtc();
        if (current.isExpiredAt(at)) {
          return const RoutineCommitResult(RoutineCommitCode.expired);
        }
        final routine = current.toRoutine(at);
        if (routineSnapshot.exists) {
          final existing = _routineFrom(routineSnapshot.data());
          if (!existing.hasSameCanonicalPayload(routine)) {
            return const RoutineCommitResult(RoutineCommitCode.conflict);
          }
        } else {
          transaction.set(routineReference, _routineData(routine));
        }
        final committed = current.copyWith(
          state: RoutineProposalState.committed,
          updatedAt: at,
        );
        transaction.set(proposalReference, _proposalData(committed));
        return RoutineCommitResult(
          RoutineCommitCode.committed,
          routine: routine,
        );
      });
    } on FirebaseException {
      return const RoutineCommitResult(RoutineCommitCode.unavailable);
    }
  }

  @override
  Future<RoutineModel?> createOrVerify(RoutineModel routine) async {
    if (AuthService.currentUserId != routine.accountScopeId) return null;
    final ref = _ref(routine.accountScopeId).doc(routine.id);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (snapshot.exists) {
        final current = _routineFrom(snapshot.data());
        return current.hasSameCanonicalPayload(routine) ? current : null;
      }
      transaction.set(ref, _routineData(routine));
      return routine;
    });
  }

  @override
  Future<List<RoutineModel>> listForAccount(String accountScopeId) async {
    if (AuthService.currentUserId != accountScopeId) return const [];
    final snapshot = await _ref(accountScopeId)
        .where('status', isEqualTo: RoutineStatus.active.name)
        .limit(200)
        .get();
    return snapshot.docs
        .map((document) => _routineFrom(document.data()))
        .toList(growable: false);
  }
}
