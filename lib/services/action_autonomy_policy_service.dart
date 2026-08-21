import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/action_autonomy_policy.dart';
import 'settings_context_version.dart';

abstract interface class ActionAutonomyPolicyRepository {
  Future<ActionAutonomyPolicy?> load(String accountScopeId);
  Future<void> save(ActionAutonomyPolicy policy);
}

final class SharedPreferencesActionAutonomyPolicyRepository
    implements ActionAutonomyPolicyRepository {
  const SharedPreferencesActionAutonomyPolicyRepository(this.preferences);

  final SharedPreferences preferences;

  String _key(String scope) => 'action_autonomy_policy_v1:$scope';

  @override
  Future<ActionAutonomyPolicy?> load(String accountScopeId) async {
    final raw = preferences.getString(_key(accountScopeId));
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const ActionAutonomyPolicyException(
          'corrupted_action_autonomy_policy',
        );
      }
      return ActionAutonomyPolicy.fromJson(
        Map<String, Object?>.from(decoded),
        expectedAccountScopeId: accountScopeId,
      );
    } on ActionAutonomyPolicyException {
      rethrow;
    } on Object {
      throw const ActionAutonomyPolicyException(
        'corrupted_action_autonomy_policy',
      );
    }
  }

  @override
  Future<void> save(ActionAutonomyPolicy policy) async {
    policy.validate();
    final saved = await preferences.setString(
      _key(policy.accountScopeId),
      jsonEncode(policy.toJson()),
    );
    if (!saved) {
      throw const ActionAutonomyPolicyException(
        'action_autonomy_policy_save_failed',
      );
    }
  }
}

final class ActionAutonomyPolicyService {
  const ActionAutonomyPolicyService({
    required this.repository,
    required this.currentAccountScopeId,
    this.now = DateTime.now,
  });

  final ActionAutonomyPolicyRepository repository;
  final String? Function() currentAccountScopeId;
  final DateTime Function() now;

  static Future<ActionAutonomyPolicyService> local({
    required String? Function() currentAccountScopeId,
  }) async =>
      ActionAutonomyPolicyService(
        repository: SharedPreferencesActionAutonomyPolicyRepository(
          await SharedPreferences.getInstance(),
        ),
        currentAccountScopeId: currentAccountScopeId,
      );

  Future<ActionAutonomyPolicy> load() async {
    final scope = _scope();
    try {
      return await repository.load(scope) ??
          ActionAutonomyPolicy.restrictiveDefault(
            accountScopeId: scope,
            changedAt: now(),
          );
    } on ActionAutonomyPolicyException {
      return ActionAutonomyPolicy.restrictiveDefault(
        accountScopeId: scope,
        changedAt: now(),
      );
    }
  }

  Future<ActionAutonomyPolicy> saveMode(ActionAutonomyMode mode) async {
    final scope = _scope();
    final current = await load();
    final policy = ActionAutonomyPolicy(
      mode: mode,
      changedAt: now().toUtc(),
      changeSource: ActionAutonomyChangeSource.explicitUserSetting,
      accountScopeId: scope,
      policyRevision: current.policyRevision + 1,
    );
    await repository.save(policy);
    final persisted = await repository.load(scope);
    if (persisted == null || persisted.mode != mode) {
      throw const ActionAutonomyPolicyException(
        'action_autonomy_policy_verification_failed',
      );
    }
    SettingsContextVersion.notifyChanged();
    return persisted;
  }

  String _scope() {
    final scope = currentAccountScopeId()?.trim() ?? '';
    if (scope.isEmpty) {
      throw const ActionAutonomyPolicyException(
        'action_autonomy_policy_unauthenticated',
      );
    }
    return scope;
  }
}
