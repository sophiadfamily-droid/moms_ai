import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/action_autonomy_policy.dart';
import 'package:moms_ai/screens/action_autonomy_settings_screen.dart';
import 'package:moms_ai/services/action_autonomy_policy_service.dart';

final class _Repository implements ActionAutonomyPolicyRepository {
  ActionAutonomyPolicy value = ActionAutonomyPolicy.restrictiveDefault(
    accountScopeId: 'scope-a',
    changedAt: DateTime.utc(2026, 7, 23),
  );

  @override
  Future<ActionAutonomyPolicy?> load(String accountScopeId) async => value;

  @override
  Future<void> save(ActionAutonomyPolicy policy) async => value = policy;
}

void main() {
  testWidgets('shows and persists the three modes without direct storage',
      (tester) async {
    final repository = _Repository();
    final service = ActionAutonomyPolicyService(
      repository: repository,
      currentAccountScopeId: () => 'scope-a',
      now: () => DateTime.utc(2026, 7, 23, 12),
    );
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.platformDispatcher.clearTextScaleFactorTestValue,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ActionAutonomySettingsScreen(policyService: service),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Normal'), findsOneWidget);
    expect(find.text('Suggestions uniquement'), findsOneWidget);
    expect(find.text('Actions en pause'), findsOneWidget);
    await tester.tap(find.text('Actions en pause'));
    await tester.pumpAndSettle();
    expect(repository.value.mode, ActionAutonomyMode.paused);
  });
}
