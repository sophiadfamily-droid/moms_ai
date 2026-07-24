import '../models/event_model.dart';
import 'event_service.dart';
import 'zelia_response_builder.dart';

typedef EventConflictChecker = Future<EventModel?> Function({
  required EventModel candidate,
});

typedef SingleEventWriter = Future<void> Function(
  EventModel event, {
  String? mutationId,
});

typedef MultipleEventsWriter = Future<void> Function(
  List<EventModel> events,
);

typedef EventNotificationWriter = Future<void> Function({
  required String title,
  required String body,
});

class EventConfirmationResult {
  final bool created;
  final EventModel? conflictEvent;
  final String message;

  const EventConfirmationResult({
    required this.created,
    required this.message,
    this.conflictEvent,
  });
}

class EventConfirmationService {
  static String buildConfirmationMessage(EventModel event) {
    final displayDate = ZeliaResponseBuilder.formatDateForUser(event.date);
    final lines = <String>[
      "J’ai préparé ce rendez-vous 💕",
      "",
      "• ${event.title}",
      "• Le $displayDate à ${event.time}",
      "• Durée : ${event.durationMinutes} min",
      "• Trajet aller : ${event.resolvedTravelGoMinutes} min",
      "• Trajet retour : ${event.resolvedTravelBackMinutes} min",
      if (event.marginMinutes > 0)
        "• Marge de sécurité : ${event.marginMinutes} min",
      if (event.isRecurring && event.recurringType == "weekly")
        "• Répétition : chaque semaine",
      "",
      "Veux-tu que je l’ajoute à ton agenda ?",
    ];

    return lines.join("\n");
  }

  static String buildCancellationMessage(EventModel event) {
    return "D’accord 💕 Je n’ajoute pas « ${event.title} » dans ton agenda.";
  }

  static String buildExpectedAnswerMessage() {
    return "Réponds simplement oui pour l’ajouter à ton agenda, "
        "ou non pour annuler 💕";
  }

  static Future<EventConfirmationResult> confirm({
    required EventModel event,
    required EventConflictChecker conflictChecker,
    required SingleEventWriter addEvent,
    required MultipleEventsWriter addEvents,
    required EventNotificationWriter showNotification,
    String? mutationId,
  }) async {
    final conflictEvent = await conflictChecker(candidate: event);

    if (conflictEvent != null) {
      return EventConfirmationResult(
        created: false,
        conflictEvent: conflictEvent,
        message: "Je n’ai pas ajouté « ${event.title} », car le créneau "
            "est maintenant en conflit avec « ${conflictEvent.title} ». "
            "Je peux chercher un autre horaire.",
      );
    }

    if (event.isRecurring && event.recurringType == "weekly") {
      final occurrences = EventService.buildWeeklyOccurrences(
        baseEvent: event,
        count: 52,
      );

      await addEvents(occurrences);
    } else {
      await addEvent(event, mutationId: mutationId);
    }

    await showNotification(
      title: "Nouvel événement 📅",
      body: event.title,
    );

    return EventConfirmationResult(
      created: true,
      message: ZeliaResponseBuilder.eventCreated(
        title: event.title,
        date: event.date,
        time: event.time,
        durationMinutes: event.durationMinutes,
        travelGoMinutes: event.resolvedTravelGoMinutes,
        travelBackMinutes: event.resolvedTravelBackMinutes,
        marginMinutes: event.marginMinutes,
        isRecurring: event.isRecurring,
      ),
    );
  }
}
