import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/proactive_notification_policy.dart';

abstract interface class ProactiveNotificationPolicyRepository {
  Future<ProactiveNotificationPolicy?> load(String accountScopeId);
  Future<void> save(ProactiveNotificationPolicy policy);
}

final class SharedPreferencesProactiveNotificationPolicyRepository
    implements ProactiveNotificationPolicyRepository {
  const SharedPreferencesProactiveNotificationPolicyRepository(
    this.preferences,
  );

  final SharedPreferences preferences;

  String _key(String scope) => 'proactive_notification_policy_v1:$scope';
  String _backupKey(String scope) => '${_key(scope)}:previous';

  @override
  Future<ProactiveNotificationPolicy?> load(String accountScopeId) async {
    final raw = preferences.getString(_key(accountScopeId));
    if (raw == null) return null;
    try {
      return _decode(raw, accountScopeId);
    } on Object {
      final backup = preferences.getString(_backupKey(accountScopeId));
      if (backup == null) rethrow;
      return _decode(backup, accountScopeId);
    }
  }

  @override
  Future<void> save(ProactiveNotificationPolicy policy) async {
    policy.validate();
    final key = _key(policy.accountScopeId);
    final previous = preferences.getString(key);
    if (previous != null) {
      _decode(previous, policy.accountScopeId);
      if (!await preferences.setString(
          _backupKey(policy.accountScopeId), previous)) {
        throw const FormatException('proactive_policy_backup_failed');
      }
    }
    final encoded = jsonEncode(policy.toJson());
    if (!await preferences.setString(key, encoded)) {
      throw const FormatException('proactive_policy_save_failed');
    }
    _decode(preferences.getString(key)!, policy.accountScopeId);
  }

  ProactiveNotificationPolicy _decode(String raw, String scope) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('proactive_policy_corrupted');
    }
    return ProactiveNotificationPolicy.fromJson(
      Map<String, Object?>.from(decoded),
      expectedAccountScopeId: scope,
    );
  }
}

final class ProactiveNotificationPolicyService {
  const ProactiveNotificationPolicyService({
    required this.repository,
    required this.currentAccountScopeId,
    required this.currentTimezoneId,
    this.now = DateTime.now,
  });

  final ProactiveNotificationPolicyRepository repository;
  final String? Function() currentAccountScopeId;
  final Future<String> Function() currentTimezoneId;
  final DateTime Function() now;

  Future<ProactiveNotificationPolicy> load() async {
    final scope = _scope();
    try {
      return await repository.load(scope) ?? await _restrictive(scope);
    } on Object {
      return _restrictive(scope);
    }
  }

  Future<ProactiveNotificationPolicy> save(
    ProactiveNotificationPolicy policy,
  ) async {
    final scope = _scope();
    if (policy.accountScopeId != scope) {
      throw const FormatException('proactive_policy_account_mismatch');
    }
    final current = await load();
    if (policy.policyRevision != current.policyRevision + 1 ||
        policy.changeSource !=
            ProactivePolicyChangeSource.explicitUserSetting) {
      throw const FormatException('proactive_policy_revision_invalid');
    }
    policy.validate();
    await repository.save(policy);
    final saved = await repository.load(scope);
    if (saved == null || saved.policyRevision != policy.policyRevision) {
      throw const FormatException('proactive_policy_readback_failed');
    }
    return saved;
  }

  Future<ProactiveNotificationPolicy> update(
    ProactiveNotificationPolicy Function(
      ProactiveNotificationPolicy current,
      DateTime changedAt,
      String timezoneId,
    ) transform,
  ) async {
    final current = await load();
    final updated = transform(
      current,
      now().toUtc(),
      await currentTimezoneId(),
    );
    return save(updated);
  }

  Future<ProactiveNotificationPolicy> _restrictive(String scope) async =>
      ProactiveNotificationPolicy.restrictiveDefault(
        accountScopeId: scope,
        timezoneId: await currentTimezoneId(),
        changedAt: now(),
      );

  String _scope() {
    final scope = currentAccountScopeId();
    if (scope == null || scope.trim().isEmpty) {
      throw const FormatException('proactive_policy_auth_required');
    }
    return scope;
  }
}
