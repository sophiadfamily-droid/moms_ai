class PlanningDraftModel {
  final String id;
  final String sourceMessage;
  final String title;
  final String type;
  final String category;

  final String dateIso;
  final String periodLabel;
  final String time;
  final int durationMinutes;
  final int travelGoMinutes;
  final int travelBackMinutes;
  final int marginMinutes;

  final bool isOutside;
  final bool isRecurring;
  final String recurringType;
  final int recurringWeekday;
  final String recurringUntil;

  final bool needsDate;
  final bool needsTime;
  final bool needsDuration;
  final bool needsTravel;
  final bool needsConfirmation;

  final double confidence;
  final String status;
  final String source;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const PlanningDraftModel({
    required this.id,
    required this.sourceMessage,
    required this.title,
    required this.type,
    required this.category,
    required this.dateIso,
    required this.periodLabel,
    required this.time,
    required this.durationMinutes,
    required this.travelGoMinutes,
    required this.travelBackMinutes,
    required this.marginMinutes,
    required this.isOutside,
    required this.isRecurring,
    required this.recurringType,
    required this.recurringWeekday,
    required this.recurringUntil,
    required this.needsDate,
    required this.needsTime,
    required this.needsDuration,
    required this.needsTravel,
    required this.needsConfirmation,
    required this.confidence,
    required this.status,
    required this.source,
    required this.createdAt,
    this.updatedAt,
  });

  factory PlanningDraftModel.empty() {
    return PlanningDraftModel(
      id: "",
      sourceMessage: "",
      title: "",
      type: "",
      category: "",
      dateIso: "",
      periodLabel: "",
      time: "",
      durationMinutes: 0,
      travelGoMinutes: 0,
      travelBackMinutes: 0,
      marginMinutes: 0,
      isOutside: false,
      isRecurring: false,
      recurringType: "",
      recurringWeekday: 0,
      recurringUntil: "",
      needsDate: true,
      needsTime: true,
      needsDuration: true,
      needsTravel: false,
      needsConfirmation: true,
      confidence: 0,
      status: "empty",
      source: "unknown",
      createdAt: DateTime.now(),
      updatedAt: null,
    );
  }

  factory PlanningDraftModel.fromAction({
    required Map<String, dynamic> action,
    required String sourceMessage,
    required String resolvedDateIso,
    required String resolvedTime,
    required int resolvedDurationMinutes,
    required bool needsTravel,
    double confidence = 0,
    String source = "action_handler",
  }) {
    final title = action["title"]?.toString().trim() ?? "";
    final type = action["type"]?.toString().trim() ?? "";
    final category = action["category"]?.toString().trim() ?? "";

    final dateIso = resolvedDateIso.trim();
    final time = resolvedTime.trim();
    final durationMinutes = resolvedDurationMinutes;

    return PlanningDraftModel(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      sourceMessage: sourceMessage,
      title: title.isNotEmpty ? title : "Rendez-vous",
      type: type.isNotEmpty ? type : "event",
      category: category.isNotEmpty ? category : "Personnel",
      dateIso: dateIso,
      periodLabel: action["planning"]?.toString() ?? "",
      time: time,
      durationMinutes: durationMinutes,
      travelGoMinutes: int.tryParse(
            action["travelGoMinutes"]?.toString() ??
                action["travelMinutes"]?.toString() ??
                "0",
          ) ??
          0,
      travelBackMinutes: int.tryParse(
            action["travelBackMinutes"]?.toString() ?? "0",
          ) ??
          0,
      marginMinutes:
          int.tryParse(action["marginMinutes"]?.toString() ?? "0") ?? 0,
      isOutside: needsTravel,
      isRecurring: action["isRecurring"] == true,
      recurringType: action["recurringType"]?.toString() ?? "",
      recurringWeekday: int.tryParse(
            action["recurringWeekday"]?.toString() ?? "0",
          ) ??
          0,
      recurringUntil: action["recurringUntil"]?.toString() ?? "",
      needsDate: dateIso.isEmpty,
      needsTime: time.isEmpty,
      needsDuration: durationMinutes <= 0,
      needsTravel: needsTravel,
      needsConfirmation: true,
      confidence: confidence,
      status: "draft",
      source: source,
      createdAt: DateTime.now(),
      updatedAt: null,
    );
  }

  PlanningDraftModel copyWith({
    String? id,
    String? sourceMessage,
    String? title,
    String? type,
    String? category,
    String? dateIso,
    String? periodLabel,
    String? time,
    int? durationMinutes,
    int? travelGoMinutes,
    int? travelBackMinutes,
    int? marginMinutes,
    bool? isOutside,
    bool? isRecurring,
    String? recurringType,
    int? recurringWeekday,
    String? recurringUntil,
    bool? needsDate,
    bool? needsTime,
    bool? needsDuration,
    bool? needsTravel,
    bool? needsConfirmation,
    double? confidence,
    String? status,
    String? source,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PlanningDraftModel(
      id: id ?? this.id,
      sourceMessage: sourceMessage ?? this.sourceMessage,
      title: title ?? this.title,
      type: type ?? this.type,
      category: category ?? this.category,
      dateIso: dateIso ?? this.dateIso,
      periodLabel: periodLabel ?? this.periodLabel,
      time: time ?? this.time,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      travelGoMinutes: travelGoMinutes ?? this.travelGoMinutes,
      travelBackMinutes: travelBackMinutes ?? this.travelBackMinutes,
      marginMinutes: marginMinutes ?? this.marginMinutes,
      isOutside: isOutside ?? this.isOutside,
      isRecurring: isRecurring ?? this.isRecurring,
      recurringType: recurringType ?? this.recurringType,
      recurringWeekday: recurringWeekday ?? this.recurringWeekday,
      recurringUntil: recurringUntil ?? this.recurringUntil,
      needsDate: needsDate ?? this.needsDate,
      needsTime: needsTime ?? this.needsTime,
      needsDuration: needsDuration ?? this.needsDuration,
      needsTravel: needsTravel ?? this.needsTravel,
      needsConfirmation: needsConfirmation ?? this.needsConfirmation,
      confidence: confidence ?? this.confidence,
      status: status ?? this.status,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  PlanningDraftModel markUpdated() {
    return copyWith(updatedAt: DateTime.now());
  }

  PlanningDraftModel withDate(String value) {
    return copyWith(
      dateIso: value,
      needsDate: value.trim().isEmpty,
      updatedAt: DateTime.now(),
    );
  }

  PlanningDraftModel withTime(String value) {
    return copyWith(
      time: value,
      needsTime: value.trim().isEmpty,
      updatedAt: DateTime.now(),
    );
  }

  PlanningDraftModel withDuration(int minutes) {
    return copyWith(
      durationMinutes: minutes,
      needsDuration: minutes <= 0,
      updatedAt: DateTime.now(),
    );
  }

  PlanningDraftModel withTravel({
    required int goMinutes,
    required int backMinutes,
  }) {
    return copyWith(
      travelGoMinutes: goMinutes,
      travelBackMinutes: backMinutes,
      needsTravel: false,
      updatedAt: DateTime.now(),
    );
  }

  bool get isReadyForProposal {
    return !needsDate && !needsTime && !needsDuration && !needsTravel;
  }

  bool get isReadyForCalendarCreation {
    return isReadyForProposal && needsConfirmation == false;
  }

  int get totalTravelMinutes {
    return travelGoMinutes + travelBackMinutes;
  }

  int get totalEstimatedMinutes {
    return durationMinutes + totalTravelMinutes + marginMinutes;
  }

  String get nextMissingStep {
    if (needsDate) return "date";
    if (needsTime) return "time";
    if (needsDuration) return "duration";
    if (needsTravel) return "travel";
    if (needsConfirmation) return "confirmation";
    return "ready";
  }

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "sourceMessage": sourceMessage,
      "title": title,
      "type": type,
      "category": category,
      "dateIso": dateIso,
      "periodLabel": periodLabel,
      "time": time,
      "durationMinutes": durationMinutes,
      "travelGoMinutes": travelGoMinutes,
      "travelBackMinutes": travelBackMinutes,
      "marginMinutes": marginMinutes,
      "isOutside": isOutside,
      "isRecurring": isRecurring,
      "recurringType": recurringType,
      "recurringWeekday": recurringWeekday,
      "recurringUntil": recurringUntil,
      "needsDate": needsDate,
      "needsTime": needsTime,
      "needsDuration": needsDuration,
      "needsTravel": needsTravel,
      "needsConfirmation": needsConfirmation,
      "confidence": confidence,
      "status": status,
      "source": source,
      "createdAt": createdAt.toIso8601String(),
      "updatedAt": updatedAt?.toIso8601String(),
    };
  }

  factory PlanningDraftModel.fromJson(Map<String, dynamic> json) {
    return PlanningDraftModel(
      id: json["id"]?.toString() ?? "",
      sourceMessage: json["sourceMessage"]?.toString() ?? "",
      title: json["title"]?.toString() ?? "",
      type: json["type"]?.toString() ?? "",
      category: json["category"]?.toString() ?? "",
      dateIso: json["dateIso"]?.toString() ?? "",
      periodLabel: json["periodLabel"]?.toString() ?? "",
      time: json["time"]?.toString() ?? "",
      durationMinutes:
          int.tryParse(json["durationMinutes"]?.toString() ?? "0") ?? 0,
      travelGoMinutes:
          int.tryParse(json["travelGoMinutes"]?.toString() ?? "0") ?? 0,
      travelBackMinutes:
          int.tryParse(json["travelBackMinutes"]?.toString() ?? "0") ?? 0,
      marginMinutes:
          int.tryParse(json["marginMinutes"]?.toString() ?? "0") ?? 0,
      isOutside: json["isOutside"] == true,
      isRecurring: json["isRecurring"] == true,
      recurringType: json["recurringType"]?.toString() ?? "",
      recurringWeekday:
          int.tryParse(json["recurringWeekday"]?.toString() ?? "0") ?? 0,
      recurringUntil: json["recurringUntil"]?.toString() ?? "",
      needsDate: json["needsDate"] == true,
      needsTime: json["needsTime"] == true,
      needsDuration: json["needsDuration"] == true,
      needsTravel: json["needsTravel"] == true,
      needsConfirmation: json["needsConfirmation"] != false,
      confidence: double.tryParse(json["confidence"]?.toString() ?? "0") ?? 0,
      status: json["status"]?.toString() ?? "draft",
      source: json["source"]?.toString() ?? "unknown",
      createdAt: DateTime.tryParse(json["createdAt"]?.toString() ?? "") ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json["updatedAt"]?.toString() ?? ""),
    );
  }
}
