import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/routine/routine_occurrence_override.dart';
import '../auth_service.dart';
import '../routine_repository.dart';

abstract interface class RoutineOccurrenceOverrideRepository {
  Future<List<RoutineOccurrenceOverride>> listForAccount(
    String accountScopeId,
  );

  /// Creates or advances a revisioned, account-owned occurrence override.
  ///
  /// Returns null on ownership or revision conflict. Replaying the same
  /// mutation is idempotent and returns the already stored value.
  Future<RoutineOccurrenceOverride?> put(
    RoutineOccurrenceOverride override,
  );
}

final class FirestoreRoutineOccurrenceOverrideRepository
    implements RoutineOccurrenceOverrideRepository {
  FirestoreRoutineOccurrenceOverrideRepository({
    FirebaseFirestore? firestore,
  }) : _injectedFirestore = firestore;

  final FirebaseFirestore? _injectedFirestore;

  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _ref(String accountScopeId) =>
      _firestore
          .collection('users')
          .doc(accountScopeId)
          .collection('routineOccurrenceOverrides');

  bool _owns(String accountScopeId) =>
      AuthService.currentUserId == accountScopeId;

  @override
  Future<List<RoutineOccurrenceOverride>> listForAccount(
    String accountScopeId,
  ) async {
    if (!_owns(accountScopeId)) return const [];
    final snapshot = await _ref(accountScopeId).limit(400).get();
    return snapshot.docs
        .map((document) => _fromFirestore(document.data()))
        .where((override) => !override.tombstone)
        .toList(growable: false);
  }

  @override
  Future<RoutineOccurrenceOverride?> put(
    RoutineOccurrenceOverride override,
  ) async {
    if (!_owns(override.accountScopeId)) return null;
    final reference = _ref(override.accountScopeId).doc(override.overrideId);
    final result = await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      if (!snapshot.exists) {
        if (override.overrideRevision != 1) return null;
        transaction.set(reference, _toFirestore(override));
        return override;
      }
      final current = _fromFirestore(snapshot.data()!);
      if (current.lastMutationId == override.lastMutationId) return current;
      if (current.accountScopeId != override.accountScopeId ||
          current.overrideId != override.overrideId ||
          current.routineId != override.routineId ||
          current.sourceDateIso != override.sourceDateIso ||
          current.createdAt != override.createdAt ||
          current.tombstone ||
          override.overrideRevision != current.overrideRevision + 1 ||
          !override.updatedAt.isAfter(current.updatedAt)) {
        return null;
      }
      transaction.set(reference, _toFirestore(override));
      return override;
    });
    if (result != null) notifyRoutinesChanged();
    return result;
  }

  static Map<String, dynamic> _toFirestore(
    RoutineOccurrenceOverride override,
  ) =>
      {
        ...override.toJson(),
        'createdAt': Timestamp.fromDate(override.createdAt),
        'updatedAt': Timestamp.fromDate(override.updatedAt),
      };

  static RoutineOccurrenceOverride _fromFirestore(
    Map<String, dynamic> value,
  ) {
    final normalized = Map<String, dynamic>.of(value);
    for (final key in ['createdAt', 'updatedAt']) {
      final raw = normalized[key];
      if (raw is Timestamp) {
        normalized[key] = raw.toDate().toUtc().toIso8601String();
      }
    }
    return RoutineOccurrenceOverride.fromJson(normalized);
  }
}
