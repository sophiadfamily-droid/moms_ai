import '../models/action_autonomy_policy.dart';
import '../models/action_ledger.dart';

final class ActionUndoEvaluation {
  const ActionUndoEvaluation({
    required this.entry,
    required this.request,
    required this.policyAllowsMutation,
    required this.domainPolicyAllowsMutation,
    required this.now,
  });

  final ActionLedgerEntry entry;
  final ActionUndoRequest request;
  final bool policyAllowsMutation;
  final bool domainPolicyAllowsMutation;
  final DateTime now;
}

final class ActionUndoEngine {
  const ActionUndoEngine();

  ActionUndoResult evaluate(ActionUndoEvaluation evaluation) {
    final entry = evaluation.entry;
    final request = evaluation.request;
    final capability = entry.undoCapability;
    if (entry.accountScopeId != request.accountScopeId) {
      return ActionUndoResult(
        type: ActionUndoResultType.conflict,
        capability: capability,
        reasonCode: 'undo_account_mismatch',
      );
    }
    if (entry.status == ActionLedgerStatus.undone ||
        capability.type == ActionUndoCapabilityType.alreadyUndone) {
      return ActionUndoResult(
        type: ActionUndoResultType.alreadyUndone,
        capability: capability,
        reasonCode: 'undo_already_applied',
      );
    }
    if (request.policyMode == ActionAutonomyMode.paused ||
        !evaluation.policyAllowsMutation ||
        !evaluation.domainPolicyAllowsMutation) {
      return ActionUndoResult(
        type: ActionUndoResultType.blockedByPolicy,
        capability: capability,
        reasonCode: 'undo_policy_blocked',
      );
    }
    if (capability.deadline != null &&
        !evaluation.now.toUtc().isBefore(capability.deadline!.toUtc())) {
      return ActionUndoResult(
        type: ActionUndoResultType.expired,
        capability: capability,
        reasonCode: 'undo_expired',
      );
    }
    if (capability.type == ActionUndoCapabilityType.irreversible ||
        capability.type == ActionUndoCapabilityType.unsupportedDomain) {
      return ActionUndoResult(
        type: ActionUndoResultType.notSupported,
        capability: capability,
        reasonCode: capability.reasonCode,
      );
    }
    if (entry.resultRevision == null ||
        request.currentRevision != entry.resultRevision) {
      return ActionUndoResult(
        type: ActionUndoResultType.targetChanged,
        capability: capability,
        reasonCode: 'undo_target_changed',
      );
    }
    if (capability.confirmationRequired && !request.confirmed) {
      return ActionUndoResult(
        type: ActionUndoResultType.confirmationRequired,
        capability: capability,
        reasonCode: 'undo_confirmation_required',
      );
    }
    return ActionUndoResult(
      type: ActionUndoResultType.ready,
      capability: capability,
      reasonCode: 'undo_ready',
    );
  }
}
