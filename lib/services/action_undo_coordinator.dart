import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/identity/uuid_v7_entity_id_generator.dart';
import '../models/action_autonomy_policy.dart';
import '../models/action_ledger.dart';
import 'action_autonomy_policy_service.dart';
import 'action_ledger_repository.dart';
import 'action_ledger_service.dart';
import 'action_undo_adapters.dart';
import 'auth_service.dart';
import 'revisioned_cloud_repositories.dart';
import 'revisioned_domain_sync_service.dart';
import 'memory_library_service.dart';

final class ActionUndoCoordinator {
  ActionUndoCoordinator({
    required ActionLedgerRepository repository,
    required Future<ActionAutonomyPolicy> Function() policyLoader,
    required String? Function() currentScope,
    required Iterable<ActionUndoAdapter> adapters,
    DateTime Function()? now,
  })  : _repository = repository,
        _policyLoader = policyLoader,
        _currentScope = currentScope,
        _adapters = Map.unmodifiable({
          for (final adapter in adapters) adapter.domain: adapter,
        }),
        _now = now ?? DateTime.now;

  final ActionLedgerRepository _repository;
  final Future<ActionAutonomyPolicy> Function() _policyLoader;
  final String? Function() _currentScope;
  final Map<ActionLedgerDomain, ActionUndoAdapter> _adapters;
  final DateTime Function() _now;

  static Future<ActionUndoCoordinator> production() async {
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
    final policy = await ActionAutonomyPolicyService.local(
      currentAccountScopeId: () => AuthService.currentUserId,
    );
    final memoryLibrary = await MemoryLibraryService.production();
    return ActionUndoCoordinator(
      repository: local,
      policyLoader: policy.load,
      currentScope: () => AuthService.currentUserId,
      adapters: [
        EventActionUndoAdapter(ledger: ledger),
        TaskActionUndoAdapter(
          sync: TaskRevisionSyncService(
            cloud: const FirestoreRevisionedTaskRepository(),
          ),
          ledger: ledger,
        ),
        ShoppingActionUndoAdapter(
          sync: ShoppingRevisionSyncService(
            cloud: const FirestoreRevisionedShoppingRepository(),
          ),
          ledger: ledger,
        ),
        ProfileActionUndoAdapter(
          sync: ProfileRevisionSyncService(
            cloud: const FirestoreRevisionedProfileRepository(),
          ),
          ledger: ledger,
        ),
        MemoryActionUndoAdapter(
          library: memoryLibrary,
          ledger: ledger,
        ),
      ],
    );
  }

  Future<ActionUndoResult> request(
    String ledgerEntryId, {
    required bool confirmed,
  }) async {
    final scope = _currentScope();
    if (scope == null || scope.isEmpty) {
      throw const FormatException('action_undo_auth_required');
    }
    final entry = await _repository.findById(scope, ledgerEntryId);
    if (entry == null) {
      throw const FormatException('action_undo_entry_not_found');
    }
    if (entry.undoCapability.type != ActionUndoCapabilityType.reversible &&
        entry.undoCapability.type !=
            ActionUndoCapabilityType.conditionallyReversible) {
      return ActionUndoResult(
        type: ActionUndoResultType.notSupported,
        capability: entry.undoCapability,
        reasonCode: 'undo_capability_not_supported',
      );
    }
    final policy = await _policyLoader();
    final adapter = _adapters[entry.actionDomain];
    if (adapter == null) {
      return ActionUndoResult(
        type: ActionUndoResultType.notSupported,
        capability: entry.undoCapability,
        reasonCode: 'undo_domain_not_supported',
      );
    }
    return adapter.execute(
      source: entry,
      request: ActionUndoRequest(
        undoMutationId: const UuidV7EntityIdGenerator().generate(),
        sourceLedgerEntryId: entry.ledgerEntryId,
        accountScopeId: scope,
        currentRevision: entry.resultRevision ?? -1,
        policyMode: policy.mode,
        policyVersion: policy.schemaVersion,
        confirmed: confirmed,
        requestedAt: _now().toUtc(),
      ),
      policyAllowsMutation: policy.mode != ActionAutonomyMode.paused,
      domainPolicyAllowsMutation: true,
    );
  }
}
