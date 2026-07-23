import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/action_autonomy_policy.dart';
import 'package:moms_ai/models/action_ledger.dart';
import 'package:moms_ai/screens/action_history_screen.dart';
import 'package:moms_ai/services/action_ledger_repository.dart';
import 'package:moms_ai/services/action_ledger_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const scope = 'account-a';
  final instant = DateTime.utc(2026, 7, 24, 10);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('empty history stays simple and contains no technical data',
      (tester) async {
    final service = ActionLedgerService(
      local: const LocalActionLedgerRepository(),
      currentScope: () => scope,
    );
    await tester.pumpWidget(
      MaterialApp(home: ActionHistoryScreen(ledgerService: service)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Historique des actions'), findsOneWidget);
    expect(find.text('Aucune action à afficher.'), findsOneWidget);
    expect(find.textContaining('mutationId'), findsNothing);
    expect(find.textContaining(scope), findsNothing);
  });

  testWidgets('bounded history shows safe labels and an available undo',
      (tester) async {
    const repository = LocalActionLedgerRepository();
    final entry = _entry(instant);
    await repository.create(entry);
    var requested = false;

    await tester.pumpWidget(
      MaterialApp(
        home: ActionHistoryScreen(
          ledgerService: ActionLedgerService(
            local: repository,
            currentScope: () => scope,
          ),
          onUndoRequested: (_) async => requested = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Création d’une tâche'), findsOneWidget);
    expect(find.textContaining('Tâches · Effectué'), findsOneWidget);
    expect(find.text('Annuler'), findsOneWidget);
    expect(find.textContaining(entry.mutationId), findsNothing);
    await tester.tap(find.text('Annuler'));
    await tester.pump();
    expect(requested, isTrue);
  });

  testWidgets('history remains usable on phone, tablet and text scale 1.6',
      (tester) async {
    for (final size in [const Size(360, 800), const Size(820, 1180)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
              size: size, textScaler: const TextScaler.linear(1.6)),
          child: MaterialApp(
            home: ActionHistoryScreen(
              ledgerService: ActionLedgerService(
                local: const LocalActionLedgerRepository(),
                currentScope: () => scope,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets('unsafe Event update exposes no undo control', (tester) async {
    const repository = LocalActionLedgerRepository();
    await repository.create(
      _entry(
        instant,
        actionType: ActionType.updateEvent,
        domain: ActionLedgerDomain.event,
        status: ActionLedgerStatus.notUndoable,
        capability: const ActionUndoCapability(
          type: ActionUndoCapabilityType.unsupportedDomain,
          strategy: ActionUndoStrategy.undoUpdateEvent,
          reasonCode: 'undo_event_inverse_unavailable',
          confirmationRequired: true,
          currentRevisionRequired: true,
          domain: ActionLedgerDomain.event,
          riskLevel: ActionRiskLevel.destructive,
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ActionHistoryScreen(
          ledgerService: ActionLedgerService(
            local: repository,
            currentScope: () => scope,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Annuler'), findsNothing);
    expect(find.textContaining('non disponible'), findsOneWidget);
  });
}

ActionLedgerEntry _entry(
  DateTime instant, {
  ActionType actionType = ActionType.createTask,
  ActionLedgerDomain domain = ActionLedgerDomain.task,
  ActionLedgerStatus status = ActionLedgerStatus.undoAvailable,
  ActionUndoCapability capability = const ActionUndoCapability(
    type: ActionUndoCapabilityType.conditionallyReversible,
    strategy: ActionUndoStrategy.undoCreateTask,
    reasonCode: 'undo_task_create',
    confirmationRequired: true,
    currentRevisionRequired: true,
    domain: ActionLedgerDomain.task,
    riskLevel: ActionRiskLevel.destructive,
  ),
}) =>
    ActionLedgerEntry(
      ledgerEntryId: 'ledger-mutation-1',
      accountScopeId: 'account-a',
      actionType: actionType,
      actionDomain: domain,
      actionOrigin: ActionOrigin.explicitUserRequest,
      riskLevel: ActionRiskLevel.reversibleLowRisk,
      policyModeObserved: ActionAutonomyMode.normal,
      policyVersionObserved: 1,
      mutationId: 'mutation-1',
      targetReference: ActionTargetReference(
        domain: domain,
        entityType: domain.name,
        entityId: '${domain.name}-1',
        operationType: actionType.name,
        revisionBefore: 0,
        revisionAfter: 1,
        tombstoneBefore: false,
        tombstoneAfter: false,
        patchType: 'taskCreate',
        undoStrategy: ActionUndoStrategy.undoCreateTask,
      ),
      expectedRevision: 0,
      resultRevision: 1,
      status: status,
      outcome: ActionOutcome.completed,
      createdAt: instant,
      authorizedAt: instant,
      dispatchedAt: instant,
      completedAt: instant,
      updatedAt: instant,
      undoCapability: capability,
      correlationId: 'correlation-1',
      provenance: 'test',
      ledgerRevision: 4,
      lastMutationId: 'ledger-undo',
    );
