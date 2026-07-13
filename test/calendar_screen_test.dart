import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/screens/calendar_screen.dart';

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
      updateEventsForTest: onUpdate ?? (_) async {},
    ),
  );
}

void main() {
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
    },
  );
}
