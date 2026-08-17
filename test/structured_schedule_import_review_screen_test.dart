import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/structured_schedule_import.dart';
import 'package:moms_ai/screens/structured_schedule_import_review_screen.dart';

void main() {
  testWidgets(
    'la revue nomme la personne et ne valide pas une ligne incertaine',
    (tester) async {
      _useTallSurface(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: StructuredScheduleImportReviewScreen(
            initialReview: _review(),
            subjects: const [
              StructuredScheduleSubjectChoice(
                entityId: 'person-sophia',
                label: 'Sophia',
              ),
              StructuredScheduleSubjectChoice(
                entityId: 'person-kassim',
                label: 'Kassim',
              ),
            ],
            onValidated: (_) async {},
          ),
        ),
      );

      expect(find.text('Document de Kassim'), findsOneWidget);
      expect(find.text('Kassim · École ou crèche'), findsNWidgets(2));

      await tester.tap(
        find.byKey(const ValueKey('schedule-import-accept-clear')),
      );
      await tester.pumpAndSettle();

      final continueButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey('schedule-import-continue')),
      );
      expect(continueButton.onPressed, isNull);
      expect(find.text('Vérifier'), findsOneWidget);
      expect(find.byIcon(Icons.verified), findsOneWidget);
    },
  );

  testWidgets(
    'une correction ciblée termine la revue avec une validation unique',
    (tester) async {
      _useTallSurface(tester);
      List<StructuredScheduleProposal>? validated;
      await tester.pumpWidget(
        MaterialApp(
          home: StructuredScheduleImportReviewScreen(
            initialReview: _review(),
            subjects: const [
              StructuredScheduleSubjectChoice(
                entityId: 'person-kassim',
                label: 'Kassim',
              ),
            ],
            onValidated: (values) async => validated = values,
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('schedule-import-accept-clear')),
      );
      await tester.pumpAndSettle();
      final edit = find.byKey(const ValueKey('schedule-import-edit-school-2'));
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('schedule-import-end-time')),
        '16:30',
      );
      final save =
          find.byKey(const ValueKey('schedule-import-save-correction'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      final continueFinder =
          find.byKey(const ValueKey('schedule-import-continue'));
      await tester.ensureVisible(continueFinder);
      expect(find.text('Continuer avec 2 informations'), findsOneWidget);
      await tester.tap(continueFinder);
      await tester.pumpAndSettle();

      expect(validated, hasLength(2));
      expect(
        validated!.singleWhere((item) => item.proposalId == 'school-2').endTime,
        '16:30',
      );
    },
  );

  testWidgets(
    'une fin le lendemain peut être corrigée sans erreur',
    (tester) async {
      _useTallSurface(tester);
      List<StructuredScheduleProposal>? validated;
      await tester.pumpWidget(
        MaterialApp(
          home: StructuredScheduleImportReviewScreen(
            initialReview: _nightReview(),
            subjects: const [
              StructuredScheduleSubjectChoice(
                entityId: 'person-willy',
                label: 'Willy',
              ),
            ],
            onValidated: (values) async => validated = values,
          ),
        ),
      );

      expect(
        find.textContaining('27/08/2026 · 21:00 – heure à vérifier'),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('schedule-import-edit-night-work')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Personne concernée'), findsNothing);
      expect(find.text('Modifier seulement si besoin'), findsOneWidget);
      final dateField = tester.widget<TextField>(
        find.byKey(const ValueKey('schedule-import-date')),
      );
      expect(dateField.controller!.text, '27/08/2026');
      await tester.enterText(
        find.byKey(const ValueKey('schedule-import-end-time')),
        '09:00',
      );
      final save =
          find.byKey(const ValueKey('schedule-import-save-correction'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('schedule-import-sheet-error')),
        findsNothing,
      );
      expect(
        find.textContaining('21:00 – 09:00 (le lendemain)'),
        findsOneWidget,
      );
      expect(find.text('Continuer avec 1 information'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('schedule-import-continue')),
      );
      await tester.pumpAndSettle();
      expect(validated!.single.dateIso, '2026-08-27');
    },
  );
}

void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

StructuredScheduleImportReview _review() => StructuredScheduleImportReview(
      importId: 'import-school-kassim',
      accountScopeId: 'user-1',
      initiatedForSubjectEntityId: 'person-kassim',
      initiatedForSubjectLabel: 'Kassim',
      documentKind: StructuredScheduleDocumentKind.pdf,
      createdAt: DateTime.utc(2026, 8, 17),
      sourceWasDiscarded: true,
      proposals: [
        StructuredScheduleProposal(
          proposalId: 'school-1',
          target: StructuredScheduleTarget.schoolSchedule,
          temporalKind: StructuredScheduleTemporalKind.recurringWeekly,
          title: 'École',
          subjectEntityId: 'person-kassim',
          subjectLabel: 'Kassim',
          weekdays: const [DateTime.monday, DateTime.tuesday],
          startTime: '08:30',
          endTime: '11:50',
          confidence: StructuredScheduleConfidence.high,
        ),
        StructuredScheduleProposal(
          proposalId: 'school-2',
          target: StructuredScheduleTarget.schoolSchedule,
          temporalKind: StructuredScheduleTemporalKind.recurringWeekly,
          title: 'École',
          subjectEntityId: 'person-kassim',
          subjectLabel: 'Kassim',
          weekdays: const [DateTime.monday, DateTime.tuesday],
          startTime: '13:30',
          confidence: StructuredScheduleConfidence.medium,
          uncertainties: const [StructuredScheduleUncertainty.endTime],
        ),
      ],
    );

StructuredScheduleImportReview _nightReview() => StructuredScheduleImportReview(
      importId: 'import-night-work',
      accountScopeId: 'user-1',
      initiatedForSubjectEntityId: 'person-willy',
      initiatedForSubjectLabel: 'Willy',
      documentKind: StructuredScheduleDocumentKind.image,
      createdAt: DateTime.utc(2026, 8, 17),
      sourceWasDiscarded: true,
      proposals: [
        StructuredScheduleProposal(
          proposalId: 'night-work',
          target: StructuredScheduleTarget.workSchedule,
          temporalKind: StructuredScheduleTemporalKind.dated,
          title: 'Travail',
          subjectEntityId: 'person-willy',
          subjectLabel: 'Willy',
          dateIso: '2026-08-27',
          startTime: '21:00',
          confidence: StructuredScheduleConfidence.medium,
          uncertainties: const [StructuredScheduleUncertainty.endTime],
        ),
      ],
    );
