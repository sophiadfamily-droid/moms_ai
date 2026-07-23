import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/memory_policy.dart';
import 'package:moms_ai/services/memory_policy_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final now = DateTime.utc(2026, 7, 23);

  test('stockage local est versionné et isolé par compte', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = SharedPreferencesMemoryPolicyRepository(preferences);
    final policy = MemoryPolicy(
      accountScopeId: 'account-a',
      generalMode: MemoryGeneralMode.paused,
      healthMode: MemoryHealthMode.askEveryTime,
      healthConsentGranted: false,
      changedAt: now,
      changeSource: MemoryPolicyChangeSource.explicitUserSetting,
    );
    await repository.save(policy);

    expect((await repository.load('account-a'))?.toJson(), policy.toJson());
    expect(await repository.load('account-b'), isNull);
    expect(
      preferences.getKeys(),
      contains('memory_policy_v1:account-a'),
    );
  });

  test('politique absente reste restrictive sans écriture implicite', () async {
    final repository = _MemoryPolicyRepository();
    final service = MemoryPolicyService(
      repository: repository,
      currentAccountScopeId: () => 'account-a',
      now: () => now,
    );
    final policy = await service.load();
    expect(policy.generalMode, MemoryGeneralMode.askEveryTime);
    expect(policy.healthMode, MemoryHealthMode.disabled);
    expect(repository.saved, isEmpty);
  });

  test('changement de compte ne réutilise aucune politique', () async {
    final repository = _MemoryPolicyRepository();
    var scope = 'account-a';
    final service = MemoryPolicyService(
      repository: repository,
      currentAccountScopeId: () => scope,
      now: () => now,
    );
    await service.save(
      MemoryPolicy(
        accountScopeId: 'account-a',
        generalMode: MemoryGeneralMode.automatic,
        healthMode: MemoryHealthMode.disabled,
        healthConsentGranted: false,
        changedAt: now,
        changeSource: MemoryPolicyChangeSource.explicitUserSetting,
      ),
    );
    scope = 'account-b';
    expect((await service.load()).generalMode, MemoryGeneralMode.askEveryTime);
    expect(
      () => service.save(repository.saved['account-a']!),
      throwsA(isA<MemoryPolicyException>()),
    );
  });

  test('JSON corrompu ou version future échoue sans faux succès', () async {
    SharedPreferences.setMockInitialValues({
      'memory_policy_v1:account-a': '{"schemaVersion":99}',
    });
    final repository = SharedPreferencesMemoryPolicyRepository(
      await SharedPreferences.getInstance(),
    );
    expect(
      () => repository.load('account-a'),
      throwsA(isA<MemoryPolicyException>()),
    );
  });
}

final class _MemoryPolicyRepository implements MemoryPolicyRepository {
  final Map<String, MemoryPolicy> saved = {};

  @override
  Future<MemoryPolicy?> load(String accountScopeId) async =>
      saved[accountScopeId];

  @override
  Future<void> save(MemoryPolicy policy) async {
    saved[policy.accountScopeId] = policy;
  }
}
