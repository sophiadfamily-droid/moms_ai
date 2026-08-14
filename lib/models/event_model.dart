import 'event_participant_identity_link.dart';

class EventModel {
  final String? id;
  final String title;
  final String date;
  final String time;
  final String notes;
  final String category;
  final String location;
  final String? locationEntityId;
  final DateTime createdAt;
  final String startDateTimeIso;

  final String endTime;
  final String endDateTimeIso;
  final int durationMinutes;

  /// Ancien champ conservé pour compatibilité avec les rendez-vous existants.
  /// Il représente le trajet aller par défaut lorsque les nouveaux champs
  /// ne sont pas encore renseignés.
  final int travelMinutes;

  /// Temps de trajet avant le rendez-vous.
  final int travelGoMinutes;

  /// Temps de trajet après le rendez-vous.
  final int travelBackMinutes;

  /// Indique que les temps aller et retour sont enregistrés séparément.
  /// Permet de conserver correctement une valeur explicite de 0 minute.
  final bool usesSeparateTravelTimes;

  /// Marge de sécurité appliquée après le trajet retour.
  final int marginMinutes;

  /// Contexte de départ estimé ou choisi par Zelia.
  /// Exemples : home, work, school, previous_event, unknown.
  final String departureContext;

  /// Contexte d'arrivée estimé ou choisi par Zelia.
  /// Exemples : home, work, school, next_event, unknown.
  final String arrivalContext;

  final bool isRecurring;
  final String recurringType;
  final int recurringWeekday;
  final String recurringUntil;
  final String parentRecurringId;
  final int eventRevision;
  final EventParticipantIdentityLink? participantIdentity;
  final int participantIdentityRevision;

  EventModel({
    this.id,
    required this.title,
    required this.date,
    required this.time,
    required this.notes,
    this.category = "Personnel",
    this.location = "",
    this.locationEntityId,
    required this.createdAt,
    required this.startDateTimeIso,
    this.endTime = "",
    this.endDateTimeIso = "",
    this.durationMinutes = 0,
    this.travelMinutes = 0,
    this.travelGoMinutes = 0,
    this.travelBackMinutes = 0,
    this.usesSeparateTravelTimes = false,
    this.marginMinutes = 0,
    this.departureContext = "unknown",
    this.arrivalContext = "unknown",
    this.isRecurring = false,
    this.recurringType = "",
    this.recurringWeekday = 0,
    this.recurringUntil = "",
    this.parentRecurringId = "",
    this.eventRevision = 1,
    this.participantIdentity,
    int? participantIdentityRevision,
  }) : participantIdentityRevision = participantIdentityRevision ??
            (participantIdentity == null ? 0 : 1) {
    if (eventRevision < 0) {
      throw const FormatException('invalid_event_revision');
    }
    if (location.length > 240 ||
        locationEntityId?.trim().isEmpty == true ||
        (locationEntityId?.length ?? 0) > 200) {
      throw const FormatException('invalid_event_location');
    }
    if (this.participantIdentityRevision < 0 ||
        (participantIdentity != null && this.participantIdentityRevision < 1) ||
        (participantIdentity == null &&
            this.participantIdentityRevision == 1)) {
      throw const FormatException('invalid_participant_identity_revision');
    }
  }

  int get resolvedTravelGoMinutes {
    if (usesSeparateTravelTimes) return travelGoMinutes;
    return travelMinutes;
  }

  int get resolvedTravelBackMinutes {
    if (usesSeparateTravelTimes) return travelBackMinutes;
    return travelMinutes;
  }

  int get totalTravelMinutes {
    return resolvedTravelGoMinutes + resolvedTravelBackMinutes;
  }

  int get totalProtectedMinutes {
    return resolvedTravelGoMinutes +
        durationMinutes +
        resolvedTravelBackMinutes +
        marginMinutes;
  }

  EventModel copyWith({
    String? id,
    bool clearId = false,
    String? title,
    String? date,
    String? time,
    String? notes,
    String? category,
    String? location,
    String? locationEntityId,
    bool clearLocationEntityId = false,
    DateTime? createdAt,
    String? startDateTimeIso,
    String? endTime,
    String? endDateTimeIso,
    int? durationMinutes,
    int? travelMinutes,
    int? travelGoMinutes,
    int? travelBackMinutes,
    bool? usesSeparateTravelTimes,
    int? marginMinutes,
    String? departureContext,
    String? arrivalContext,
    bool? isRecurring,
    String? recurringType,
    int? recurringWeekday,
    String? recurringUntil,
    String? parentRecurringId,
    int? eventRevision,
    EventParticipantIdentityLink? participantIdentity,
    bool clearParticipantIdentity = false,
    int? participantIdentityRevision,
  }) {
    final nextParticipantIdentity = clearParticipantIdentity
        ? null
        : participantIdentity ?? this.participantIdentity;
    final nextParticipantIdentityRevision = participantIdentityRevision ??
        (participantIdentity != null && this.participantIdentity == null
            ? 1
            : this.participantIdentityRevision);
    return EventModel(
      id: clearId ? null : id ?? this.id,
      title: title ?? this.title,
      date: date ?? this.date,
      time: time ?? this.time,
      notes: notes ?? this.notes,
      category: category ?? this.category,
      location: location ?? this.location,
      locationEntityId: clearLocationEntityId
          ? null
          : locationEntityId ?? this.locationEntityId,
      createdAt: createdAt ?? this.createdAt,
      startDateTimeIso: startDateTimeIso ?? this.startDateTimeIso,
      endTime: endTime ?? this.endTime,
      endDateTimeIso: endDateTimeIso ?? this.endDateTimeIso,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      travelMinutes: travelMinutes ?? this.travelMinutes,
      travelGoMinutes: travelGoMinutes ?? this.travelGoMinutes,
      travelBackMinutes: travelBackMinutes ?? this.travelBackMinutes,
      usesSeparateTravelTimes:
          usesSeparateTravelTimes ?? this.usesSeparateTravelTimes,
      marginMinutes: marginMinutes ?? this.marginMinutes,
      departureContext: departureContext ?? this.departureContext,
      arrivalContext: arrivalContext ?? this.arrivalContext,
      isRecurring: isRecurring ?? this.isRecurring,
      recurringType: recurringType ?? this.recurringType,
      recurringWeekday: recurringWeekday ?? this.recurringWeekday,
      recurringUntil: recurringUntil ?? this.recurringUntil,
      parentRecurringId: parentRecurringId ?? this.parentRecurringId,
      eventRevision: eventRevision ?? this.eventRevision,
      participantIdentity: nextParticipantIdentity,
      participantIdentityRevision: nextParticipantIdentityRevision,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) "id": id,
      "title": title,
      "date": date,
      "time": time,
      "notes": notes,
      "category": category,
      "location": location,
      if (locationEntityId != null) "locationEntityId": locationEntityId,
      "createdAt": createdAt.toIso8601String(),
      "startDateTimeIso": startDateTimeIso,
      "endTime": endTime,
      "endDateTimeIso": endDateTimeIso,
      "durationMinutes": durationMinutes,
      "travelMinutes": travelMinutes,
      "travelGoMinutes": travelGoMinutes,
      "travelBackMinutes": travelBackMinutes,
      "usesSeparateTravelTimes": usesSeparateTravelTimes,
      "marginMinutes": marginMinutes,
      "departureContext": departureContext,
      "arrivalContext": arrivalContext,
      "isRecurring": isRecurring,
      "recurringType": recurringType,
      "recurringWeekday": recurringWeekday,
      "recurringUntil": recurringUntil,
      "parentRecurringId": parentRecurringId,
      "eventRevision": eventRevision,
      if (participantIdentity != null)
        "participantIdentity": participantIdentity!.toJson(),
      if (participantIdentityRevision > 0)
        "participantIdentityRevision": participantIdentityRevision,
    };
  }

  factory EventModel.fromJson(Map<String, dynamic> json) {
    final legacyTravel =
        int.tryParse(json["travelMinutes"]?.toString() ?? "0") ?? 0;

    final parsedTravelGo =
        int.tryParse(json["travelGoMinutes"]?.toString() ?? "0") ?? 0;
    final parsedTravelBack =
        int.tryParse(json["travelBackMinutes"]?.toString() ?? "0") ?? 0;

    final usesSeparateTravelTimes = json["usesSeparateTravelTimes"] == true ||
        parsedTravelGo > 0 ||
        parsedTravelBack > 0;

    return EventModel(
      id: json["id"] is String ? json["id"] as String : null,
      title: json["title"] ?? "",
      date: json["date"] ?? "",
      time: json["time"] ?? "",
      notes: json["notes"] ?? "",
      category: json["category"] ?? "Personnel",
      location: json["location"]?.toString() ?? "",
      locationEntityId: _optionalText(json["locationEntityId"]),
      createdAt: DateTime.tryParse(json["createdAt"] ?? "") ?? DateTime.now(),
      startDateTimeIso: json["startDateTimeIso"] ?? "",
      endTime: json["endTime"] ?? "",
      endDateTimeIso: json["endDateTimeIso"] ?? "",
      durationMinutes:
          int.tryParse(json["durationMinutes"]?.toString() ?? "0") ?? 0,
      travelMinutes: legacyTravel,
      travelGoMinutes: parsedTravelGo,
      travelBackMinutes: parsedTravelBack,
      usesSeparateTravelTimes: usesSeparateTravelTimes,
      marginMinutes:
          int.tryParse(json["marginMinutes"]?.toString() ?? "0") ?? 0,
      departureContext: json["departureContext"] ?? "unknown",
      arrivalContext: json["arrivalContext"] ?? "unknown",
      isRecurring: json["isRecurring"] ?? false,
      recurringType: json["recurringType"] ?? "",
      recurringWeekday:
          int.tryParse(json["recurringWeekday"]?.toString() ?? "0") ?? 0,
      recurringUntil: json["recurringUntil"] ?? "",
      parentRecurringId: json["parentRecurringId"] ?? "",
      eventRevision: _eventRevisionFromJson(json),
      participantIdentity: _participantIdentityFromJson(json),
      participantIdentityRevision: _participantIdentityRevisionFromJson(json),
    );
  }

  static int _eventRevisionFromJson(Map<String, dynamic> json) {
    if (!json.containsKey('eventRevision')) return 0;
    final revision = json['eventRevision'];
    if (revision is! int || revision < 0) {
      throw const FormatException('invalid_event_revision');
    }
    return revision;
  }

  static String? _optionalText(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static EventParticipantIdentityLink? _participantIdentityFromJson(
    Map<String, dynamic> json,
  ) {
    final link = EventParticipantIdentityLink.tryFromJson(
      json["participantIdentity"],
    );
    final revision = int.tryParse(
          json["participantIdentityRevision"]?.toString() ?? '',
        ) ??
        (link == null ? 0 : 1);
    if (link == null || revision < 1) return null;
    return link;
  }

  static int _participantIdentityRevisionFromJson(
    Map<String, dynamic> json,
  ) {
    final link = EventParticipantIdentityLink.tryFromJson(
      json["participantIdentity"],
    );
    final revision = int.tryParse(
          json["participantIdentityRevision"]?.toString() ?? '',
        ) ??
        (link == null ? 0 : 1);
    if (link != null && revision >= 1) return revision;
    if (link == null && revision >= 2) return revision;
    return 0;
  }
}
