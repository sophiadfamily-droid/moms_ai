import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/revisioned_domain_models.dart';
import '../models/revisioned_sync_protocol.dart';
import '../models/shopping_item_model.dart';
import '../models/task_model.dart';
import '../models/user_profile.dart';

final class RevisionedJournalState {
  static const currentSchemaVersion = 1;
  static const maxMutations = 200;
  static const maxReceipts = 200;
  static const maxConflicts = 100;
  static const maxEncodedBytes = 512 * 1024;
  static const maxAttempts = 5;

  RevisionedJournalState({
    this.schemaVersion = currentSchemaVersion,
    required this.accountScopeId,
    required this.domain,
    this.mutations = const [],
    this.receipts = const [],
    this.conflicts = const [],
  }) {
    if (schemaVersion != currentSchemaVersion ||
        accountScopeId.trim().isEmpty ||
        mutations.length > maxMutations ||
        receipts.length > maxReceipts ||
        conflicts.length > maxConflicts ||
        mutations.any((mutation) =>
            mutation.domain != domain ||
            mutation.attempt < 0 ||
            mutation.attempt > maxAttempts)) {
      throw const FormatException('invalid_revisioned_journal');
    }
  }

  final int schemaVersion;
  final String accountScopeId;
  final RevisionedSyncDomain domain;
  final List<RevisionedDomainMutation> mutations;
  final List<String> receipts;
  final List<RevisionedConflict> conflicts;

  RevisionedJournalState copyWith({
    List<RevisionedDomainMutation>? mutations,
    List<String>? receipts,
    List<RevisionedConflict>? conflicts,
  }) =>
      RevisionedJournalState(
        accountScopeId: accountScopeId,
        domain: domain,
        mutations: mutations ?? this.mutations,
        receipts: receipts ?? this.receipts,
        conflicts: conflicts ?? this.conflicts,
      );

  Map<String, Object> toJson() => {
        'schemaVersion': schemaVersion,
        'accountScopeId': accountScopeId,
        'domain': domain.name,
        'mutations': mutations.map(_mutationToJson).toList(growable: false),
        'receipts': receipts,
        'conflicts': conflicts
            .map((conflict) => conflict.toJson())
            .toList(growable: false),
      };

  factory RevisionedJournalState.fromJson(Map<String, dynamic> json) =>
      RevisionedJournalState(
        schemaVersion: json['schemaVersion'] as int? ?? -1,
        accountScopeId: json['accountScopeId'] as String? ?? '',
        domain: RevisionedSyncDomain.values.singleWhere(
          (value) => value.name == json['domain'],
        ),
        mutations: (json['mutations'] as List<dynamic>)
            .map(
              (value) => _mutationFromJson(
                Map<String, dynamic>.from(value as Map),
              ),
            )
            .toList(growable: false),
        receipts: (json['receipts'] as List<dynamic>)
            .map((value) => value as String)
            .toList(growable: false),
        conflicts: (json['conflicts'] as List<dynamic>)
            .map(
              (value) => RevisionedConflict.fromJson(
                Map<String, dynamic>.from(value as Map),
              ),
            )
            .toList(growable: false),
      );

  static Map<String, Object?> _mutationToJson(
    RevisionedDomainMutation mutation,
  ) {
    final base = <String, Object?>{
      'mutationId': mutation.mutationId,
      'targetId': mutation.targetId,
      'expectedRevision': mutation.expectedRevision,
      'createdAt': mutation.createdAt.toUtc().toIso8601String(),
      'attempt': mutation.attempt,
      'nextRetryAt': mutation.nextRetryAt?.toUtc().toIso8601String(),
      'state': mutation.state.name,
      'domain': mutation.domain.name,
      if (mutation.actionReference != null)
        'actionReference': mutation.actionReference!.toJson(),
    };
    return switch (mutation) {
      TaskMutation() => {
          ...base,
          'type': mutation.type.name,
          'payload': mutation.task.toJson(),
        },
      ShoppingMutation() => {
          ...base,
          'type': mutation.type.name,
          'payload': mutation.item.toJson(),
          'clearGeneration': mutation.clearGeneration,
        },
      ProfileMutation() => {
          ...base,
          'type': mutation.type.name,
          'changedFields': mutation.changedFields.toList()..sort(),
          'payload': ProfileFieldOwnership.ownedPayload(mutation.profile),
        },
    };
  }

  static RevisionedDomainMutation _mutationFromJson(
    Map<String, dynamic> json,
  ) {
    final domain = RevisionedSyncDomain.values.singleWhere(
      (value) => value.name == json['domain'],
    );
    final actionJson = json['actionReference'];
    final actionReference = actionJson is Map
        ? RevisionedActionReference(
            actionType: actionJson['actionType'] as String,
            pendingActionId: actionJson['pendingActionId'] as String?,
            policyMode: actionJson['policyMode'] as String,
            policyVersion: actionJson['policyVersion'] as int,
            sessionGeneration: actionJson['sessionGeneration'] as int,
            origin: actionJson['origin'] as String,
          )
        : null;
    final mutationId = json['mutationId'] as String? ?? '';
    final targetId = json['targetId'] as String? ?? '';
    final expectedRevision = json['expectedRevision'] as int? ?? -1;
    final createdAt = DateTime.parse(json['createdAt'] as String);
    final attempt = json['attempt'] as int? ?? -1;
    final nextRetryRaw = json['nextRetryAt'] as String?;
    final nextRetryAt =
        nextRetryRaw == null ? null : DateTime.parse(nextRetryRaw);
    final state = RevisionedMutationState.values.singleWhere(
      (value) => value.name == json['state'],
    );
    final payload = Map<String, dynamic>.from(json['payload'] as Map);
    return switch (domain) {
      RevisionedSyncDomain.task => TaskMutation(
          mutationId: mutationId,
          targetId: targetId,
          expectedRevision: expectedRevision,
          createdAt: createdAt,
          attempt: attempt,
          nextRetryAt: nextRetryAt,
          state: state,
          actionReference: actionReference,
          type: TaskMutationType.values.singleWhere(
            (value) => value.name == json['type'],
          ),
          task: TaskModel.fromJson(payload),
        ),
      RevisionedSyncDomain.shopping => ShoppingMutation(
          mutationId: mutationId,
          targetId: targetId,
          expectedRevision: expectedRevision,
          createdAt: createdAt,
          attempt: attempt,
          nextRetryAt: nextRetryAt,
          state: state,
          actionReference: actionReference,
          type: ShoppingMutationType.values.singleWhere(
            (value) => value.name == json['type'],
          ),
          item: ShoppingItemModel.fromJson(payload),
          clearGeneration: json['clearGeneration'] as int? ?? 0,
        ),
      RevisionedSyncDomain.profile => ProfileMutation(
          mutationId: mutationId,
          targetId: targetId,
          expectedRevision: expectedRevision,
          createdAt: createdAt,
          attempt: attempt,
          nextRetryAt: nextRetryAt,
          state: state,
          actionReference: actionReference,
          type: ProfileMutationType.values.singleWhere(
            (value) => value.name == json['type'],
          ),
          changedFields: (json['changedFields'] as List<dynamic>)
              .map((value) => value as String)
              .toSet(),
          profile: UserProfile.fromJson(payload),
        ),
    };
  }
}

final class RevisionedOfflineJournal {
  const RevisionedOfflineJournal();

  String _key(String scope, RevisionedSyncDomain domain) =>
      'zelia_y1_${domain.name}_journal_v1:$scope';

  String _backupKey(String scope, RevisionedSyncDomain domain) =>
      '${_key(scope, domain)}:backup';

  Future<RevisionedJournalState> load({
    required String accountScopeId,
    required RevisionedSyncDomain domain,
  }) async {
    _validateScope(accountScopeId);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(accountScopeId, domain));
    if (raw == null) {
      return RevisionedJournalState(
        accountScopeId: accountScopeId,
        domain: domain,
      );
    }
    try {
      return _decode(raw, accountScopeId, domain);
    } on Object {
      final backup = prefs.getString(_backupKey(accountScopeId, domain));
      if (backup == null) {
        throw const FormatException('revisioned_journal_corrupted');
      }
      return _decode(backup, accountScopeId, domain);
    }
  }

  Future<void> save(RevisionedJournalState state) async {
    final encoded = jsonEncode(state.toJson());
    if (utf8.encode(encoded).length > RevisionedJournalState.maxEncodedBytes) {
      throw const FormatException('revisioned_journal_size_exceeded');
    }
    final prefs = await SharedPreferences.getInstance();
    final key = _key(state.accountScopeId, state.domain);
    final previous = prefs.getString(key);
    if (previous != null) {
      await prefs.setString(
        _backupKey(state.accountScopeId, state.domain),
        previous,
      );
    }
    await prefs.setString(key, encoded);
    _decode(
      prefs.getString(key)!,
      state.accountScopeId,
      state.domain,
    );
  }

  Future<RevisionedJournalState> enqueue({
    required String accountScopeId,
    required RevisionedSyncDomain domain,
    required RevisionedDomainMutation mutation,
  }) async {
    final current = await load(accountScopeId: accountScopeId, domain: domain);
    if (current.receipts.contains(mutation.mutationId) ||
        current.mutations.any(
          (existing) => existing.mutationId == mutation.mutationId,
        )) {
      return current;
    }
    if (current.mutations.length >= RevisionedJournalState.maxMutations) {
      throw const FormatException('revisioned_journal_limit_reached');
    }
    final updated = current.copyWith(
      mutations: [...current.mutations, mutation],
    );
    await save(updated);
    return updated;
  }

  Future<void> replace(RevisionedJournalState state) => save(state);

  RevisionedJournalState _decode(
    String raw,
    String scope,
    RevisionedSyncDomain domain,
  ) {
    final decoded = RevisionedJournalState.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    );
    if (decoded.accountScopeId != scope || decoded.domain != domain) {
      throw const FormatException('revisioned_journal_scope_mismatch');
    }
    return decoded;
  }

  void _validateScope(String scope) {
    if (scope.trim().isEmpty) {
      throw const FormatException('revisioned_journal_scope_required');
    }
  }
}
