class TaskModel {
  final String? id;
  final String title;
  final String category;
  final bool isDone;
  final DateTime createdAt;

  final bool isImportant;
  final String dueDate;
  final String notes;
  final int? durationMinutes;

  // Premium organisation
  // Exemples : Aujourd’hui, Cette semaine, Ce mois-ci, Plus tard
  final String planning;
  final String priority;

  TaskModel({
    this.id,
    required this.title,
    required this.category,
    required this.isDone,
    required this.createdAt,
    this.isImportant = false,
    this.dueDate = "",
    this.notes = "",
    this.durationMinutes,
    this.planning = "Cette semaine",
    this.priority = "Normale",
  }) {
    if (durationMinutes != null &&
        (durationMinutes! <= 0 || durationMinutes! > 10080)) {
      throw const FormatException('invalid_task_duration');
    }
  }

  TaskModel copyWith({
    String? id,
    String? title,
    String? category,
    bool? isDone,
    DateTime? createdAt,
    bool? isImportant,
    String? dueDate,
    String? notes,
    int? durationMinutes,
    bool clearDuration = false,
    String? planning,
    String? priority,
  }) {
    return TaskModel(
      id: id ?? this.id,
      title: title ?? this.title,
      category: category ?? this.category,
      isDone: isDone ?? this.isDone,
      createdAt: createdAt ?? this.createdAt,
      isImportant: isImportant ?? this.isImportant,
      dueDate: dueDate ?? this.dueDate,
      notes: notes ?? this.notes,
      durationMinutes:
          clearDuration ? null : durationMinutes ?? this.durationMinutes,
      planning: planning ?? this.planning,
      priority: priority ?? this.priority,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) "id": id,
      "title": title,
      "category": category,
      "isDone": isDone,
      "createdAt": createdAt.toIso8601String(),
      "isImportant": isImportant,
      "dueDate": dueDate,
      "notes": notes,
      if (durationMinutes != null) "durationMinutes": durationMinutes,
      "planning": planning,
      "priority": priority,
    };
  }

  factory TaskModel.fromJson(
    Map<String, dynamic> json,
  ) {
    final rawDuration = json["durationMinutes"];
    final parsedDuration = rawDuration is num
        ? rawDuration.toInt()
        : int.tryParse(rawDuration?.toString() ?? '');
    final durationMinutes =
        parsedDuration != null && parsedDuration > 0 && parsedDuration <= 10080
            ? parsedDuration
            : null;
    return TaskModel(
      id: json["id"] is String ? json["id"] as String : null,
      title: json["title"] ?? "",
      category: json["category"] ?? "Perso",
      isDone: json["isDone"] ?? false,
      createdAt: DateTime.tryParse(
            json["createdAt"] ?? "",
          ) ??
          DateTime.now(),
      isImportant: json["isImportant"] ?? false,
      dueDate: json["dueDate"] ?? "",
      notes: json["notes"] ?? "",
      durationMinutes: durationMinutes,
      planning: json["planning"] ?? "Cette semaine",
      priority: json["priority"] ?? "Normale",
    );
  }
}
