import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/user_profile.dart';
import 'settings_context_version.dart';

abstract interface class AppSettingsRepository {
  Future<AppSettings?> load(String accountScopeId);
  Future<void> save(AppSettings settings);
}

final class SharedPreferencesAppSettingsRepository
    implements AppSettingsRepository {
  const SharedPreferencesAppSettingsRepository(this.preferences);

  final SharedPreferences preferences;

  String _key(String scope) => 'app_settings_v1:$scope';
  String _backupKey(String scope) => '${_key(scope)}:previous';

  @override
  Future<AppSettings?> load(String accountScopeId) async {
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
  Future<void> save(AppSettings settings) async {
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
      throw const FormatException('app_settings_save_failed');
    }
    _decode(preferences.getString(key)!, settings.accountScopeId);
  }

  AppSettings _decode(String raw, String scope) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('app_settings_corrupted');
    }
    return AppSettings.fromJson(
      Map<String, Object?>.from(decoded),
      expectedAccountScopeId: scope,
    );
  }
}

final class AppSettingsService {
  const AppSettingsService({
    required this.repository,
    this.now = DateTime.now,
  });

  final AppSettingsRepository repository;
  final DateTime Function() now;

  Future<AppSettings> loadOrMigrate({
    required String accountScopeId,
    required UserProfile legacyProfile,
  }) async {
    final existing = await repository.load(accountScopeId);
    if (existing != null) return existing;
    final migrated = AppSettings.fromLegacyProfile(
      accountScopeId: accountScopeId,
      profile: legacyProfile,
      changedAt: now(),
    );
    await repository.save(migrated);
    SettingsContextVersion.notifyChanged();
    return migrated;
  }

  Future<AppSettings> saveFromCompatibilityProfile({
    required String accountScopeId,
    required UserProfile profile,
  }) async {
    final current = await repository.load(accountScopeId);
    if (current == null) {
      return loadOrMigrate(
        accountScopeId: accountScopeId,
        legacyProfile: profile,
      );
    }
    if (current.hasSameValuesAsProfile(profile)) return current;
    final updated = current.copyWith(
      automaticTravelCalculationEnabled:
          profile.automaticTravelCalculationEnabled,
      aiTone: profile.aiTone.trim(),
      planningStyle: profile.planningStyle.trim(),
      notificationLevel: profile.notificationLevel.trim(),
      spokenLanguage: profile.spokenLanguage.trim(),
      country: profile.country.trim(),
      timeZone: profile.timeZone.trim(),
      changedAt: now(),
      source: AppSettingsSource.explicitUserSetting,
      revision: current.revision + 1,
    );
    await repository.save(updated);
    SettingsContextVersion.notifyChanged();
    return updated;
  }
}
