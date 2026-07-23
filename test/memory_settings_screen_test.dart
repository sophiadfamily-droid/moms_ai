import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/memory_policy.dart';
import 'package:moms_ai/screens/memory_settings_screen.dart';
import 'package:moms_ai/services/memory_policy_service.dart';

void main() {
  final now = DateTime.utc(2026, 7, 23);

  testWidgets('affiche les modes généraux et santé séparés', (tester) async {
    final repository = _Repository(
      MemoryPolicy.restrictiveDefault(
        accountScopeId: 'account-a',
        changedAt: now,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MemorySettingsScreen(
          policyService: MemoryPolicyService(
            repository: repository,
            currentAccountScopeId: () => 'account-a',
            now: () => now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Automatique'), findsOneWidget);
    expect(find.text('En pause'), findsOneWidget);
    expect(find.text('Ne pas mémoriser'), findsOneWidget);
    expect(find.text('Autoriser la mémorisation'), findsOneWidget);
    expect(find.textContaining('aucun diagnostic médical'), findsOneWidget);
  });

  testWidgets('enregistre pause et consentement santé explicitement',
      (tester) async {
    final repository = _Repository(
      MemoryPolicy.restrictiveDefault(
        accountScopeId: 'account-a',
        changedAt: now,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MemorySettingsScreen(
          policyService: MemoryPolicyService(
            repository: repository,
            currentAccountScopeId: () => 'account-a',
            now: () => now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('En pause'));
    await tester.scrollUntilVisible(
      find.text('Autoriser la mémorisation'),
      250,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Autoriser la mémorisation'));
    await tester.scrollUntilVisible(find.text('Enregistrer'), 250);
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    expect(repository.policy.generalMode, MemoryGeneralMode.paused);
    expect(repository.policy.healthMode, MemoryHealthMode.enabled);
    expect(repository.policy.healthConsentGranted, true);
    expect(find.text('Réglages de mémoire enregistrés.'), findsOneWidget);
  });

  testWidgets('reste utilisable sur téléphone et tablette', (tester) async {
    for (final size in const [Size(360, 800), Size(820, 1180)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      final repository = _Repository(
        MemoryPolicy.restrictiveDefault(
          accountScopeId: 'account-a',
          changedAt: now,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: const TextScaler.linear(1.4),
            ),
            child: MemorySettingsScreen(
              policyService: MemoryPolicyService(
                repository: repository,
                currentAccountScopeId: () => 'account-a',
                now: () => now,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('Enregistrer'), 250);
      expect(find.text('Enregistrer'), findsOneWidget);
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });
}

final class _Repository implements MemoryPolicyRepository {
  _Repository(this.policy);

  MemoryPolicy policy;

  @override
  Future<MemoryPolicy?> load(String accountScopeId) async => policy;

  @override
  Future<void> save(MemoryPolicy policy) async {
    this.policy = policy;
  }
}
