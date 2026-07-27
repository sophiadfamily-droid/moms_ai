import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/life_context/life_context_domains.dart';
import 'package:moms_ai/models/life_context/life_context_projection.dart';
import 'package:moms_ai/models/priority/proactive_priority_models.dart';
import 'package:moms_ai/screens/tasks_screen.dart';
import 'package:moms_ai/services/priority/proactive_interaction_registry.dart';
import 'package:moms_ai/services/priority/proactive_priority_service.dart';
import 'package:moms_ai/services/priority/proactive_suggestion_history_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const diagnosticsEnabled = bool.fromEnvironment(
    'ZELIA_PRIORITY_DIAGNOSTICS',
  );
  testWidgets('QA panel reads the production service and registry instances',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime(2026, 7, 27, 10);
    final registry = ProactiveInteractionRegistry();
    final service = ProactivePriorityService(
      accountScopeId: 'account',
      loadProjection: () async => _projection(now),
      history: _History(),
      clock: () => now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TasksScreen(
          proactivePriorityService: service,
          proactiveInteractionRegistry: registry,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('proactive-priority-diagnostic-panel')),
      findsOneWidget,
    );
    expect(find.textContaining('buildMarker=qa-widget'), findsOneWidget);
    expect(
      find.textContaining(registry.diagnosticInstanceIdentifier),
      findsOneWidget,
    );
    expect(service.lastEvaluationSnapshot, isNotNull);
    expect(
      service.lastEvaluationSnapshot!.registryInstanceIdentifier,
      registry.diagnosticInstanceIdentifier,
    );
    expect(
      service.lastEvaluationSnapshot!.sectionAvailabilityCodes,
      contains('relation:available'),
    );
    expect(service.lastEvaluationSnapshot!.blockingSections, isEmpty);
    expect(
      service.lastEvaluationSnapshot!.projectionStateReasonCodes,
      isEmpty,
    );

    final generation = service.lastEvaluationSnapshot!.evaluationGeneration;
    final reevaluate = find.text('Réévaluer maintenant');
    await tester.ensureVisible(reevaluate);
    await tester.tap(reevaluate);
    await tester.pumpAndSettle();
    expect(
      service.lastEvaluationSnapshot!.evaluationGeneration,
      greaterThan(generation),
    );
  }, skip: !diagnosticsEnabled);

  testWidgets('QA panel is absent when diagnostics are not compiled in',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MaterialApp(home: TasksScreen()),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('proactive-priority-diagnostic-panel')),
      findsNothing,
    );
  }, skip: diagnosticsEnabled);
}

LifeContextProjection _projection(DateTime now) => LifeContextProjection(
      projectionId: 'projection',
      sourceSnapshotId: 'snapshot',
      accountScopeId: 'account',
      purpose: LifeContextConsumerPurpose.conversation,
      generatedAt: now.toUtc(),
      state: LifeContextProjectionState.complete,
      budgetRequested: 100,
      budgetUsed: 0,
      sections: [
        LifeContextProjectionSection(
          type: LifeContextProjectionSectionType.relation,
          availability: LifeContextAvailability.available,
          freshness: LifeContextFreshness.current,
          items: [],
          budgetLimit: 10,
          budgetUsed: 0,
          omittedCount: 0,
          truncated: false,
        ),
      ],
      omittedCount: 0,
      warningCodes: const [],
    );

final class _History implements ProactiveSuggestionHistoryRepository {
  @override
  Future<List<ProactiveSuggestionReceipt>> load(String accountScopeId) async =>
      const [];

  @override
  Future<void> save(
    String accountScopeId,
    List<ProactiveSuggestionReceipt> receipts,
  ) async {}
}
