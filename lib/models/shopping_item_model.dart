class ShoppingItemModel {
  final String title;
  final bool isBought;
  final DateTime createdAt;

  final String category;
  final String notes;
  final bool isUrgent;

  // Premium
  final String section;

  ShoppingItemModel({
    required this.title,
    required this.isBought,
    required this.createdAt,
    this.category = "Autre",
    this.notes = "",
    this.isUrgent = false,
    this.section = "Aujourd’hui",
  });

  ShoppingItemModel copyWith({
    String? title,
    bool? isBought,
    DateTime? createdAt,
    String? category,
    String? notes,
    bool? isUrgent,
    String? section,
  }) {
    return ShoppingItemModel(
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
      title: json["title"] ?? "",
      isBought: json["isBought"] ?? false,
      createdAt:
          DateTime.tryParse(json["createdAt"] ?? "") ??
              DateTime.now(),
      category: json["category"] ?? "Autre",
      notes: json["notes"] ?? "",
      isUrgent: json["isUrgent"] ?? false,
      section: json["section"] ?? "Aujourd’hui",
    );
  }
}
