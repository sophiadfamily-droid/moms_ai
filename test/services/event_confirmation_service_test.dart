import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/services/event_confirmation_service.dart';

void main() {
  EventModel buildEvent({
    bool recurring = false,
  }) {
    return EventModel(
      title: 'Dentiste',
      date: '2026-07-20',
      time: '14:00',
      notes: '',
      category: 'Santé',
      createdAt: DateTime(2026, 7, 15),
      startDateTimeIso: '2026-07-20T14:00:00',
      endTime: '14:45',
      endDateTimeIso: '2026-07-20T14:45:00',
      durationMinutes: 45,
      travelMinutes: 45,
      travelGoMinutes: 15,
      travelBackMinutes: 30,
      usesSeparateTravelTimes: true,
      marginMinutes: 10,
      isRecurring: recurring,
      recurringType: recurring ? 'weekly' : '',
      recurringWeekday: recurring ? DateTime.monday : 0,
    );
  }

  group('EventConfirmationService', () {
    test('builds a complete confirmation summary', () {
      final message = EventConfirmationService.buildConfirmationMessage(
        buildEvent(),
      );

      expect(message, contains('Dentiste'));
      expect(message, contains('20/07/2026'));
      expect(message, contains('14:00'));
      expect(message, contains('Durée : 45 min'));
      expect(message, contains('Trajet aller : 15 min'));
      expect(message, contains('Trajet retour : 30 min'));
      expect(message, contains('Marge de sécurité : 10 min'));
      expect(message, contains('Veux-tu'));
    });

    test('does not write anything when a conflict exists', () async {
      final event = buildEvent();
      var singleWrites = 0;
      var multipleWrites = 0;
      var notifications = 0;

      final conflict = event.copyWith(title: 'École');

      final result = await EventConfirmationService.confirm(
        event: event,
        conflictChecker: ({required candidate}) async => conflict,
        addEvent: (_, {mutationId}) async {
          singleWrites++;
        },
        addEvents: (_) async {
          multipleWrites++;
        },
        showNotification: ({
          required title,
          required body,
        }) async {
          notifications++;
        },
      );

      expect(result.created, false);
      expect(result.conflictEvent?.title, 'École');
      expect(singleWrites, 0);
      expect(multipleWrites, 0);
      expect(notifications, 0);
    });

    test('writes one event only after confirmation execution', () async {
      final event = buildEvent();
      var singleWrites = 0;
      var multipleWrites = 0;
      var notifications = 0;

      final result = await EventConfirmationService.confirm(
        event: event,
        conflictChecker: ({required candidate}) async => null,
        addEvent: (createdEvent, {mutationId}) async {
          singleWrites++;
          expect(createdEvent.title, 'Dentiste');
        },
        addEvents: (_) async {
          multipleWrites++;
        },
        showNotification: ({
          required title,
          required body,
        }) async {
          notifications++;
          expect(body, 'Dentiste');
        },
      );

      expect(result.created, true);
      expect(singleWrites, 1);
      expect(multipleWrites, 0);
      expect(notifications, 1);
    });

    test('writes recurring occurrences through the batch writer', () async {
      final event = buildEvent(recurring: true);
      var singleWrites = 0;
      var multipleWrites = 0;
      var occurrenceCount = 0;

      final result = await EventConfirmationService.confirm(
        event: event,
        conflictChecker: ({required candidate}) async => null,
        addEvent: (_, {mutationId}) async {
          singleWrites++;
        },
        addEvents: (events) async {
          multipleWrites++;
          occurrenceCount = events.length;
        },
        showNotification: ({
          required title,
          required body,
        }) async {},
      );

      expect(result.created, true);
      expect(singleWrites, 0);
      expect(multipleWrites, 1);
      expect(occurrenceCount, 52);
    });
  });
}
