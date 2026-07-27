import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/priority/proactive_priority_models.dart';

abstract interface class ProactiveSuggestionHistoryRepository {
  Future<List<ProactiveSuggestionReceipt>> load(String accountScopeId);
  Future<void> save(
    String accountScopeId,
    List<ProactiveSuggestionReceipt> receipts,
  );
}

final class SharedPreferencesProactiveSuggestionHistoryRepository
    implements ProactiveSuggestionHistoryRepository {
  const SharedPreferencesProactiveSuggestionHistoryRepository(
    this.preferences,
  );

  static const maximumReceipts = 128;
  final SharedPreferences preferences;

  String _key(String scope) => 'proactive_priority_history_v1:$scope';
  String _backupKey(String scope) => '${_key(scope)}:previous';

  @override
  Future<List<ProactiveSuggestionReceipt>> load(String accountScopeId) async {
    final scope = accountScopeId.trim();
    if (scope.isEmpty) {
      throw const FormatException('proactive_priority_scope_required');
    }
    final raw = preferences.getString(_key(scope));
    if (raw == null) return const [];
    try {
      return _decode(raw, scope);
    } on Object {
      final backup = preferences.getString(_backupKey(scope));
      if (backup == null) rethrow;
      return _decode(backup, scope);
    }
  }

  @override
  Future<void> save(
    String accountScopeId,
    List<ProactiveSuggestionReceipt> receipts,
  ) async {
    final scope = accountScopeId.trim();
    if (scope.isEmpty || receipts.length > maximumReceipts) {
      throw const FormatException('proactive_priority_history_invalid');
    }
    final key = _key(scope);
    final previous = preferences.getString(key);
    if (previous != null) {
      _decode(previous, scope);
      await preferences.setString(_backupKey(scope), previous);
    }
    final encoded = jsonEncode({
      'schemaVersion': 1,
      'accountScopeId': scope,
      'receipts': receipts.map((value) => value.toJson()).toList(),
    });
    if (!await preferences.setString(key, encoded)) {
      throw const FormatException('proactive_priority_history_save_failed');
    }
    _decode(preferences.getString(key)!, scope);
  }

  List<ProactiveSuggestionReceipt> _decode(String raw, String scope) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map ||
        decoded['schemaVersion'] != 1 ||
        decoded['accountScopeId'] != scope ||
        decoded['receipts'] is! List ||
        (decoded['receipts'] as List).length > maximumReceipts) {
      throw const FormatException('proactive_priority_history_corrupted');
    }
    return (decoded['receipts'] as List)
        .map(
          (value) => ProactiveSuggestionReceipt.fromJson(
            Map<String, Object?>.from(value as Map),
          ),
        )
        .toList(growable: false);
  }
}
