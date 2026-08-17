import '../models/structured_schedule_import.dart';

final class StructuredScheduleImportReviewService {
  const StructuredScheduleImportReviewService();

  StructuredScheduleImportReview acceptAllClear(
    StructuredScheduleImportReview review,
  ) {
    return review.copyWith(
      proposals: review.proposals.map((proposal) {
        if (proposal.state != StructuredScheduleProposalState.pendingReview ||
            !proposal.isComplete) {
          return proposal;
        }
        return proposal.copyWith(
          state: StructuredScheduleProposalState.accepted,
        );
      }).toList(),
    );
  }

  StructuredScheduleImportReview acceptProposal(
    StructuredScheduleImportReview review,
    String proposalId,
  ) {
    final proposal = _proposal(review, proposalId);
    if (!proposal.isComplete) {
      throw const StructuredScheduleImportException(
        'proposal_requires_correction',
      );
    }
    return _replace(
      review,
      proposal.copyWith(state: StructuredScheduleProposalState.accepted),
    );
  }

  StructuredScheduleImportReview correctProposal(
    StructuredScheduleImportReview review,
    StructuredScheduleProposal corrected,
  ) {
    _proposal(review, corrected.proposalId);
    if (!corrected.isComplete ||
        corrected.state == StructuredScheduleProposalState.rejected) {
      throw const StructuredScheduleImportException(
        'invalid_proposal_correction',
      );
    }
    return _replace(
      review,
      corrected.copyWith(state: StructuredScheduleProposalState.corrected),
    );
  }

  StructuredScheduleImportReview rejectProposal(
    StructuredScheduleImportReview review,
    String proposalId,
  ) {
    final proposal = _proposal(review, proposalId);
    return _replace(
      review,
      proposal.copyWith(state: StructuredScheduleProposalState.rejected),
    );
  }

  List<StructuredScheduleProposal> validatedProposals(
    StructuredScheduleImportReview review,
  ) {
    if (review.state != StructuredScheduleReviewState.readyToApply) {
      throw const StructuredScheduleImportException('review_not_ready');
    }
    return List.unmodifiable(review.proposals.where((item) => item.isKept));
  }

  StructuredScheduleProposal _proposal(
    StructuredScheduleImportReview review,
    String proposalId,
  ) {
    if (proposalId.trim().isEmpty) {
      throw const StructuredScheduleImportException('proposal_not_found');
    }
    for (final proposal in review.proposals) {
      if (proposal.proposalId == proposalId) return proposal;
    }
    throw const StructuredScheduleImportException('proposal_not_found');
  }

  StructuredScheduleImportReview _replace(
    StructuredScheduleImportReview review,
    StructuredScheduleProposal replacement,
  ) {
    return review.copyWith(
      proposals: review.proposals
          .map(
            (proposal) => proposal.proposalId == replacement.proposalId
                ? replacement
                : proposal,
          )
          .toList(),
    );
  }
}
