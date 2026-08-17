import '../models/structured_schedule_import.dart';

enum StructuredScheduleApplicationStatus {
  applied,
  alreadyApplied,
  invalidReview,
  scopeMismatch,
  unavailable,
}

final class StructuredScheduleApplicationResult {
  const StructuredScheduleApplicationResult(this.status);

  final StructuredScheduleApplicationStatus status;

  bool get isSuccess =>
      status == StructuredScheduleApplicationStatus.applied ||
      status == StructuredScheduleApplicationStatus.alreadyApplied;
}

final class StructuredScheduleApplicationBatch {
  StructuredScheduleApplicationBatch({
    required this.importId,
    required this.accountScopeId,
    required List<StructuredScheduleProposal> proposals,
  }) : proposals = List.unmodifiable(proposals) {
    if (importId.trim().isEmpty ||
        accountScopeId.trim().isEmpty ||
        this.proposals.isEmpty ||
        this
            .proposals
            .any((proposal) => !proposal.isComplete || !proposal.isKept)) {
      throw const StructuredScheduleImportException(
        'invalid_schedule_application_batch',
      );
    }
  }

  final String importId;
  final String accountScopeId;
  final List<StructuredScheduleProposal> proposals;
}

abstract interface class StructuredScheduleApplicationGateway {
  Future<StructuredScheduleApplicationResult> apply(
    StructuredScheduleApplicationBatch batch,
  );
}

/// Closed boundary between the review screen and durable domain writes.
///
/// No individual proposal is ever sent to persistence. The complete reviewed
/// batch crosses one gateway call so production can provide idempotency and
/// avoid UI-owned Event/Profile writes.
final class StructuredScheduleImportApplicationService {
  const StructuredScheduleImportApplicationService({required this.gateway});

  final StructuredScheduleApplicationGateway gateway;

  Future<StructuredScheduleApplicationResult> apply({
    required StructuredScheduleImportReview review,
    required String currentAccountScopeId,
  }) async {
    if (review.state != StructuredScheduleReviewState.readyToApply) {
      return const StructuredScheduleApplicationResult(
        StructuredScheduleApplicationStatus.invalidReview,
      );
    }
    if (currentAccountScopeId.trim().isEmpty ||
        review.accountScopeId != currentAccountScopeId) {
      return const StructuredScheduleApplicationResult(
        StructuredScheduleApplicationStatus.scopeMismatch,
      );
    }
    final kept = review.proposals.where((proposal) => proposal.isKept).toList();
    if (kept.isEmpty || kept.any((proposal) => !proposal.isComplete)) {
      return const StructuredScheduleApplicationResult(
        StructuredScheduleApplicationStatus.invalidReview,
      );
    }
    return gateway.apply(
      StructuredScheduleApplicationBatch(
        importId: review.importId,
        accountScopeId: review.accountScopeId,
        proposals: kept,
      ),
    );
  }
}
