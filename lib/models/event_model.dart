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
  final int travelMinutes;

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
    this.isRecurring = false,
    this.recurringType = "",
    this.recurringWeekday = 0,
    this.recurringUntil = "",
    this.parentRecurringId = "",
  });

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
      "isRecurring": isRecurring,
      "recurringType": recurringType,
      "recurringWeekday": recurringWeekday,
      "recurringUntil": recurringUntil,
      "parentRecurringId": parentRecurringId,
    };
  }

  factory EventModel.fromJson(Map<String, dynamic> json) {
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
      durationMinutes: json["durationMinutes"] ?? 0,
      travelMinutes: json["travelMinutes"] ?? 0,
      isRecurring: json["isRecurring"] ?? false,
      recurringType: json["recurringType"] ?? "",
      recurringWeekday: json["recurringWeekday"] ?? 0,
      recurringUntil: json["recurringUntil"] ?? "",
      parentRecurringId: json["parentRecurringId"] ?? "",
    );
  }
}
