import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/human/human_model.dart';

final class HumanModelLocalRepository {
  HumanModelLocalRepository(this._preferences);

  static const storageKeyPrefix = 'human_model_v1';

  final SharedPreferences _preferences;

  String _key(String accountScopeId) {
    if (accountScopeId.trim().isEmpty) {
      throw const HumanModelException('invalid_account_scope_id');
    }
    return '$storageKeyPrefix:$accountScopeId';
  }

  Future<HumanModel?> load(String accountScopeId) async {
    final encoded = _preferences.getString(_key(accountScopeId));
    if (encoded == null) return null;
    try {
      final decoded = jsonDecode(encoded);
      final model = HumanModel.fromJson(decoded);
      if (model.accountScopeId != accountScopeId) {
        throw const HumanModelException('human_model_scope_mismatch');
      }
      return model;
    } on HumanModelException {
      rethrow;
    } on Object {
      throw const HumanModelException('invalid_human_model_json');
    }
  }

  Future<void> save(HumanModel model) async {
    model.validate();
    final encoded = jsonEncode(model.toJson());
    final saved = await _preferences.setString(
      _key(model.accountScopeId),
      encoded,
    );
    if (!saved) {
      throw const HumanModelException('human_model_storage_failure');
    }
  }
}
