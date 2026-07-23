import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/human/human_model.dart';
import '../../models/human/human_model_persistence.dart';

abstract interface class HumanModelKeyValueStore {
  String? getString(String key);
  Future<bool> setString(String key, String value);
}

final class SharedPreferencesHumanModelStore
    implements HumanModelKeyValueStore {
  const SharedPreferencesHumanModelStore(this.preferences);

  final SharedPreferences preferences;

  @override
  String? getString(String key) => preferences.getString(key);

  @override
  Future<bool> setString(String key, String value) =>
      preferences.setString(key, value);
}

final class HumanModelLocalRepository {
  HumanModelLocalRepository(SharedPreferences preferences)
      : this.withStore(SharedPreferencesHumanModelStore(preferences));

  HumanModelLocalRepository.withStore(this._store);

  static const storageKeyPrefix = 'human_model_v1';

  final HumanModelKeyValueStore _store;

  String _key(String accountScopeId) {
    if (accountScopeId.trim().isEmpty) {
      throw const HumanModelException('invalid_account_scope_id');
    }
    return '$storageKeyPrefix:$accountScopeId';
  }

  String _backupKey(String accountScopeId) =>
      '${_key(accountScopeId)}:previous';

  Future<HumanModel?> load(String accountScopeId) async =>
      (await loadState(accountScopeId))?.model;

  Future<HumanModelLocalState?> loadState(String accountScopeId) async {
    final encoded = _store.getString(_key(accountScopeId));
    if (encoded == null) return null;
    try {
      return _decodeState(encoded, accountScopeId);
    } on HumanModelException catch (currentError) {
      final backup = _store.getString(_backupKey(accountScopeId));
      if (backup == null) rethrow;
      try {
        final recovered = _decodeState(backup, accountScopeId);
        return recovered.copyWith(
          syncStatus: currentError.code.contains('unsupported')
              ? HumanModelSyncStatus.unsupportedVersion
              : HumanModelSyncStatus.corruptedLocal,
        );
      } on Object {
        rethrow;
      }
    } on Object {
      throw const HumanModelException('invalid_human_model_json');
    }
  }

  Future<void> save(HumanModel model) => saveState(
        HumanModelLocalState(
          model: model,
          syncStatus: HumanModelSyncStatus.localOnly,
          migrationStatus: HumanModelMigrationStatus.complete,
        ),
      );

  Future<void> saveState(HumanModelLocalState state) async {
    state.model.validate();
    final key = _key(state.model.accountScopeId);
    final previous = _store.getString(key);
    if (previous != null) {
      _decodeState(previous, state.model.accountScopeId);
      if (!await _store.setString(
        _backupKey(state.model.accountScopeId),
        previous,
      )) {
        throw const HumanModelException('human_model_backup_failure');
      }
    }

    final encoded = jsonEncode(state.toJson());
    if (!await _store.setString(key, encoded)) {
      throw const HumanModelException('human_model_storage_failure');
    }
    try {
      final verified = _store.getString(key);
      if (verified == null) {
        throw const HumanModelException('human_model_storage_failure');
      }
      _decodeState(verified, state.model.accountScopeId);
    } on Object {
      if (previous != null) {
        await _store.setString(key, previous);
      }
      throw const HumanModelException('human_model_storage_failure');
    }
  }

  HumanModelLocalState _decodeState(
    String encoded,
    String accountScopeId,
  ) {
    try {
      final decoded = jsonDecode(encoded);
      final state = decoded is Map && decoded.containsKey('storageVersion')
          ? HumanModelLocalState.fromJson(decoded)
          : HumanModelLocalState(
              model: HumanModel.fromJson(decoded),
              syncStatus: HumanModelSyncStatus.localOnly,
              migrationStatus: HumanModelMigrationStatus.complete,
            );
      if (state.model.accountScopeId != accountScopeId) {
        throw const HumanModelException('human_model_scope_mismatch');
      }
      return state;
    } on HumanModelException {
      rethrow;
    } on Object {
      throw const HumanModelException('invalid_human_model_json');
    }
  }
}
