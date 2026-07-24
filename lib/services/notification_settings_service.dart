import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/local_notification_models.dart';

abstract interface class NotificationSettingsRepository {
  Future<NotificationSettings?> load(String accountScopeId);
  Future<void> save(NotificationSettings settings);
}

final class SharedPreferencesNotificationSettingsRepository
    implements NotificationSettingsRepository {
  const SharedPreferencesNotificationSettingsRepository(this.preferences);

  final SharedPreferences preferences;

  String _key(String scope) => 'notification_settings_v1:$scope';
  String _backupKey(String scope) => '${_key(scope)}:previous';

  @override
  Future<NotificationSettings?> load(String accountScopeId) async {
    final current = preferences.getString(_key(accountScopeId));
    if (current == null) return null;
    try {
      return _decode(current, accountScopeId);
    } on Object {
      final backup = preferences.getString(_backupKey(accountScopeId));
      if (backup == null) rethrow;
      return _decode(backup, accountScopeId);
    }
  }

  @override
  Future<void> save(NotificationSettings settings) async {
    settings.validate();
    final key = _key(settings.accountScopeId);
    final previous = preferences.getString(key);
    if (previous != null) {
      _decode(previous, settings.accountScopeId);
      await preferences.setString(
          _backupKey(settings.accountScopeId), previous);
    }
    final encoded = jsonEncode(settings.toJson());
    if (!await preferences.setString(key, encoded)) {
      throw const FormatException('notification_settings_save_failed');
    }
    _decode(preferences.getString(key)!, settings.accountScopeId);
  }

  NotificationSettings _decode(String raw, String scope) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('notification_settings_corrupted');
    }
    return NotificationSettings.fromJson(
      Map<String, Object?>.from(decoded),
      expectedAccountScopeId: scope,
    );
  }
}

final class NotificationSettingsService {
  const NotificationSettingsService({
    required this.repository,
    required this.currentAccountScopeId,
    required this.currentTimezoneId,
    this.now = DateTime.now,
  });

  final NotificationSettingsRepository repository;
  final String? Function() currentAccountScopeId;
  final Future<String> Function() currentTimezoneId;
  final DateTime Function() now;

  Future<NotificationSettings> load() async {
    final scope = _scope();
    try {
      return await repository.load(scope) ??
          NotificationSettings.restrictiveDefault(
            accountScopeId: scope,
            timezoneId: await currentTimezoneId(),
            changedAt: now(),
          );
    } on Object {
      return NotificationSettings.restrictiveDefault(
        accountScopeId: scope,
        timezoneId: await currentTimezoneId(),
        changedAt: now(),
      );
    }
  }

  Future<NotificationSettings> save({
    required bool enabled,
    required bool permissionPromptExplained,
    required bool soundEnabled,
    required bool vibrationEnabled,
    required bool badgeEnabled,
  }) async {
    final current = await load();
    final updated = current.copyWith(
      enabled: enabled,
      permissionPromptExplained: permissionPromptExplained,
      privacyMode: NotificationPrivacyMode.genericOnly,
      soundEnabled: soundEnabled,
      vibrationEnabled: vibrationEnabled,
      badgeEnabled: badgeEnabled,
      timezoneId: await currentTimezoneId(),
      changedAt: now().toUtc(),
      source: NotificationSettingsSource.explicitUserSetting,
      policyRevision: current.policyRevision + 1,
    );
    await repository.save(updated);
    return await repository.load(updated.accountScopeId) ?? updated;
  }

  String _scope() {
    final scope = currentAccountScopeId();
    if (scope == null || scope.trim().isEmpty) {
      throw const FormatException('notification_auth_required');
    }
    return scope;
  }
}
