import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/action_autonomy_policy.dart';
import 'package:moms_ai/services/action_autonomy_policy_service.dart';

final class _Repository implements ActionAutonomyPolicyRepository {
  final Map<String, ActionAutonomyPolicy> values = {};
  bool corrupt = false;

  @override
  Future<ActionAutonomyPolicy?> load(String accountScopeId) async {
    if (corrupt) {
      throw const ActionAutonomyPolicyException(
        'corrupted_action_autonomy_policy',
      );
    }
    return values[accountScopeId];
  }

  @override
  Future<void> save(ActionAutonomyPolicy policy) async {
    values[policy.accountScopeId] = policy;
  }
}

void main() {
  test('local policy is account scoped, reread and restrictive on corruption',
      () async {
    final repository = _Repository();
    var scope = 'a';
    final service = ActionAutonomyPolicyService(
      repository: repository,
      currentAccountScopeId: () => scope,
      now: () => DateTime.utc(2026, 7, 23),
    );
    expect((await service.load()).mode, ActionAutonomyMode.suggestions);
    expect(
      (await service.saveMode(ActionAutonomyMode.normal)).mode,
      ActionAutonomyMode.normal,
    );
    scope = 'b';
    expect((await service.load()).mode, ActionAutonomyMode.suggestions);
    repository.corrupt = true;
    expect((await service.load()).mode, ActionAutonomyMode.suggestions);
  });

  test('unauthenticated policy access is refused', () async {
    final service = ActionAutonomyPolicyService(
      repository: _Repository(),
      currentAccountScopeId: () => null,
    );
    expect(service.load, throwsA(isA<ActionAutonomyPolicyException>()));
  });
}
