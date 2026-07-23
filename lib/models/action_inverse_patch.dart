sealed class ActionInversePatch {
  const ActionInversePatch();

  String get type;
  Map<String, Object?> toJson();

  static ActionInversePatch fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    return switch (type) {
      'task' => TaskInversePatch.fromJson(json),
      'shopping' => ShoppingInversePatch.fromJson(json),
      'profile' => ProfileInversePatch.fromJson(json),
      'memory' => MemoryInversePatch.fromJson(json),
      _ => throw const FormatException('unknown_action_inverse_patch'),
    };
  }
}

final class MemoryInversePatch extends ActionInversePatch {
  MemoryInversePatch({
    required this.text,
    required this.normalizedText,
    required this.lifecycleStatus,
    required this.confirmationStatus,
    required this.wasTombstone,
    required this.isHealth,
  }) {
    if (text.isEmpty ||
        normalizedText.isEmpty ||
        text.length > 4000 ||
        normalizedText.length > 4000 ||
        lifecycleStatus.length > 40 ||
        confirmationStatus.length > 40) {
      throw const FormatException('invalid_memory_inverse_patch');
    }
  }

  final String text;
  final String normalizedText;
  final String lifecycleStatus;
  final String confirmationStatus;
  final bool wasTombstone;
  final bool isHealth;

  @override
  String get type => 'memory';

  @override
  Map<String, Object?> toJson() => {
        'type': type,
        'text': text,
        'normalizedText': normalizedText,
        'lifecycleStatus': lifecycleStatus,
        'confirmationStatus': confirmationStatus,
        'wasTombstone': wasTombstone,
        'isHealth': isHealth,
      };

  factory MemoryInversePatch.fromJson(Map<String, dynamic> json) {
    const keys = {
      'type',
      'text',
      'normalizedText',
      'lifecycleStatus',
      'confirmationStatus',
      'wasTombstone',
      'isHealth',
    };
    if (json.keys.any((key) => !keys.contains(key))) {
      throw const FormatException('invalid_memory_inverse_patch');
    }
    return MemoryInversePatch(
      text: json['text'] as String,
      normalizedText: json['normalizedText'] as String,
      lifecycleStatus: json['lifecycleStatus'] as String,
      confirmationStatus: json['confirmationStatus'] as String,
      wasTombstone: json['wasTombstone'] as bool,
      isHealth: json['isHealth'] as bool,
    );
  }
}

final class TaskInversePatch extends ActionInversePatch {
  const TaskInversePatch({
    required this.title,
    required this.category,
    required this.isDone,
    required this.createdAt,
    required this.isImportant,
    required this.dueDate,
    required this.notes,
    required this.planning,
    required this.priority,
    required this.wasTombstone,
  });

  final String title;
  final String category;
  final bool isDone;
  final DateTime createdAt;
  final bool isImportant;
  final String dueDate;
  final String notes;
  final String planning;
  final String priority;
  final bool wasTombstone;

  @override
  String get type => 'task';

  void validate() {
    if (title.length > 500 ||
        category.length > 100 ||
        dueDate.length > 100 ||
        notes.length > 2000 ||
        planning.length > 100 ||
        priority.length > 100) {
      throw const FormatException('action_inverse_patch_too_large');
    }
  }

  @override
  Map<String, Object?> toJson() {
    validate();
    return {
      'type': type,
      'title': title,
      'category': category,
      'isDone': isDone,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'isImportant': isImportant,
      'dueDate': dueDate,
      'notes': notes,
      'planning': planning,
      'priority': priority,
      'wasTombstone': wasTombstone,
    };
  }

  factory TaskInversePatch.fromJson(Map<String, dynamic> json) {
    const keys = {
      'type',
      'title',
      'category',
      'isDone',
      'createdAt',
      'isImportant',
      'dueDate',
      'notes',
      'planning',
      'priority',
      'wasTombstone',
    };
    if (json.keys.any((key) => !keys.contains(key))) {
      throw const FormatException('invalid_task_inverse_patch');
    }
    final patch = TaskInversePatch(
      title: json['title'] as String,
      category: json['category'] as String,
      isDone: json['isDone'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      isImportant: json['isImportant'] as bool,
      dueDate: json['dueDate'] as String,
      notes: json['notes'] as String,
      planning: json['planning'] as String,
      priority: json['priority'] as String,
      wasTombstone: json['wasTombstone'] as bool,
    );
    patch.validate();
    return patch;
  }
}

final class ShoppingInversePatch extends ActionInversePatch {
  const ShoppingInversePatch({
    required this.title,
    required this.isBought,
    required this.createdAt,
    required this.category,
    required this.notes,
    required this.isUrgent,
    required this.section,
    required this.wasTombstone,
    required this.clearGeneration,
  });

  final String title;
  final bool isBought;
  final DateTime createdAt;
  final String category;
  final String notes;
  final bool isUrgent;
  final String section;
  final bool wasTombstone;
  final int clearGeneration;

  @override
  String get type => 'shopping';

  void validate() {
    if (title.length > 500 ||
        category.length > 100 ||
        notes.length > 2000 ||
        section.length > 100 ||
        clearGeneration < 0) {
      throw const FormatException('action_inverse_patch_too_large');
    }
  }

  @override
  Map<String, Object?> toJson() {
    validate();
    return {
      'type': type,
      'title': title,
      'isBought': isBought,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'category': category,
      'notes': notes,
      'isUrgent': isUrgent,
      'section': section,
      'wasTombstone': wasTombstone,
      'clearGeneration': clearGeneration,
    };
  }

  factory ShoppingInversePatch.fromJson(Map<String, dynamic> json) {
    const keys = {
      'type',
      'title',
      'isBought',
      'createdAt',
      'category',
      'notes',
      'isUrgent',
      'section',
      'wasTombstone',
      'clearGeneration',
    };
    if (json.keys.any((key) => !keys.contains(key))) {
      throw const FormatException('invalid_shopping_inverse_patch');
    }
    final patch = ShoppingInversePatch(
      title: json['title'] as String,
      isBought: json['isBought'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      category: json['category'] as String,
      notes: json['notes'] as String,
      isUrgent: json['isUrgent'] as bool,
      section: json['section'] as String,
      wasTombstone: json['wasTombstone'] as bool,
      clearGeneration: json['clearGeneration'] as int,
    );
    patch.validate();
    return patch;
  }
}

enum ProfileOwnedPatchField {
  workStatus,
  wantsNotifications,
  workHours,
  workScheduleType,
  workDays,
  morningStart,
  morningEnd,
  afternoonStart,
  afternoonEnd,
  variableWorkDetails,
  habits,
  personalNotes,
  preferences,
  goals,
  aiTone,
  planningStyle,
  notificationLevel,
  mainLifePriority,
  spokenLanguage,
  country,
  timeZone,
  personalGoals,
  businessGoals,
  familyGoals,
  vehicleInfo,
  petsInfo,
  transportInfo,
  childcareInfo,
  foodPreferences,
  adminNotes,
  budgetNotes,
  importantPlaces,
}

sealed class ProfilePatchValue {
  const ProfilePatchValue();

  String get kind;
  Object? get value;

  Map<String, Object?> toJson() => {'kind': kind, 'value': value};

  static ProfilePatchValue fromJson(Map<String, dynamic> json) {
    if (json.keys.any((key) => key != 'kind' && key != 'value')) {
      throw const FormatException('invalid_profile_patch_value');
    }
    return switch (json['kind']) {
      'null' when json['value'] == null => const NullProfilePatchValue(),
      'string' => StringProfilePatchValue(json['value'] as String),
      'bool' => BoolProfilePatchValue(json['value'] as bool),
      'stringList' => StringListProfilePatchValue(
          List<String>.from(json['value'] as List),
        ),
      _ => throw const FormatException('invalid_profile_patch_value'),
    };
  }

  static ProfilePatchValue fromOwnedValue(Object? value) => switch (value) {
        null => const NullProfilePatchValue(),
        String() => StringProfilePatchValue(value),
        bool() => BoolProfilePatchValue(value),
        List() when value.every((item) => item is String) =>
          StringListProfilePatchValue(List<String>.from(value)),
        _ => throw const FormatException('unsupported_profile_patch_value'),
      };
}

final class NullProfilePatchValue extends ProfilePatchValue {
  const NullProfilePatchValue();
  @override
  String get kind => 'null';
  @override
  Object? get value => null;
}

final class StringProfilePatchValue extends ProfilePatchValue {
  StringProfilePatchValue(this.value) {
    if (value.length > 2000) {
      throw const FormatException('profile_patch_value_too_large');
    }
  }
  @override
  final String value;
  @override
  String get kind => 'string';
}

final class BoolProfilePatchValue extends ProfilePatchValue {
  const BoolProfilePatchValue(this.value);
  @override
  final bool value;
  @override
  String get kind => 'bool';
}

final class StringListProfilePatchValue extends ProfilePatchValue {
  StringListProfilePatchValue(List<String> value)
      : value = List.unmodifiable(value) {
    if (value.length > 32 || value.any((item) => item.length > 200)) {
      throw const FormatException('profile_patch_value_too_large');
    }
  }
  @override
  final List<String> value;
  @override
  String get kind => 'stringList';
}

final class ProfileInversePatchEntry {
  const ProfileInversePatchEntry({required this.field, required this.value});

  final ProfileOwnedPatchField field;
  final ProfilePatchValue value;

  Map<String, Object?> toJson() => {
        'field': field.name,
        'value': value.toJson(),
      };

  factory ProfileInversePatchEntry.fromJson(Map<String, dynamic> json) {
    if (json.keys.any((key) => key != 'field' && key != 'value')) {
      throw const FormatException('invalid_profile_inverse_patch_entry');
    }
    try {
      return ProfileInversePatchEntry(
        field: ProfileOwnedPatchField.values.byName(json['field'] as String),
        value: ProfilePatchValue.fromJson(
          Map<String, dynamic>.from(json['value'] as Map),
        ),
      );
    } on Object {
      throw const FormatException('invalid_profile_inverse_patch_entry');
    }
  }
}

final class ProfileInversePatch extends ActionInversePatch {
  ProfileInversePatch(List<ProfileInversePatchEntry> entries)
      : entries = List.unmodifiable(entries) {
    final fields = entries.map((entry) => entry.field).toSet();
    if (entries.isEmpty ||
        entries.length > 32 ||
        fields.length != entries.length) {
      throw const FormatException('invalid_profile_inverse_patch');
    }
  }

  final List<ProfileInversePatchEntry> entries;

  @override
  String get type => 'profile';

  @override
  Map<String, Object?> toJson() => {
        'type': type,
        'entries': entries.map((entry) => entry.toJson()).toList(),
      };

  factory ProfileInversePatch.fromJson(Map<String, dynamic> json) {
    if (json.keys.any((key) => key != 'type' && key != 'entries')) {
      throw const FormatException('invalid_profile_inverse_patch');
    }
    return ProfileInversePatch(
      (json['entries'] as List)
          .map(
            (entry) => ProfileInversePatchEntry.fromJson(
              Map<String, dynamic>.from(entry as Map),
            ),
          )
          .toList(growable: false),
    );
  }
}
