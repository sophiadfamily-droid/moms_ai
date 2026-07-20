class TaskModel {
  final String? id;
  final String title;
  final String category;
  final bool isDone;
  final DateTime createdAt;

  final bool isImportant;
  final String dueDate;
  final String notes;

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
    this.planning = "Cette semaine",
    this.priority = "Normale",
  });

  TaskModel copyWith({
    String? id,
    String? title,
    String? category,
    bool? isDone,
    DateTime? createdAt,
    bool? isImportant,
    String? dueDate,
    String? notes,
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
      "planning": planning,
      "priority": priority,
    };
  }

  factory TaskModel.fromJson(
    Map<String, dynamic> json,
  ) {
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
      planning: json["planning"] ?? "Cette semaine",
      priority: json["priority"] ?? "Normale",
    );
  }
}
