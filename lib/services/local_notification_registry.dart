import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/local_notification_models.dart';

abstract interface class LocalNotificationRegistry {
  Future<NotificationRegistryState> load(String accountScopeId);
  Future<void> save(NotificationRegistryState state);
}

final class SharedPreferencesLocalNotificationRegistry
    implements LocalNotificationRegistry {
  const SharedPreferencesLocalNotificationRegistry(this.preferences);

  final SharedPreferences preferences;

  String _key(String scope) => 'local_notification_registry_v1:$scope';
  String _backupKey(String scope) => '${_key(scope)}:previous';

  @override
  Future<NotificationRegistryState> load(String accountScopeId) async {
    final raw = preferences.getString(_key(accountScopeId));
    if (raw == null) {
      return NotificationRegistryState(
        accountScopeId: accountScopeId,
        entries: const [],
      );
    }
    try {
      return _decode(raw, accountScopeId);
    } on Object {
      final backup = preferences.getString(_backupKey(accountScopeId));
      if (backup == null) {
        return NotificationRegistryState(
          accountScopeId: accountScopeId,
          entries: const [],
        );
      }
      return _decode(backup, accountScopeId);
    }
  }

  @override
  Future<void> save(NotificationRegistryState state) async {
    final key = _key(state.accountScopeId);
    final previous = preferences.getString(key);
    if (previous != null) {
      _decode(previous, state.accountScopeId);
      await preferences.setString(_backupKey(state.accountScopeId), previous);
    }
    final encoded = jsonEncode({
      'schemaVersion': state.schemaVersion,
      'accountScopeId': state.accountScopeId,
      'entries': state.entries.map((item) => item.toJson()).toList(),
    });
    if (!await preferences.setString(key, encoded)) {
      throw const FormatException('notification_registry_save_failed');
    }
    _decode(preferences.getString(key)!, state.accountScopeId);
  }

  NotificationRegistryState _decode(String raw, String scope) {
    final decoded = jsonDecode(raw);
    const keys = {'schemaVersion', 'accountScopeId', 'entries'};
    if (decoded is! Map ||
        decoded.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(decoded.keys.toSet()).isNotEmpty ||
        decoded['schemaVersion'] !=
            NotificationRegistryState.currentSchemaVersion ||
        decoded['accountScopeId'] != scope ||
        decoded['entries'] is! List) {
      throw const FormatException('notification_registry_corrupted');
    }
    return NotificationRegistryState(
      accountScopeId: scope,
      entries: (decoded['entries'] as List)
          .map(
            (item) => LocalNotificationRequest.fromJson(
              Map<String, Object?>.from(item as Map),
              expectedAccountScopeId: scope,
            ),
          )
          .toList(growable: false),
    );
  }
}
