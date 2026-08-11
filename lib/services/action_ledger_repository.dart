import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/action_ledger.dart';

final class ActionLedgerPage {
  const ActionLedgerPage({
    required this.entries,
    required this.hasMore,
    this.nextCursor,
  });

  final List<ActionLedgerEntry> entries;
  final bool hasMore;
  final String? nextCursor;
}

abstract interface class ActionLedgerRepository {
  Future<ActionLedgerEntry?> findByMutationId(
    String accountScopeId,
    String mutationId,
  );
  Future<ActionLedgerEntry?> findById(
    String accountScopeId,
    String ledgerEntryId,
  );
  Future<void> create(ActionLedgerEntry entry);
  Future<void> update(
    ActionLedgerEntry entry, {
    required int expectedLedgerRevision,
  });
  Future<ActionLedgerPage> page(
    String accountScopeId, {
    int limit = 30,
    String? cursor,
  });
  Future<void> importBootstrapSnapshot(ActionLedgerEntry entry);
}

final class LocalActionLedgerRepository implements ActionLedgerRepository {
  static const currentSchemaVersion = 1;
  static const maxActiveEntries = 100;
  static const maxHistoricalEntries = 400;
  static const maxEncodedBytes = 1024 * 1024;
  static const maxPageSize = 50;

  const LocalActionLedgerRepository();

  String _key(String scope) => 'action_ledger_v1:$scope';
  String _backupKey(String scope) => 'action_ledger_v1_backup:$scope';

  @override
  Future<void> importBootstrapSnapshot(ActionLedgerEntry entry) async {
    final entries = await _load(entry.accountScopeId);
    final matches =
        entries.where((value) => value.ledgerEntryId == entry.ledgerEntryId);
    if (matches.isNotEmpty &&
        matches.single.ledgerRevision >= entry.ledgerRevision) {
      return;
    }
    final mutationMatches =
        entries.where((value) => value.mutationId == entry.mutationId);
    if (mutationMatches.isNotEmpty &&
        mutationMatches.single.ledgerEntryId != entry.ledgerEntryId) {
      throw const FormatException('action_ledger_idempotency_conflict');
    }
    await _save(entry.accountScopeId, [
      for (final value in entries)
        if (value.ledgerEntryId != entry.ledgerEntryId) value,
      entry,
    ]);
  }

  @override
  Future<void> create(ActionLedgerEntry entry) async {
    final entries = await _load(entry.accountScopeId);
    final duplicateId =
        entries.where((value) => value.ledgerEntryId == entry.ledgerEntryId);
    final duplicateMutation =
        entries.where((value) => value.mutationId == entry.mutationId);
    if (duplicateId.isNotEmpty || duplicateMutation.isNotEmpty) {
      final existing = duplicateId.isNotEmpty
          ? duplicateId.single
          : duplicateMutation.single;
      if (jsonEncode(existing.toJson()) == jsonEncode(entry.toJson())) return;
      throw const FormatException('action_ledger_idempotency_conflict');
    }
    await _save(entry.accountScopeId, [...entries, entry]);
  }

  @override
  Future<void> update(
    ActionLedgerEntry entry, {
    required int expectedLedgerRevision,
  }) async {
    final entries = await _load(entry.accountScopeId);
    final matches =
        entries.where((value) => value.ledgerEntryId == entry.ledgerEntryId);
    if (matches.isEmpty ||
        matches.single.ledgerRevision != expectedLedgerRevision ||
        entry.ledgerRevision != expectedLedgerRevision + 1) {
      throw const FormatException('action_ledger_revision_conflict');
    }
    await _save(entry.accountScopeId, [
      for (final value in entries)
        if (value.ledgerEntryId == entry.ledgerEntryId) entry else value,
    ]);
  }

  @override
  Future<ActionLedgerEntry?> findById(
    String accountScopeId,
    String ledgerEntryId,
  ) async {
    final matches = (await _load(accountScopeId))
        .where((value) => value.ledgerEntryId == ledgerEntryId);
    return matches.isEmpty ? null : matches.single;
  }

  @override
  Future<ActionLedgerEntry?> findByMutationId(
    String accountScopeId,
    String mutationId,
  ) async {
    final matches = (await _load(accountScopeId))
        .where((value) => value.mutationId == mutationId);
    return matches.isEmpty ? null : matches.single;
  }

  @override
  Future<ActionLedgerPage> page(
    String accountScopeId, {
    int limit = 30,
    String? cursor,
  }) async {
    if (limit < 1 || limit > maxPageSize) {
      throw const FormatException('action_ledger_page_limit');
    }
    final ordered = await _load(accountScopeId)
      ..sort((a, b) {
        final date = b.createdAt.compareTo(a.createdAt);
        return date != 0 ? date : a.ledgerEntryId.compareTo(b.ledgerEntryId);
      });
    final cursorIndex = cursor == null
        ? null
        : ordered.indexWhere((value) => value.ledgerEntryId == cursor);
    if (cursorIndex != null && cursorIndex < 0) {
      throw const FormatException('action_ledger_cursor');
    }
    final start = cursorIndex == null ? 0 : cursorIndex + 1;
    final selected = ordered.skip(start).take(limit).toList(growable: false);
    final hasMore = start + selected.length < ordered.length;
    return ActionLedgerPage(
      entries: selected,
      hasMore: hasMore,
      nextCursor:
          hasMore && selected.isNotEmpty ? selected.last.ledgerEntryId : null,
    );
  }

  Future<List<ActionLedgerEntry>> _load(String scope) async {
    _validateScope(scope);
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key(scope));
    if (raw == null) return [];
    try {
      return _decode(raw, scope);
    } on Object {
      final backup = preferences.getString(_backupKey(scope));
      if (backup == null) {
        throw const FormatException('action_ledger_corrupted');
      }
      return _decode(backup, scope);
    }
  }

  List<ActionLedgerEntry> _decode(String raw, String scope) {
    if (utf8.encode(raw).length > maxEncodedBytes) {
      throw const FormatException('action_ledger_size');
    }
    final json = jsonDecode(raw);
    if (json is! Map ||
        json['schemaVersion'] != currentSchemaVersion ||
        json['accountScopeId'] != scope ||
        json['entries'] is! List) {
      throw const FormatException('action_ledger_corrupted');
    }
    final entries = (json['entries'] as List)
        .map(
          (value) => ActionLedgerEntry.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        )
        .toList();
    if (entries.any((entry) => entry.accountScopeId != scope) ||
        entries.length > maxActiveEntries + maxHistoricalEntries) {
      throw const FormatException('action_ledger_corrupted');
    }
    return entries;
  }

  Future<void> _save(String scope, List<ActionLedgerEntry> entries) async {
    _validateScope(scope);
    final active = entries
        .where((entry) => !_isHistorical(entry.status))
        .toList(growable: false);
    final historical = entries
        .where((entry) => _isHistorical(entry.status))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (active.length > maxActiveEntries) {
      throw const FormatException('action_ledger_active_limit');
    }
    final bounded = [
      ...active,
      ...historical.take(maxHistoricalEntries),
    ];
    final encoded = jsonEncode({
      'schemaVersion': currentSchemaVersion,
      'accountScopeId': scope,
      'entries': bounded.map((entry) => entry.toJson()).toList(),
    });
    if (utf8.encode(encoded).length > maxEncodedBytes) {
      throw const FormatException('action_ledger_size');
    }
    final preferences = await SharedPreferences.getInstance();
    final current = preferences.getString(_key(scope));
    if (current != null) {
      await preferences.setString(_backupKey(scope), current);
    }
    await preferences.setString(_key(scope), encoded);
  }

  static bool _isHistorical(ActionLedgerStatus status) => {
        ActionLedgerStatus.succeeded,
        ActionLedgerStatus.failed,
        ActionLedgerStatus.conflict,
        ActionLedgerStatus.cancelled,
        ActionLedgerStatus.expired,
        ActionLedgerStatus.blockedByPolicy,
        ActionLedgerStatus.undoAvailable,
        ActionLedgerStatus.undone,
        ActionLedgerStatus.undoConflict,
        ActionLedgerStatus.undoFailed,
        ActionLedgerStatus.notUndoable,
      }.contains(status);

  static void _validateScope(String scope) {
    if (scope.trim().isEmpty) {
      throw const FormatException('action_ledger_scope');
    }
  }
}

final class FirestoreActionLedgerRepository implements ActionLedgerRepository {
  const FirestoreActionLedgerRepository({
    required FirebaseFirestore firestore,
    required String? Function() currentUid,
  })  : _firestore = firestore,
        _currentUid = currentUid;

  final FirebaseFirestore _firestore;
  final String? Function() _currentUid;

  CollectionReference<Map<String, dynamic>> _collection(String scope) {
    if (_currentUid() != scope || scope.trim().isEmpty) {
      throw const FormatException('action_ledger_account_mismatch');
    }
    return _firestore.collection('users').doc(scope).collection('actionLedger');
  }

  @override
  Future<void> importBootstrapSnapshot(ActionLedgerEntry entry) {
    throw UnsupportedError('cloud_bootstrap_import_not_supported');
  }

  @override
  Future<void> create(ActionLedgerEntry entry) =>
      _firestore.runTransaction((transaction) async {
        final reference =
            _collection(entry.accountScopeId).doc(entry.ledgerEntryId);
        final existing = await transaction.get(reference);
        if (existing.exists) {
          final current = _fromFirestore(existing);
          if (current.mutationId == entry.mutationId) return;
          throw const FormatException('action_ledger_idempotency_conflict');
        }
        transaction.set(reference, _toFirestore(entry, create: true));
      });

  @override
  Future<void> update(
    ActionLedgerEntry entry, {
    required int expectedLedgerRevision,
  }) =>
      _firestore.runTransaction((transaction) async {
        final reference =
            _collection(entry.accountScopeId).doc(entry.ledgerEntryId);
        final snapshot = await transaction.get(reference);
        if (!snapshot.exists ||
            _fromFirestore(snapshot).ledgerRevision != expectedLedgerRevision ||
            entry.ledgerRevision != expectedLedgerRevision + 1) {
          throw const FormatException('action_ledger_revision_conflict');
        }
        transaction.set(reference, _toFirestore(entry, create: false));
      });

  @override
  Future<ActionLedgerEntry?> findById(
    String accountScopeId,
    String ledgerEntryId,
  ) async {
    final snapshot = await _collection(accountScopeId).doc(ledgerEntryId).get();
    return snapshot.exists ? _fromFirestore(snapshot) : null;
  }

  @override
  Future<ActionLedgerEntry?> findByMutationId(
    String accountScopeId,
    String mutationId,
  ) async {
    final snapshot = await _collection(accountScopeId)
        .where('mutationId', isEqualTo: mutationId)
        .limit(2)
        .get();
    if (snapshot.docs.length > 1) {
      throw const FormatException('action_ledger_duplicate_mutation');
    }
    return snapshot.docs.isEmpty ? null : _fromFirestore(snapshot.docs.single);
  }

  @override
  Future<ActionLedgerPage> page(
    String accountScopeId, {
    int limit = 30,
    String? cursor,
  }) async {
    if (limit < 1 || limit > LocalActionLedgerRepository.maxPageSize) {
      throw const FormatException('action_ledger_page_limit');
    }
    Query<Map<String, dynamic>> query = _collection(accountScopeId)
        .orderBy('createdAt', descending: true)
        .limit(limit + 1);
    if (cursor != null) {
      final cursorSnapshot =
          await _collection(accountScopeId).doc(cursor).get();
      if (!cursorSnapshot.exists) {
        throw const FormatException('action_ledger_cursor');
      }
      query = query.startAfterDocument(cursorSnapshot);
    }
    final snapshot = await query.get();
    final values = snapshot.docs.take(limit).map(_fromFirestore).toList();
    return ActionLedgerPage(
      entries: values,
      hasMore: snapshot.docs.length > limit,
      nextCursor: snapshot.docs.length > limit && values.isNotEmpty
          ? values.last.ledgerEntryId
          : null,
    );
  }

  static Map<String, Object?> _toFirestore(
    ActionLedgerEntry entry, {
    required bool create,
  }) =>
      {
        ...entry.toJson(),
        'createdAt': create ? FieldValue.serverTimestamp() : entry.createdAt,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  static ActionLedgerEntry _fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = Map<String, dynamic>.from(snapshot.data()!);
    data['ledgerEntryId'] = snapshot.id;
    for (final key in [
      'createdAt',
      'authorizedAt',
      'dispatchedAt',
      'completedAt',
      'updatedAt',
    ]) {
      if (data[key] is Timestamp) {
        data[key] = (data[key] as Timestamp).toDate().toUtc().toIso8601String();
      }
    }
    return ActionLedgerEntry.fromJson(data);
  }
}
