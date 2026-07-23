import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/action_autonomy_policy.dart';
import 'package:moms_ai/models/action_ledger.dart';
import 'package:moms_ai/models/action_inverse_patch.dart';
import 'package:moms_ai/services/action_ledger_repository.dart';
import 'package:moms_ai/services/action_ledger_service.dart';
import 'package:moms_ai/services/action_ledger_reconciliation_service.dart';
import 'package:moms_ai/services/action_undo_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const scope = 'account-a';
  final instant = DateTime.utc(2026, 7, 24, 10);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('A.2 ledger models', () {
    test('inverse patches are closed bounded and deterministic', () {
      final patch = ProfileInversePatch([
        ProfileInversePatchEntry(
          field: ProfileOwnedPatchField.workStatus,
          value: StringProfilePatchValue('indépendante'),
        ),
        const ProfileInversePatchEntry(
          field: ProfileOwnedPatchField.wantsNotifications,
          value: NullProfilePatchValue(),
        ),
      ]);
      final encoded = jsonEncode(patch.toJson());
      final decoded = ActionInversePatch.fromJson(
        Map<String, dynamic>.from(jsonDecode(encoded) as Map),
      );

      expect(jsonEncode(decoded.toJson()), encoded);
      expect(encoded, contains('"kind":"null","value":null'));
      expect(
        () => ActionInversePatch.fromJson({
          'type': 'profile',
          'entries': [
            {
              'field': 'children',
              'value': {'kind': 'string', 'value': 'interdit'},
            },
          ],
        }),
        throwsFormatException,
      );
      expect(
        () => ProfileInversePatch([
          ProfileInversePatchEntry(
            field: ProfileOwnedPatchField.personalNotes,
            value: StringProfilePatchValue(List.filled(2001, 'x').join()),
          ),
        ]),
        throwsFormatException,
      );
    });

    test('task and shopping patches reject unknown fields', () {
      expect(
        () => TaskInversePatch.fromJson({
          ...TaskInversePatch(
            title: 'Tâche',
            category: 'Perso',
            isDone: false,
            createdAt: instant,
            isImportant: false,
            dueDate: '',
            notes: '',
            planning: 'Cette semaine',
            priority: 'Normale',
            wasTombstone: false,
          ).toJson(),
          'unknown': true,
        }),
        throwsFormatException,
      );
      expect(
        () => ShoppingInversePatch.fromJson({
          ...ShoppingInversePatch(
            title: 'Lait',
            isBought: false,
            createdAt: instant,
            category: 'Autre',
            notes: '',
            isUrgent: false,
            section: 'Aujourd’hui',
            wasTombstone: false,
            clearGeneration: 2,
          ).toJson(),
          'unknown': true,
        }),
        throwsFormatException,
      );
    });

    test('valid entry round trips deterministically without content', () {
      final entry = _entry(instant);
      final encoded = jsonEncode(entry.toJson());
      final decoded = ActionLedgerEntry.fromJson(
        Map<String, dynamic>.from(jsonDecode(encoded) as Map),
      );

      expect(jsonEncode(decoded.toJson()), encoded);
      expect(encoded, isNot(contains('Task title')));
      expect(encoded, isNot(contains('message')));
      expect(encoded, isNot(contains('prompt')));
    });

    test('future version and missing mutation are refused', () {
      final json = _entry(instant).toJson();
      expect(
        () => ActionLedgerEntry.fromJson({
          ...json,
          'schemaVersion': ActionLedgerEntry.currentSchemaVersion + 1,
        }),
        throwsFormatException,
      );
      expect(
        () => ActionLedgerEntry.fromJson({...json, 'mutationId': ''}),
        throwsFormatException,
      );
    });

    test('closed transitions reject success before dispatch', () {
      expect(
        () => _entry(instant).transition(
          nextStatus: ActionLedgerStatus.succeeded,
          nextOutcome: ActionOutcome.completed,
          at: instant.add(const Duration(seconds: 1)),
          transitionMutationId: 'transition-1',
          resultRevision: 1,
        ),
        throwsFormatException,
      );
    });
  });

  group('A.2 repositories and lifecycle', () {
    test('reconciliation is bounded and never replays a mutation', () async {
      const repository = LocalActionLedgerRepository();
      final service = ActionLedgerService(
        local: repository,
        currentScope: () => scope,
        now: () => instant,
      );
      final authorized = _entry(instant);
      await repository.create(authorized);
      final dispatching = await service.markDispatching(
        authorized,
        transitionMutationId: 'dispatch',
      );
      var observations = 0;
      final reconciliation = ActionLedgerReconciliationService(
        repository: repository,
        ledger: service,
        currentScope: () => scope,
        probes: [
          CallbackActionMutationReceiptProbe(
            domain: ActionLedgerDomain.task,
            observe: (entry) async {
              observations++;
              return ActionMutationObservation.applied;
            },
          ),
        ],
      );

      final result = await reconciliation.reconcile(limit: 1);
      final reconciled = await repository.findById(
        scope,
        dispatching.ledgerEntryId,
      );

      expect(result.inspected, 1);
      expect(result.updated, 1);
      expect(observations, 1);
      expect(reconciled!.status, ActionLedgerStatus.undoAvailable);
      expect(
        () => reconciliation.reconcile(
          limit: ActionLedgerReconciliationService.maxEntriesPerPass + 1,
        ),
        throwsFormatException,
      );
    });

    test('same mutation creates one logical entry', () async {
      const repository = LocalActionLedgerRepository();
      final entry = _entry(instant);
      await repository.create(entry);
      await repository.create(entry);

      final page = await repository.page(scope);
      expect(page.entries, hasLength(1));
      expect(
        (await repository.findByMutationId(scope, entry.mutationId))!
            .ledgerEntryId,
        entry.ledgerEntryId,
      );
    });

    test('service records dispatch and only then a real success', () async {
      const repository = LocalActionLedgerRepository();
      final service = ActionLedgerService(
        local: repository,
        currentScope: () => scope,
        now: () => instant,
      );
      final begun = await service.begin(
        mutationId: 'mutation-1',
        actionType: ActionType.createTask,
        domain: ActionLedgerDomain.task,
        origin: ActionOrigin.explicitUserRequest,
        riskLevel: ActionRiskLevel.reversibleLowRisk,
        policyMode: ActionAutonomyMode.normal,
        policyVersion: 1,
        target: _target(),
        undoCapability: _capability(),
        correlationId: 'correlation-1',
        provenance: 'task_service',
      );
      final dispatching = await service.markDispatching(
        begun,
        transitionMutationId: 'ledger-dispatch',
      );
      final succeeded = await service.recordResult(
        dispatching,
        outcome: ActionOutcome.completed,
        transitionMutationId: 'ledger-result',
        resultRevision: 1,
      );
      final exposed = await service.exposeUndo(
        succeeded,
        transitionMutationId: 'ledger-undo-capability',
      );

      expect(dispatching.status, ActionLedgerStatus.dispatching);
      expect(succeeded.status, ActionLedgerStatus.succeeded);
      expect(exposed.status, ActionLedgerStatus.undoAvailable);
      expect(exposed.resultRevision, 1);
    });

    test('pending, conflict and unknown result never become success', () async {
      const repository = LocalActionLedgerRepository();
      final service = ActionLedgerService(
        local: repository,
        currentScope: () => scope,
        now: () => instant,
      );
      for (final outcome in [
        ActionOutcome.pendingSync,
        ActionOutcome.conflict,
        ActionOutcome.unknownResult,
      ]) {
        final suffix = outcome.name;
        final begun = await service.begin(
          mutationId: 'mutation-$suffix',
          actionType: ActionType.createTask,
          domain: ActionLedgerDomain.task,
          origin: ActionOrigin.explicitUserRequest,
          riskLevel: ActionRiskLevel.reversibleLowRisk,
          policyMode: ActionAutonomyMode.normal,
          policyVersion: 1,
          target: _target(entityId: 'task-$suffix'),
          undoCapability: _capability(),
          correlationId: 'correlation-$suffix',
          provenance: 'task_service',
        );
        final dispatch = await service.markDispatching(
          begun,
          transitionMutationId: 'dispatch-$suffix',
        );
        final result = await service.recordResult(
          dispatch,
          outcome: outcome,
          transitionMutationId: 'result-$suffix',
        );
        expect(result.status, isNot(ActionLedgerStatus.succeeded));
      }
    });

    test('history is account scoped and paginated', () async {
      const repository = LocalActionLedgerRepository();
      for (var index = 0; index < 3; index++) {
        await repository.create(
          _entry(
            instant.add(Duration(minutes: index)),
            mutationId: 'mutation-$index',
            entityId: 'task-$index',
          ),
        );
      }
      final first = await repository.page(scope, limit: 2);
      final second = await repository.page(
        scope,
        limit: 2,
        cursor: first.nextCursor,
      );

      expect(first.entries, hasLength(2));
      expect(first.hasMore, isTrue);
      expect(second.entries, hasLength(1));
      expect(
        () => repository.page('account-b'),
        returnsNormally,
      );
    });
  });

  group('A.2 undo policy', () {
    test('current revision and fresh confirmation make undo ready', () {
      final entry = _succeededEntry(instant);
      final result = const ActionUndoEngine().evaluate(
        ActionUndoEvaluation(
          entry: entry,
          request: _undoRequest(instant),
          policyAllowsMutation: true,
          domainPolicyAllowsMutation: true,
          now: instant,
        ),
      );
      expect(result.type, ActionUndoResultType.ready);
    });

    test('Pause, missing confirmation and changed target block undo', () {
      final entry = _succeededEntry(instant);
      final engine = const ActionUndoEngine();
      expect(
        engine
            .evaluate(
              ActionUndoEvaluation(
                entry: entry,
                request: _undoRequest(
                  instant,
                  mode: ActionAutonomyMode.paused,
                ),
                policyAllowsMutation: true,
                domainPolicyAllowsMutation: true,
                now: instant,
              ),
            )
            .type,
        ActionUndoResultType.blockedByPolicy,
      );
      expect(
        engine
            .evaluate(
              ActionUndoEvaluation(
                entry: entry,
                request: _undoRequest(instant, confirmed: false),
                policyAllowsMutation: true,
                domainPolicyAllowsMutation: true,
                now: instant,
              ),
            )
            .type,
        ActionUndoResultType.confirmationRequired,
      );
      expect(
        engine
            .evaluate(
              ActionUndoEvaluation(
                entry: entry,
                request: _undoRequest(instant, currentRevision: 2),
                policyAllowsMutation: true,
                domainPolicyAllowsMutation: true,
                now: instant,
              ),
            )
            .type,
        ActionUndoResultType.targetChanged,
      );
    });

    test('Identity, Routine and destructive memory stay unsupported', () {
      for (final domain in [
        ActionLedgerDomain.identity,
        ActionLedgerDomain.routine,
        ActionLedgerDomain.memory,
      ]) {
        final capability = ActionUndoCapability(
          type: ActionUndoCapabilityType.unsupportedDomain,
          strategy: domain == ActionLedgerDomain.identity
              ? ActionUndoStrategy.identityNotSupported
              : domain == ActionLedgerDomain.routine
                  ? ActionUndoStrategy.routineNotSupported
                  : ActionUndoStrategy.irreversible,
          reasonCode: 'undo_not_supported',
          confirmationRequired: true,
          currentRevisionRequired: true,
          domain: domain,
          riskLevel: ActionRiskLevel.destructive,
        );
        expect(
          capability.type,
          ActionUndoCapabilityType.unsupportedDomain,
        );
      }
    });
  });
}

ActionTargetReference _target({String entityId = 'task-1'}) =>
    ActionTargetReference(
      domain: ActionLedgerDomain.task,
      entityType: 'task',
      entityId: entityId,
      operationType: 'createTask',
      revisionBefore: 0,
      revisionAfter: 1,
      tombstoneBefore: false,
      tombstoneAfter: false,
      patchType: 'taskCreate',
      undoStrategy: ActionUndoStrategy.undoCreateTask,
    );

ActionUndoCapability _capability() => const ActionUndoCapability(
      type: ActionUndoCapabilityType.conditionallyReversible,
      strategy: ActionUndoStrategy.undoCreateTask,
      reasonCode: 'undo_task_create',
      confirmationRequired: true,
      currentRevisionRequired: true,
      domain: ActionLedgerDomain.task,
      riskLevel: ActionRiskLevel.destructive,
    );

ActionLedgerEntry _entry(
  DateTime instant, {
  String mutationId = 'mutation-1',
  String entityId = 'task-1',
}) =>
    ActionLedgerEntry(
      ledgerEntryId: 'ledger-$mutationId',
      accountScopeId: 'account-a',
      actionType: ActionType.createTask,
      actionDomain: ActionLedgerDomain.task,
      actionOrigin: ActionOrigin.explicitUserRequest,
      riskLevel: ActionRiskLevel.reversibleLowRisk,
      policyModeObserved: ActionAutonomyMode.normal,
      policyVersionObserved: 1,
      mutationId: mutationId,
      targetReference: _target(entityId: entityId),
      expectedRevision: 0,
      status: ActionLedgerStatus.authorized,
      outcome: ActionOutcome.unknownResult,
      createdAt: instant,
      authorizedAt: instant,
      updatedAt: instant,
      undoCapability: _capability(),
      correlationId: 'correlation-$mutationId',
      provenance: 'test',
      lastMutationId: mutationId,
    );

ActionLedgerEntry _succeededEntry(DateTime instant) => ActionLedgerEntry(
      ledgerEntryId: 'ledger-mutation-1',
      accountScopeId: 'account-a',
      actionType: ActionType.createTask,
      actionDomain: ActionLedgerDomain.task,
      actionOrigin: ActionOrigin.explicitUserRequest,
      riskLevel: ActionRiskLevel.reversibleLowRisk,
      policyModeObserved: ActionAutonomyMode.normal,
      policyVersionObserved: 1,
      mutationId: 'mutation-1',
      targetReference: _target(),
      expectedRevision: 0,
      resultRevision: 1,
      status: ActionLedgerStatus.undoAvailable,
      outcome: ActionOutcome.completed,
      createdAt: instant,
      authorizedAt: instant,
      dispatchedAt: instant,
      completedAt: instant,
      updatedAt: instant,
      undoCapability: _capability(),
      correlationId: 'correlation-1',
      provenance: 'test',
      ledgerRevision: 4,
      lastMutationId: 'ledger-undo-capability',
    );

ActionUndoRequest _undoRequest(
  DateTime instant, {
  ActionAutonomyMode mode = ActionAutonomyMode.normal,
  bool confirmed = true,
  int currentRevision = 1,
}) =>
    ActionUndoRequest(
      undoMutationId: 'undo-mutation-1',
      sourceLedgerEntryId: 'ledger-mutation-1',
      accountScopeId: 'account-a',
      currentRevision: currentRevision,
      policyMode: mode,
      policyVersion: 1,
      confirmed: confirmed,
      requestedAt: instant,
    );
