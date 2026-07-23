import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/memory_policy.dart';

abstract interface class MemoryPolicyRepository {
  Future<MemoryPolicy?> load(String accountScopeId);
  Future<void> save(MemoryPolicy policy);
}

final class SharedPreferencesMemoryPolicyRepository
    implements MemoryPolicyRepository {
  const SharedPreferencesMemoryPolicyRepository(this.preferences);

  final SharedPreferences preferences;

  String _key(String scope) => 'memory_policy_v1:$scope';

  @override
  Future<MemoryPolicy?> load(String accountScopeId) async {
    final raw = preferences.getString(_key(accountScopeId));
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const MemoryPolicyException('invalid_memory_policy');
      }
      return MemoryPolicy.fromJson(
        Map<String, Object?>.from(decoded),
        expectedAccountScopeId: accountScopeId,
      );
    } on MemoryPolicyException {
      rethrow;
    } on Object {
      throw const MemoryPolicyException('corrupted_memory_policy');
    }
  }

  @override
  Future<void> save(MemoryPolicy policy) async {
    policy.validate();
    final saved = await preferences.setString(
      _key(policy.accountScopeId),
      jsonEncode(policy.toJson()),
    );
    if (!saved) throw const MemoryPolicyException('memory_policy_save_failed');
  }
}

final class MemoryPolicyService {
  const MemoryPolicyService({
    required this.repository,
    required this.currentAccountScopeId,
    this.now = DateTime.now,
  });

  final MemoryPolicyRepository repository;
  final String? Function() currentAccountScopeId;
  final DateTime Function() now;

  static Future<MemoryPolicyService> local({
    required String? Function() currentAccountScopeId,
  }) async =>
      MemoryPolicyService(
        repository: SharedPreferencesMemoryPolicyRepository(
          await SharedPreferences.getInstance(),
        ),
        currentAccountScopeId: currentAccountScopeId,
      );

  Future<MemoryPolicy> load() async {
    final scope = _scope();
    return await repository.load(scope) ??
        MemoryPolicy.restrictiveDefault(
          accountScopeId: scope,
          changedAt: now().toUtc(),
        );
  }

  Future<void> save(MemoryPolicy policy) async {
    final scope = _scope();
    if (policy.accountScopeId != scope) {
      throw const MemoryPolicyException('memory_policy_account_mismatch');
    }
    await repository.save(policy);
  }

  String _scope() {
    final scope = currentAccountScopeId()?.trim() ?? '';
    if (scope.isEmpty) {
      throw const MemoryPolicyException('memory_policy_unauthenticated');
    }
    return scope;
  }
}
