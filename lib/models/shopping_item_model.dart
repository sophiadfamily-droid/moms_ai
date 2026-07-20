class ShoppingItemModel {
  final String? id;
  final String title;
  final bool isBought;
  final DateTime createdAt;

  final String category;
  final String notes;
  final bool isUrgent;

  // Premium
  final String section;

  ShoppingItemModel({
    this.id,
    required this.title,
    required this.isBought,
    required this.createdAt,
    this.category = "Autre",
    this.notes = "",
    this.isUrgent = false,
    this.section = "Aujourd’hui",
  });

  ShoppingItemModel copyWith({
    String? id,
    String? title,
    bool? isBought,
    DateTime? createdAt,
    String? category,
    String? notes,
    bool? isUrgent,
    String? section,
  }) {
    return ShoppingItemModel(
      id: id ?? this.id,
      title: title ?? this.title,
      isBought: isBought ?? this.isBought,
      createdAt: createdAt ?? this.createdAt,
      category: category ?? this.category,
      notes: notes ?? this.notes,
      isUrgent: isUrgent ?? this.isUrgent,
      section: section ?? this.section,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) "id": id,
      "title": title,
      "isBought": isBought,
      "createdAt": createdAt.toIso8601String(),
      "category": category,
      "notes": notes,
      "isUrgent": isUrgent,
      "section": section,
    };
  }

  factory ShoppingItemModel.fromJson(
    Map<String, dynamic> json,
  ) {
    return ShoppingItemModel(
      id: json["id"] is String ? json["id"] as String : null,
      title: json["title"] ?? "",
      isBought: json["isBought"] ?? false,
      createdAt: DateTime.tryParse(json["createdAt"] ?? "") ?? DateTime.now(),
      category: json["category"] ?? "Autre",
      notes: json["notes"] ?? "",
      isUrgent: json["isUrgent"] ?? false,
      section: json["section"] ?? "Aujourd’hui",
    );
  }
}
