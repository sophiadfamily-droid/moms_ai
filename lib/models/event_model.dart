class EventModel {
  final String title;
  final String date;
  final String time;
  final String notes;
  final String category;
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

  EventModel({
    required this.title,
    required this.date,
    required this.time,
    required this.notes,
    this.category = "Personnel",
    required this.createdAt,
    required this.startDateTimeIso,
    this.endTime = "",
    this.endDateTimeIso = "",
    this.durationMinutes = 0,
    this.travelMinutes = 0,
    this.travelGoMinutes = 0,
    this.travelBackMinutes = 0,
    this.departureContext = "unknown",
    this.arrivalContext = "unknown",
    this.isRecurring = false,
    this.recurringType = "",
    this.recurringWeekday = 0,
    this.recurringUntil = "",
    this.parentRecurringId = "",
  });

  int get resolvedTravelGoMinutes {
    if (travelGoMinutes > 0) return travelGoMinutes;
    return travelMinutes;
  }

  int get resolvedTravelBackMinutes {
    if (travelBackMinutes > 0) return travelBackMinutes;
    return travelMinutes;
  }

  int get totalTravelMinutes {
    return resolvedTravelGoMinutes + resolvedTravelBackMinutes;
  }

  EventModel copyWith({
    String? title,
    String? date,
    String? time,
    String? notes,
    String? category,
    DateTime? createdAt,
    String? startDateTimeIso,
    String? endTime,
    String? endDateTimeIso,
    int? durationMinutes,
    int? travelMinutes,
    int? travelGoMinutes,
    int? travelBackMinutes,
    String? departureContext,
    String? arrivalContext,
    bool? isRecurring,
    String? recurringType,
    int? recurringWeekday,
    String? recurringUntil,
    String? parentRecurringId,
  }) {
    return EventModel(
      title: title ?? this.title,
      date: date ?? this.date,
      time: time ?? this.time,
      notes: notes ?? this.notes,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
      startDateTimeIso: startDateTimeIso ?? this.startDateTimeIso,
      endTime: endTime ?? this.endTime,
      endDateTimeIso: endDateTimeIso ?? this.endDateTimeIso,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      travelMinutes: travelMinutes ?? this.travelMinutes,
      travelGoMinutes: travelGoMinutes ?? this.travelGoMinutes,
      travelBackMinutes: travelBackMinutes ?? this.travelBackMinutes,
      departureContext: departureContext ?? this.departureContext,
      arrivalContext: arrivalContext ?? this.arrivalContext,
      isRecurring: isRecurring ?? this.isRecurring,
      recurringType: recurringType ?? this.recurringType,
      recurringWeekday: recurringWeekday ?? this.recurringWeekday,
      recurringUntil: recurringUntil ?? this.recurringUntil,
      parentRecurringId: parentRecurringId ?? this.parentRecurringId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "title": title,
      "date": date,
      "time": time,
      "notes": notes,
      "category": category,
      "createdAt": createdAt.toIso8601String(),
      "startDateTimeIso": startDateTimeIso,
      "endTime": endTime,
      "endDateTimeIso": endDateTimeIso,
      "durationMinutes": durationMinutes,
      "travelMinutes": travelMinutes,
      "travelGoMinutes": travelGoMinutes,
      "travelBackMinutes": travelBackMinutes,
      "departureContext": departureContext,
      "arrivalContext": arrivalContext,
      "isRecurring": isRecurring,
      "recurringType": recurringType,
      "recurringWeekday": recurringWeekday,
      "recurringUntil": recurringUntil,
      "parentRecurringId": parentRecurringId,
    };
  }

  factory EventModel.fromJson(Map<String, dynamic> json) {
    final legacyTravel =
        int.tryParse(json["travelMinutes"]?.toString() ?? "0") ?? 0;

    return EventModel(
      title: json["title"] ?? "",
      date: json["date"] ?? "",
      time: json["time"] ?? "",
      notes: json["notes"] ?? "",
      category: json["category"] ?? "Personnel",
      createdAt: DateTime.tryParse(json["createdAt"] ?? "") ?? DateTime.now(),
      startDateTimeIso: json["startDateTimeIso"] ?? "",
      endTime: json["endTime"] ?? "",
      endDateTimeIso: json["endDateTimeIso"] ?? "",
      durationMinutes:
          int.tryParse(json["durationMinutes"]?.toString() ?? "0") ?? 0,
      travelMinutes: legacyTravel,
      travelGoMinutes:
          int.tryParse(json["travelGoMinutes"]?.toString() ?? "0") ??
              legacyTravel,
      travelBackMinutes:
          int.tryParse(json["travelBackMinutes"]?.toString() ?? "0") ??
              legacyTravel,
      departureContext: json["departureContext"] ?? "unknown",
      arrivalContext: json["arrivalContext"] ?? "unknown",
      isRecurring: json["isRecurring"] ?? false,
      recurringType: json["recurringType"] ?? "",
      recurringWeekday:
          int.tryParse(json["recurringWeekday"]?.toString() ?? "0") ?? 0,
      recurringUntil: json["recurringUntil"] ?? "",
      parentRecurringId: json["parentRecurringId"] ?? "",
    );
  }
}
