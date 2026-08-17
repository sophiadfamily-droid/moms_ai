import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/structured_schedule_import.dart';
import 'package:moms_ai/services/structured_schedule_import_application_service.dart';

void main() {
  test('refuse un lot qui contient encore une ligne à vérifier', () async {
    final gateway = _Gateway();
    final result = await StructuredScheduleImportApplicationService(
      gateway: gateway,
    ).apply(
      review: _review(proposal: _proposal()),
      currentAccountScopeId: 'account-a',
    );

    expect(result.status, StructuredScheduleApplicationStatus.invalidReview);
    expect(gateway.calls, 0);
  });

  test('refuse une validation provenant d’un autre compte', () async {
    final gateway = _Gateway();
    final result = await StructuredScheduleImportApplicationService(
      gateway: gateway,
    ).apply(
      review: _review(
        proposal: _proposal(
          state: StructuredScheduleProposalState.accepted,
        ),
      ),
      currentAccountScopeId: 'account-b',
    );

    expect(result.status, StructuredScheduleApplicationStatus.scopeMismatch);
    expect(gateway.calls, 0);
  });

  test('envoie une seule fois le lot entièrement validé', () async {
    final gateway = _Gateway();
    final result = await StructuredScheduleImportApplicationService(
      gateway: gateway,
    ).apply(
      review: _review(
        proposal: _proposal(
          state: StructuredScheduleProposalState.accepted,
        ),
      ),
      currentAccountScopeId: 'account-a',
    );

    expect(result.isSuccess, isTrue);
    expect(gateway.calls, 1);
    expect(gateway.last!.proposals.single.proposalId, 'proposal-a');
  });
}

StructuredScheduleImportReview _review({
  required StructuredScheduleProposal proposal,
}) =>
    StructuredScheduleImportReview(
      importId: 'import-a',
      accountScopeId: 'account-a',
      initiatedForSubjectEntityId: 'person-a',
      initiatedForSubjectLabel: 'Sophia',
      documentKind: StructuredScheduleDocumentKind.image,
      createdAt: DateTime.utc(2026, 8, 17),
      sourceWasDiscarded: true,
      proposals: [proposal],
    );

StructuredScheduleProposal _proposal({
  StructuredScheduleProposalState state =
      StructuredScheduleProposalState.pendingReview,
}) =>
    StructuredScheduleProposal(
      proposalId: 'proposal-a',
      target: StructuredScheduleTarget.activitySchedule,
      temporalKind: StructuredScheduleTemporalKind.recurringWeekly,
      title: 'Pilates',
      subjectEntityId: 'person-a',
      subjectLabel: 'Sophia',
      weekdays: const [DateTime.wednesday],
      startTime: '09:00',
      endTime: '10:00',
      confidence: StructuredScheduleConfidence.high,
      state: state,
    );

final class _Gateway implements StructuredScheduleApplicationGateway {
  int calls = 0;
  StructuredScheduleApplicationBatch? last;

  @override
  Future<StructuredScheduleApplicationResult> apply(
    StructuredScheduleApplicationBatch batch,
  ) async {
    calls++;
    last = batch;
    return const StructuredScheduleApplicationResult(
      StructuredScheduleApplicationStatus.applied,
    );
  }
}
