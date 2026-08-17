import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/structured_schedule_import.dart';
import 'package:moms_ai/services/structured_schedule_import_review_service.dart';

void main() {
  const service = StructuredScheduleImportReviewService();

  test('une validation globale conserve seulement les lignes complètes', () {
    final review = _review([
      _datedEvent('event-1'),
      StructuredScheduleProposal(
        proposalId: 'school-1',
        target: StructuredScheduleTarget.schoolSchedule,
        temporalKind: StructuredScheduleTemporalKind.recurringWeekly,
        title: 'École',
        subjectEntityId: 'person-kassim',
        subjectLabel: 'Kassim',
        weekdays: const [DateTime.monday, DateTime.tuesday],
        startTime: '08:30',
        confidence: StructuredScheduleConfidence.medium,
        uncertainties: const [StructuredScheduleUncertainty.endTime],
      ),
    ]);

    final result = service.acceptAllClear(review);

    expect(
      result.proposals.first.state,
      StructuredScheduleProposalState.accepted,
    );
    expect(
      result.proposals.last.state,
      StructuredScheduleProposalState.pendingReview,
    );
    expect(result.state, StructuredScheduleReviewState.needsReview);
  });

  test('une ligne incertaine doit être corrigée avant application', () {
    final uncertain = StructuredScheduleProposal(
      proposalId: 'activity-1',
      target: StructuredScheduleTarget.activitySchedule,
      temporalKind: StructuredScheduleTemporalKind.recurringWeekly,
      title: 'Pilates',
      subjectEntityId: 'person-sophia',
      subjectLabel: 'Sophia',
      weekdays: const [DateTime.wednesday],
      startTime: '09:00',
      confidence: StructuredScheduleConfidence.medium,
      uncertainties: const [StructuredScheduleUncertainty.endTime],
    );
    final review = _review([uncertain]);

    expect(
      () => service.acceptProposal(review, 'activity-1'),
      throwsA(_code('proposal_requires_correction')),
    );

    final corrected = service.correctProposal(
      review,
      uncertain.copyWith(
        endTime: '10:00',
        confidence: StructuredScheduleConfidence.high,
        uncertainties: const [],
      ),
    );
    final values = service.validatedProposals(corrected);

    expect(corrected.state, StructuredScheduleReviewState.readyToApply);
    expect(values, hasLength(1));
    expect(values.single.endTime, '10:00');
    expect(
      values.single.state,
      StructuredScheduleProposalState.corrected,
    );
  });

  test('une ligne rejetée ne produit aucune donnée à appliquer', () {
    final review = _review([_datedEvent('event-1'), _datedEvent('event-2')]);
    final accepted = service.acceptProposal(review, 'event-1');
    final result = service.rejectProposal(accepted, 'event-2');

    expect(result.state, StructuredScheduleReviewState.readyToApply);
    expect(service.validatedProposals(result).single.proposalId, 'event-1');
  });

  test('un service de nuit se termine automatiquement le lendemain', () {
    final nightShift = StructuredScheduleProposal(
      proposalId: 'night-work-1',
      target: StructuredScheduleTarget.workSchedule,
      temporalKind: StructuredScheduleTemporalKind.dated,
      title: 'Travail de nuit',
      subjectEntityId: 'person-willy',
      subjectLabel: 'Willy',
      dateIso: '2026-08-27',
      startTime: '21:00',
      endTime: '09:00',
      confidence: StructuredScheduleConfidence.high,
    );

    expect(nightShift.isComplete, isTrue);
    expect(nightShift.spansMidnight, isTrue);
    final accepted =
        service.acceptProposal(_review([nightShift]), 'night-work-1');
    expect(accepted.state, StructuredScheduleReviewState.readyToApply);
  });

  test('le contrat ne conserve ni fichier, ni octets, ni texte OCR brut', () {
    final json = _review([_datedEvent('event-1')]).toJson();
    final serialized = json.toString().toLowerCase();

    expect(json['sourceWasDiscarded'], isTrue);
    expect(serialized, isNot(contains('filepath')));
    expect(serialized, isNot(contains('bytes')));
    expect(serialized, isNot(contains('rawocr')));
    expect(serialized, isNot(contains('documenttext')));
  });

  test('un événement récurrent est refusé par le contrat fermé', () {
    expect(
      () => StructuredScheduleProposal(
        proposalId: 'event-1',
        target: StructuredScheduleTarget.event,
        temporalKind: StructuredScheduleTemporalKind.recurringWeekly,
        title: 'Dentiste',
        weekdays: const [DateTime.monday],
        startTime: '09:00',
        endTime: '10:00',
        confidence: StructuredScheduleConfidence.high,
      ),
      throwsA(_code('invalid_structured_schedule_proposal')),
    );
  });

  test('le résultat de revue exige la suppression de la source', () {
    expect(
      () => StructuredScheduleImportReview(
        importId: 'import-1',
        accountScopeId: 'user-1',
        initiatedForSubjectEntityId: 'person-sophia',
        initiatedForSubjectLabel: 'Sophia',
        documentKind: StructuredScheduleDocumentKind.pdf,
        createdAt: DateTime.utc(2026, 8, 17),
        sourceWasDiscarded: false,
        proposals: [_datedEvent('event-1')],
      ),
      throwsA(_code('invalid_structured_schedule_review')),
    );
  });
}

StructuredScheduleImportReview _review(
  List<StructuredScheduleProposal> proposals,
) =>
    StructuredScheduleImportReview(
      importId: 'import-1',
      accountScopeId: 'user-1',
      initiatedForSubjectEntityId: 'person-sophia',
      initiatedForSubjectLabel: 'Sophia',
      documentKind: StructuredScheduleDocumentKind.image,
      createdAt: DateTime.utc(2026, 8, 17),
      sourceWasDiscarded: true,
      proposals: proposals,
    );

StructuredScheduleProposal _datedEvent(String id) => StructuredScheduleProposal(
      proposalId: id,
      target: StructuredScheduleTarget.event,
      temporalKind: StructuredScheduleTemporalKind.dated,
      title: 'Dentiste',
      subjectEntityId: 'person-sophia',
      subjectLabel: 'Sophia',
      dateIso: '2026-08-20',
      startTime: '09:00',
      endTime: '10:00',
      place: 'Clinique du Vert-Galant',
      confidence: StructuredScheduleConfidence.high,
    );

Matcher _code(String code) => isA<StructuredScheduleImportException>().having(
      (error) => error.code,
      'code',
      code,
    );
