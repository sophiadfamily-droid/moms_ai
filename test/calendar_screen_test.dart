import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/models/agenda_conflict_help.dart';
import 'package:moms_ai/models/event_sync_conflict.dart';
import 'package:moms_ai/models/event_sync_models.dart';
import 'package:moms_ai/models/routine/routine_agenda_item.dart';
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
  testWidgets('agenda back arrow returns to the dashboard', (tester) async {
    var returnedHome = false;

    await tester.pumpWidget(
      MaterialApp(
        home: CalendarScreen(
          loadEventsForTest: () async => const [],
          loadRoutinesForDayForTest: (_, __) async => const [],
          onBackToHome: () => returnedHome = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('agenda-back-to-home')));

    expect(returnedHome, isTrue);
  });

  testWidgets('shows a conflict from earlier on the selected day',
      (WidgetTester tester) async {
    final today = DateTime.now();
    final date = isoDate(today);
    await tester.pumpWidget(
      MaterialApp(
        home: CalendarScreen(
          accountScopeToken: 'account-a',
          initialDate: today,
          eventsVersionForTest: ValueNotifier<int>(0),
          routinesVersionForTest: ValueNotifier<int>(0),
          loadEventsForTest: () async => [
            EventModel(
              id: 'past-event',
              title: 'Ancien rendez-vous',
              date: date,
              time: '06:00',
              durationMinutes: 60,
              notes: '',
              createdAt: DateTime.utc(2026, 8, 1),
              startDateTimeIso: '${date}T06:00:00',
            ),
          ],
          loadSyncConflictsForTest: () async => const [],
          loadRoutinesForDayForTest: (_, day) async => [
            RoutineAgendaItem(
              occurrenceId: 'past-routine:${isoDate(day)}',
              routineId: 'past-routine',
              dateIso: isoDate(day),
              title: 'Routine du matin',
              startTime: '06:30',
              endTime: '07:00',
              protectedStart: DateTime(day.year, day.month, day.day, 6, 30),
              protectedEnd: DateTime(day.year, day.month, day.day, 7),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Regarde, « Ancien rendez-vous » et « Routine du matin » se '
        'chevauchent. Je ne change rien sans ton accord.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('highlights the exact event and routine opened from an alert',
      (WidgetTester tester) async {
    final testDay = DateTime.now().add(const Duration(days: 1));
    final date = isoDate(testDay);
    AgendaConflictHelp? requestedHelp;
    await tester.pumpWidget(
      MaterialApp(
        home: CalendarScreen(
          accountScopeToken: 'account-a',
          initialDate: testDay,
          highlightedEventId: 'event-coiffeur',
          highlightedRoutineId: 'routine-enfants',
          highlightedEventTitle: 'Coiffeur',
          highlightedRoutineTitle: 'Préparer les enfants',
          onAskZeliaForConflict: (help) => requestedHelp = help,
          eventsVersionForTest: ValueNotifier<int>(0),
          routinesVersionForTest: ValueNotifier<int>(0),
          loadEventsForTest: () async => [
            EventModel(
              id: 'event-coiffeur',
              title: 'Coiffeur',
              date: date,
              time: '08:00',
              notes: '',
              createdAt: DateTime.utc(2026, 8, 1),
              startDateTimeIso: '${date}T08:00:00',
            ),
          ],
          loadSyncConflictsForTest: () async => const [],
          loadRoutinesForDayForTest: (_, day) async => [
            RoutineAgendaItem(
              occurrenceId: 'routine-enfants:${isoDate(day)}',
              routineId: 'routine-enfants',
              dateIso: isoDate(day),
              title: 'Préparer les enfants',
              startTime: '10:00',
              endTime: '11:00',
              protectedStart: DateTime(day.year, day.month, day.day, 10),
              protectedEnd: DateTime(day.year, day.month, day.day, 11),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Regarde, « Coiffeur » et « Préparer les enfants » se chevauchent. '
        'Je ne change rien sans ton accord.',
      ),
      findsOneWidget,
    );
    expect(find.text('Coiffeur'), findsOneWidget);
    expect(find.text('Préparer les enfants'), findsOneWidget);
    final helpButton = find.text('Aide-moi à trouver une solution');
    await tester.ensureVisible(helpButton);
    await tester.pumpAndSettle();
    await tester.tap(helpButton);
    expect(requestedHelp?.eventTitle, 'Coiffeur');
    expect(requestedHelp?.eventId, 'event-coiffeur');
    expect(requestedHelp?.otherTitle, 'Préparer les enfants');
    expect(
      requestedHelp?.assistantMessage,
      'Je vois que « Coiffeur » et « Préparer les enfants » se chevauchent. '
      'Je peux t’aider à trouver une solution. Dis-moi ce que tu préfères '
      'déplacer.',
    );
  });

  testWidgets('shows a routine as a read-only Zelia Agenda item',
      (WidgetTester tester) async {
    final today = DateTime.now();
    final routineVersion = ValueNotifier<int>(0);
    await tester.pumpWidget(
      MaterialApp(
        home: CalendarScreen(
          accountScopeToken: 'account-a',
          initialDate: today,
          eventsVersionForTest: ValueNotifier<int>(0),
          routinesVersionForTest: routineVersion,
          loadEventsForTest: () async => const [],
          loadSyncConflictsForTest: () async => const [],
          loadRoutinesForDayForTest: (_, day) async => [
            RoutineAgendaItem(
              occurrenceId: 'routine-1:${isoDate(day)}',
              routineId: 'routine-1',
              dateIso: isoDate(day),
              title: 'Préparer les enfants',
              startTime: '07:30',
              endTime: '08:15',
              protectedStart: DateTime(day.year, day.month, day.day, 7, 30),
              protectedEnd: DateTime(day.year, day.month, day.day, 8, 15),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Préparer les enfants'), findsOneWidget);
    expect(find.text('07:30 - 08:15'), findsOneWidget);
    expect(find.text('Routine prévue par Zelia'), findsOneWidget);
    expect(
      find.byKey(ValueKey('routine-agenda-routine-1:${isoDate(today)}')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.more_horiz), findsNothing);
  });

  testWidgets('offers Zelia help when two future events overlap',
      (WidgetTester tester) async {
    final day = DateTime.now().add(const Duration(days: 2));
    final date = isoDate(day);
    AgendaConflictHelp? requestedHelp;
    await tester.pumpWidget(
      MaterialApp(
        home: CalendarScreen(
          accountScopeToken: 'account-a',
          initialDate: day,
          onAskZeliaForConflict: (help) => requestedHelp = help,
          eventsVersionForTest: ValueNotifier<int>(0),
          routinesVersionForTest: ValueNotifier<int>(0),
          loadEventsForTest: () async => [
            EventModel(
              id: 'event-one',
              title: 'Médecin',
              date: date,
              time: '14:00',
              durationMinutes: 60,
              notes: '',
              createdAt: DateTime.utc(2026, 8, 1),
              startDateTimeIso: '${date}T14:00:00',
            ),
            EventModel(
              id: 'event-two',
              title: 'Banque',
              date: date,
              time: '14:30',
              durationMinutes: 60,
              notes: '',
              createdAt: DateTime.utc(2026, 8, 1),
              startDateTimeIso: '${date}T14:30:00',
            ),
          ],
          loadSyncConflictsForTest: () async => const [],
          loadRoutinesForDayForTest: (_, __) async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Regarde, « Banque » et « Médecin » se chevauchent. '
        'Je ne change rien sans ton accord.',
      ),
      findsOneWidget,
    );
    final helpButton = find.text('Aide-moi à trouver une solution');
    await tester.ensureVisible(helpButton);
    await tester.tap(helpButton);
    expect(requestedHelp?.eventId, 'event-two');
    expect(requestedHelp?.eventTitle, 'Banque');
    expect(requestedHelp?.otherTitle, 'Médecin');
  });

  testWidgets(
    'account scope change clears immediately and discards the old load',
    (WidgetTester tester) async {
      final accountALoad = Completer<List<EventModel>>();
      final today = isoDate(DateTime.now());
      final accountEvent = EventModel(
        id: 'account-a-event',
        title: 'Événement compte A',
        date: today,
        time: '10:00',
        notes: '',
        createdAt: DateTime.utc(2026, 7, 28),
        startDateTimeIso: '${today}T10:00:00',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CalendarScreen(
            accountScopeToken: 'account-a',
            eventsVersionForTest: ValueNotifier<int>(0),
            loadEventsForTest: () => accountALoad.future,
            loadSyncConflictsForTest: () async => const [],
          ),
        ),
      );
      await tester.pump();

      await tester.pumpWidget(
        MaterialApp(
          home: CalendarScreen(
            accountScopeToken: 'guest',
            eventsVersionForTest: ValueNotifier<int>(0),
            loadEventsForTest: () async => const [],
            loadSyncConflictsForTest: () async => const [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Événement compte A'), findsNothing);

      accountALoad.complete([accountEvent]);
      await tester.pumpAndSettle();
      expect(find.text('Événement compte A'), findsNothing);
    },
  );

  testWidgets('account A, B and A again never mix visible events',
      (WidgetTester tester) async {
    final today = isoDate(DateTime.now());
    EventModel event(String id, String title) => EventModel(
          id: id,
          title: title,
          date: today,
          time: '10:00',
          notes: '',
          createdAt: DateTime.utc(2026, 7, 28),
          startDateTimeIso: '${today}T10:00:00',
        );

    Future<void> showScope(String scope, EventModel scopedEvent) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CalendarScreen(
            accountScopeToken: scope,
            eventsVersionForTest: ValueNotifier<int>(0),
            loadEventsForTest: () async => [scopedEvent],
            loadSyncConflictsForTest: () async => const [],
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await showScope('account-a', event('event-a', 'Agenda A'));
    expect(find.text('Agenda A'), findsOneWidget);

    await showScope('account-b', event('event-b', 'Agenda B'));
    expect(find.text('Agenda A'), findsNothing);
    expect(find.text('Agenda B'), findsOneWidget);

    await showScope('account-a', event('event-a', 'Agenda A'));
    expect(find.text('Agenda B'), findsNothing);
    expect(find.text('Agenda A'), findsOneWidget);

    await showScope('guest', event('event-guest', 'Agenda invité'));
    expect(find.text('Agenda A'), findsNothing);
    expect(find.text('Agenda invité'), findsOneWidget);

    await showScope('account-a', event('event-a', 'Agenda A'));
    expect(find.text('Agenda invité'), findsNothing);
    expect(find.text('Agenda A'), findsOneWidget);

    await showScope('guest', event('event-guest', 'Agenda invité'));
    expect(find.text('Agenda A'), findsNothing);
    expect(find.text('Agenda invité'), findsOneWidget);
  });

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
    expect(find.text('Ton agenda a changé'), findsOneWidget);
    await tester.tap(find.text('Appliquer mes changements'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmer'));
    await tester.pumpAndSettle();

    expect(transmitted, EventConflictResolutionDecision.retryAgainstLatest);
    expect(find.textContaining('deux choses en même temps'), findsOneWidget);
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
