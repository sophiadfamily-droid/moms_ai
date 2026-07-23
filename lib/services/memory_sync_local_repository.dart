import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/memory_sync.dart';
import '../models/memory_policy.dart';

final class MemorySyncLocalState {
  static const storageVersion = 1;
  static const maxMemories = 500;
  static const maxMutations = 50;
  static const maxConflicts = 25;
  static const maxReceipts = 100;

  MemorySyncLocalState({
    required this.accountScopeId,
    this.policy,
    this.memories = const [],
    this.mutations = const [],
    this.conflicts = const [],
    this.receipts = const [],
    this.syncStatus = MemorySyncStatus.localOnly,
    this.lastBootstrapAt,
  }) {
    if (accountScopeId.trim().isEmpty ||
        memories.length > maxMemories ||
        mutations.length > maxMutations ||
        conflicts.length > maxConflicts ||
        receipts.length > maxReceipts ||
        memories.any((item) => item.accountScopeId != accountScopeId) ||
        mutations.any((item) => item.accountScopeId != accountScopeId)) {
      throw const MemorySyncException('invalid_memory_local_state');
    }
  }

  final String accountScopeId;
  final RevisionedMemoryPolicy? policy;
  final List<RevisionedMemory> memories;
  final List<MemorySyncMutation> mutations;
  final List<MemorySyncConflict> conflicts;
  final List<String> receipts;
  final MemorySyncStatus syncStatus;
  final DateTime? lastBootstrapAt;

  MemorySyncLocalState copyWith({
    RevisionedMemoryPolicy? policy,
    List<RevisionedMemory>? memories,
    List<MemorySyncMutation>? mutations,
    List<MemorySyncConflict>? conflicts,
    List<String>? receipts,
    MemorySyncStatus? syncStatus,
    DateTime? lastBootstrapAt,
  }) =>
      MemorySyncLocalState(
        accountScopeId: accountScopeId,
        policy: policy ?? this.policy,
        memories: memories ?? this.memories,
        mutations: mutations ?? this.mutations,
        conflicts: conflicts ?? this.conflicts,
        receipts: receipts ?? this.receipts,
        syncStatus: syncStatus ?? this.syncStatus,
        lastBootstrapAt: lastBootstrapAt ?? this.lastBootstrapAt,
      );

  Map<String, Object?> toJson() => {
        'storageVersion': storageVersion,
        'accountScopeId': accountScopeId,
        'policy': policy?.toJson(),
        'memories': memories.map((item) => item.toJson()).toList(),
        'mutations': mutations.map((item) => item.toJson()).toList(),
        'conflicts': conflicts.map((item) => item.toJson()).toList(),
        'receipts': receipts,
        'syncStatus': syncStatus.name,
        'lastBootstrapAt': lastBootstrapAt?.toUtc().toIso8601String(),
      };
}

final class MemorySyncLocalRepository {
  MemorySyncLocalRepository(this._preferences);

  static const keyPrefix = 'memory_sync_v1';
  final SharedPreferences _preferences;

  String _key(String scope) => '$keyPrefix:$scope';
  String _backupKey(String scope) => '${_key(scope)}:previous';

  Future<MemorySyncLocalState?> load(String scope) async {
    final encoded = _preferences.getString(_key(scope));
    if (encoded == null) return null;
    try {
      return _decode(encoded, scope);
    } on Object {
      final backup = _preferences.getString(_backupKey(scope));
      if (backup == null) rethrow;
      return _decode(backup, scope).copyWith(
        syncStatus: MemorySyncStatus.corrupted,
      );
    }
  }

  Future<void> save(MemorySyncLocalState state) async {
    final key = _key(state.accountScopeId);
    final previous = _preferences.getString(key);
    if (previous != null) {
      _decode(previous, state.accountScopeId);
      if (!await _preferences.setString(
        _backupKey(state.accountScopeId),
        previous,
      )) {
        throw const MemorySyncException('memory_local_backup_failed');
      }
    }
    final encoded = jsonEncode(state.toJson());
    if (!await _preferences.setString(key, encoded)) {
      throw const MemorySyncException('memory_local_write_failed');
    }
    try {
      _decode(_preferences.getString(key)!, state.accountScopeId);
    } on Object {
      if (previous != null) await _preferences.setString(key, previous);
      throw const MemorySyncException('memory_local_write_failed');
    }
  }

  Future<MemorySyncLocalState> enqueue(
    MemorySyncLocalState state,
    MemorySyncMutation mutation,
  ) async {
    if (state.mutations.length >= MemorySyncLocalState.maxMutations) {
      throw const MemorySyncException('memory_queue_full');
    }
    final existingIndex = state.mutations.indexWhere(
      (item) =>
          item.targetId == mutation.targetId &&
          item.state == MemoryMutationState.queued &&
          item.type == MemoryMutationType.updateMemory &&
          mutation.type == MemoryMutationType.updateMemory &&
          item.isHealth == mutation.isHealth &&
          item.expectedRevision == mutation.expectedRevision,
    );
    final queued = [...state.mutations];
    if (existingIndex >= 0) {
      final existing = queued[existingIndex];
      queued[existingIndex] = mutation.copyWith(
        patch: {...existing.patch, ...mutation.patch},
      );
    } else {
      queued.add(mutation);
    }
    queued.sort((a, b) {
      final date = a.createdAt.compareTo(b.createdAt);
      return date != 0 ? date : a.mutationId.compareTo(b.mutationId);
    });
    final next = state.copyWith(
      mutations: queued,
      syncStatus: MemorySyncStatus.pending,
    );
    await save(next);
    return next;
  }

  MemorySyncLocalState _decode(String encoded, String scope) {
    final raw = jsonDecode(encoded);
    if (raw is! Map ||
        raw['storageVersion'] != MemorySyncLocalState.storageVersion ||
        raw['accountScopeId'] != scope) {
      throw const MemorySyncException('invalid_memory_local_state');
    }
    final map = Map<String, Object?>.from(raw);
    final policyRaw = map['policy'];
    final memoriesRaw = map['memories'];
    final mutationsRaw = map['mutations'];
    final conflictsRaw = map['conflicts'];
    final receiptsRaw = map['receipts'];
    if (memoriesRaw is! List ||
        mutationsRaw is! List ||
        conflictsRaw is! List ||
        receiptsRaw is! List) {
      throw const MemorySyncException('invalid_memory_local_state');
    }
    return MemorySyncLocalState(
      accountScopeId: scope,
      policy: policyRaw is Map
          ? _policy(Map<String, Object?>.from(policyRaw), scope)
          : null,
      memories: memoriesRaw
          .map((item) => RevisionedMemory.fromJson(
                Map<String, Object?>.from(item as Map),
                expectedScope: scope,
              ))
          .toList(),
      mutations: mutationsRaw
          .map((item) => MemorySyncMutation.fromJson(
                Map<String, Object?>.from(item as Map),
              ))
          .toList(),
      conflicts: conflictsRaw
          .map((item) => MemorySyncConflict.fromJson(
                Map<String, Object?>.from(item as Map),
              ))
          .toList(),
      receipts: receiptsRaw.map((item) => item.toString()).toList(),
      syncStatus: MemorySyncStatus.values.singleWhere(
        (item) => item.name == map['syncStatus'],
      ),
      lastBootstrapAt: map['lastBootstrapAt'] == null
          ? null
          : DateTime.parse(map['lastBootstrapAt'].toString()).toUtc(),
    );
  }

  RevisionedMemoryPolicy _policy(
    Map<String, Object?> raw,
    String scope,
  ) =>
      RevisionedMemoryPolicy(
        policy: MemoryPolicy.fromJson(raw, expectedAccountScopeId: scope),
        policyRevision: raw['policyRevision'] as int,
        createdAt: DateTime.parse(raw['createdAt'].toString()).toUtc(),
        updatedAt: DateTime.parse(raw['updatedAt'].toString()).toUtc(),
        explicitHealthConsentAt: raw['explicitHealthConsentAt'] == null
            ? null
            : DateTime.parse(raw['explicitHealthConsentAt'].toString()).toUtc(),
        lastMutationId: raw['lastMutationId'].toString(),
      );
}
