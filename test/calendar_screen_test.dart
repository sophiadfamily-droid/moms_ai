import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/models/event_sync_conflict.dart';
import 'package:moms_ai/models/event_sync_models.dart';
import 'package:moms_ai/screens/calendar_screen.dart';
import 'package:moms_ai/services/event_mutation_result.dart';

String isoDate(DateTime date) {
  final year = date.year.toString();
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

Widget buildCalendar({
  required List<EventModel> initialEvents,
  Future<void> Function(List<EventModel> events)? onUpdate,
}) {
  return MaterialApp(
    home: CalendarScreen(
      eventsVersionForTest: ValueNotifier<int>(0),
      loadEventsForTest: () async => List<EventModel>.from(initialEvents),
      addEventForTest: (_) async {},
      mutateEventForTest: ({
        required existing,
        required proposed,
        required expectedEventRevision,
        required participantIntent,
      }) async {
        await onUpdate?.call([
          proposed.copyWith(eventRevision: expectedEventRevision + 1),
        ]);
        return EventMutationResult.success(
          proposed.copyWith(eventRevision: expectedEventRevision + 1),
        );
      },
    ),
  );
}

void main() {
  testWidgets('conflict dialog reports a new planning conflict safely',
      (WidgetTester tester) async {
    final conflict = EventSyncConflict.fromOperation(
      PendingEventSyncOperation(
        operationId: 'synthetic-operation',
        eventId: 'synthetic-event',
        accountScopeId: 'synthetic-scope',
        type: EventSyncOperationType.update,
        expectedEventRevision: 1,
        event: EventModel(
          id: 'synthetic-event',
          title: 'Événement synthétique',
          date: '2026-07-23',
          time: '10:00',
          notes: '',
          createdAt: DateTime.utc(2026, 7, 22),
          startDateTimeIso: '2026-07-23T10:00:00',
          eventRevision: 2,
        ),
        baseEvent: EventModel(
          id: 'synthetic-event',
          title: 'Événement synthétique',
          date: '2026-07-23',
          time: '09:00',
          notes: '',
          createdAt: DateTime.utc(2026, 7, 22),
          startDateTimeIso: '2026-07-23T09:00:00',
          eventRevision: 1,
        ),
        batchId: 'synthetic-batch',
        createdAt: DateTime.utc(2026, 7, 22),
        state: EventSyncOperationState.conflict,
        conflictType: EventSyncConflictType.revisionConflict,
      ),
    );
    EventConflictResolutionDecision? transmitted;
    await tester.pumpWidget(MaterialApp(
      home: CalendarScreen(
        eventsVersionForTest: ValueNotifier<int>(0),
        loadEventsForTest: () async => <EventModel>[],
        loadSyncConflictsForTest: () async => [conflict],
        resolveSyncConflictForTest: ({
          required conflictId,
          required decision,
          required confirmed,
        }) async {
          transmitted = decision;
          return const EventConflictResolutionResult.planningConflict();
        },
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('1 modification(s) à vérifier'));
    await tester.pumpAndSettle();
    expect(find.text('Modification à vérifier'), findsOneWidget);
    await tester.tap(find.text('Reprendre'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmer'));
    await tester.pumpAndSettle();

    expect(transmitted, EventConflictResolutionDecision.retryAgainstLatest);
    expect(find.textContaining('conflit dans ton planning'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets(
    'manual event form exposes separate travel fields',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 932));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildCalendar(initialEvents: const []),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.text('Durée'), findsOneWidget);
      expect(find.text('Trajet aller'), findsOneWidget);
      expect(find.text('Trajet retour'), findsOneWidget);
      expect(find.text('Marge de sécurité'), findsOneWidget);
      expect(find.text('Temps de trajet'), findsNothing);
    },
  );

  testWidgets(
    'editing preserves outbound travel and explicit zero return',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 932));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final date = isoDate(DateTime.now());

      final initialEvent = EventModel(
        id: 'event-stable-id',
        title: 'Médecin',
        date: date,
        time: '10:15',
        endTime: '11:00',
        notes: '',
        category: 'Santé',
        createdAt: DateTime(2026, 7, 13, 12),
        startDateTimeIso: '${date}T10:15:00',
        endDateTimeIso: '${date}T11:00:00',
        durationMinutes: 45,
        travelMinutes: 45,
        travelGoMinutes: 15,
        travelBackMinutes: 30,
        usesSeparateTravelTimes: true,
        marginMinutes: 10,
        departureContext: 'home',
        arrivalContext: 'home',
      );

      List<EventModel>? savedEvents;

      await tester.pumpWidget(
        buildCalendar(
          initialEvents: [initialEvent],
          onUpdate: (events) async {
            savedEvents = List<EventModel>.from(events);
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Médecin').first);
      await tester.pumpAndSettle();

      expect(find.text('Trajet aller'), findsOneWidget);
      expect(find.text('Trajet retour'), findsOneWidget);
      expect(find.text('Marge de sécurité'), findsOneWidget);

      final noTravelChoices = find.text('Aucun');
      expect(noTravelChoices, findsNWidgets(2));

      await tester.ensureVisible(noTravelChoices.at(1));
      await tester.tap(noTravelChoices.at(1));
      await tester.pump();

      final saveButton = find.text('Enregistrer');
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(savedEvents, isNotNull);
      expect(savedEvents, hasLength(1));

      final saved = savedEvents!.single;

      expect(saved.travelGoMinutes, 15);
      expect(saved.travelBackMinutes, 0);
      expect(saved.marginMinutes, 10);
      expect(saved.usesSeparateTravelTimes, isTrue);
      expect(saved.departureContext, 'home');
      expect(saved.arrivalContext, 'home');
      expect(saved.id, 'event-stable-id');
      expect(saved.eventRevision, 2);
    },
  );
}
