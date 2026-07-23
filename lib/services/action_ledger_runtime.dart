import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/action_ledger.dart';
import '../models/revisioned_sync_protocol.dart';
import '../repositories/identity/firestore_identity_read_repository.dart';
import '../repositories/identity/identity_read_repository.dart';
import 'action_ledger_reconciliation_service.dart';
import 'action_ledger_repository.dart';
import 'action_ledger_service.dart';
import 'auth_service.dart';
import 'event_action_receipt_probe.dart';
import 'human/human_model_service.dart';
import 'memory_sync_local_repository.dart';
import 'memory_lifecycle_repository.dart';
import 'revisioned_action_receipt_probe.dart';

final class ActionLedgerRuntime {
  ActionLedgerRuntime._({
    required this.ledger,
    required this.reconciliation,
  });

  final ActionLedgerService ledger;
  final ActionLedgerReconciliationService reconciliation;

  static Future<ActionLedgerRuntime> production() async {
    const local = LocalActionLedgerRepository();
    final cloud = FirestoreActionLedgerRepository(
      firestore: FirebaseFirestore.instance,
      currentUid: () => AuthService.currentUserId,
    );
    final ledger = ActionLedgerService(
      local: local,
      cloud: cloud,
      currentScope: () => AuthService.currentUserId,
    );
    final human = await HumanModelService.createProduction();
    final memory =
        MemorySyncLocalRepository(await SharedPreferences.getInstance());
    final memoryLifecycle = FirestoreMemoryLifecycleRepository();
    final identity = FirestoreIdentityReadRepository(
      firestore: FirebaseFirestore.instance,
    );
    final reconciliation = ActionLedgerReconciliationService(
      repository: local,
      ledger: ledger,
      currentScope: () => AuthService.currentUserId,
      probes: [
        const EventActionReceiptProbe(),
        const RevisionedActionReceiptProbe(
          domain: ActionLedgerDomain.task,
          syncDomain: RevisionedSyncDomain.task,
        ),
        const RevisionedActionReceiptProbe(
          domain: ActionLedgerDomain.shopping,
          syncDomain: RevisionedSyncDomain.shopping,
        ),
        const RevisionedActionReceiptProbe(
          domain: ActionLedgerDomain.profile,
          syncDomain: RevisionedSyncDomain.profile,
        ),
        CallbackActionMutationReceiptProbe(
          domain: ActionLedgerDomain.humanModel,
          observe: (entry) async {
            final state = await human.loadState(entry.accountScopeId);
            if (state?.lastMutationId == entry.mutationId) {
              return ActionMutationObservation.applied;
            }
            if (state?.pendingMutation?.mutationId == entry.mutationId) {
              return ActionMutationObservation.pending;
            }
            return ActionMutationObservation.stillUnknown;
          },
        ),
        CallbackActionMutationReceiptProbe(
          domain: ActionLedgerDomain.memory,
          observe: (entry) async {
            final state = await memory.load(entry.accountScopeId);
            if (state?.receipts.contains(entry.mutationId) ?? false) {
              return ActionMutationObservation.applied;
            }
            if (state?.conflicts
                    .any((value) => value.mutationId == entry.mutationId) ??
                false) {
              return ActionMutationObservation.conflict;
            }
            if (state?.mutations
                    .any((value) => value.mutationId == entry.mutationId) ??
                false) {
              return ActionMutationObservation.pending;
            }
            final lifecycleReceipt = await memoryLifecycle.readTechnicalReceipt(
              entry.targetReference.entityId,
            );
            if (lifecycleReceipt?.lastMutationId == entry.mutationId) {
              return ActionMutationObservation.applied;
            }
            if (lifecycleReceipt != null &&
                lifecycleReceipt.revision > entry.expectedRevision) {
              return ActionMutationObservation.conflict;
            }
            return ActionMutationObservation.stillUnknown;
          },
        ),
        CallbackActionMutationReceiptProbe(
          domain: ActionLedgerDomain.identity,
          observe: (entry) async {
            final entity = await identity.findById(
              scope: IdentityAccountScope(entry.accountScopeId),
              entityId: entry.targetReference.entityId,
            );
            return entity == null
                ? ActionMutationObservation.stillUnknown
                : ActionMutationObservation.applied;
          },
        ),
      ],
    );
    return ActionLedgerRuntime._(
      ledger: ledger,
      reconciliation: reconciliation,
    );
  }

  Future<ActionLedgerPage> bootstrap({int limit = 50}) async {
    await ledger.bootstrap(limit: limit);
    await reconciliation.reconcile(
      limit: limit > ActionLedgerReconciliationService.maxEntriesPerPass
          ? ActionLedgerReconciliationService.maxEntriesPerPass
          : limit,
    );
    return ledger.history(limit: limit);
  }
}
