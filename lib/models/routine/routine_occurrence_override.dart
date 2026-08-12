enum RoutineOccurrenceOverrideType { cancelled, moved, replaced }

/// A durable exception affecting one dated occurrence of a recurring routine.
///
/// The recurring routine remains unchanged. A cancelled or replaced override
/// suppresses only [sourceDateIso]. A moved override projects that occurrence
/// at [replacementDateIso] and [replacementStartTime].
final class RoutineOccurrenceOverride {
  static const int currentSchemaVersion = 1;

  RoutineOccurrenceOverride({
    this.schemaVersion = currentSchemaVersion,
    required this.overrideId,
    required this.accountScopeId,
    required this.routineId,
    required this.sourceDateIso,
    required this.type,
    required this.overrideRevision,
    required this.lastMutationId,
    required this.createdAt,
    required this.updatedAt,
    this.replacementDateIso,
    this.replacementStartTime,
    this.replacementEntityId,
    this.tombstone = false,
  }) {
    final moved = type == RoutineOccurrenceOverrideType.moved;
    final replaced = type == RoutineOccurrenceOverrideType.replaced;
    if (schemaVersion != currentSchemaVersion ||
        overrideId.trim().isEmpty ||
        overrideId.length > 200 ||
        accountScopeId.trim().isEmpty ||
        routineId.trim().isEmpty ||
        routineId.length > 200 ||
        !_validDateIso(sourceDateIso) ||
        overrideRevision < 1 ||
        lastMutationId.trim().isEmpty ||
        lastMutationId.length > 128 ||
        !createdAt.isUtc ||
        !updatedAt.isUtc ||
        updatedAt.isBefore(createdAt) ||
        (overrideRevision == 1 && (tombstone || updatedAt != createdAt)) ||
        (moved &&
            (!_validDateIso(replacementDateIso ?? '') ||
                !_validTime(replacementStartTime ?? ''))) ||
        (!moved &&
            (replacementDateIso != null || replacementStartTime != null)) ||
        (replacementEntityId?.trim().isEmpty == true) ||
        (replacementEntityId?.length ?? 0) > 200 ||
        (!replaced && replacementEntityId != null)) {
      throw const FormatException('invalid_routine_occurrence_override_v1');
    }
  }

  final int schemaVersion;
  final String overrideId;
  final String accountScopeId;
  final String routineId;
  final String sourceDateIso;
  final RoutineOccurrenceOverrideType type;
  final String? replacementDateIso;
  final String? replacementStartTime;
  final String? replacementEntityId;
  final bool tombstone;
  final int overrideRevision;
  final String lastMutationId;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get occurrenceKey => '$routineId:$sourceDateIso';

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'overrideId': overrideId,
        'accountScopeId': accountScopeId,
        'routineId': routineId,
        'sourceDateIso': sourceDateIso,
        'type': type.name,
        'replacementDateIso': replacementDateIso,
        'replacementStartTime': replacementStartTime,
        'replacementEntityId': replacementEntityId,
        'tombstone': tombstone,
        'overrideRevision': overrideRevision,
        'lastMutationId': lastMutationId,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory RoutineOccurrenceOverride.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('invalid_routine_occurrence_override_v1');
    }
    final map = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw const FormatException(
          'invalid_routine_occurrence_override_v1',
        );
      }
      map[entry.key as String] = entry.value;
    }
    final createdAt = DateTime.tryParse(map['createdAt']?.toString() ?? '');
    final updatedAt = DateTime.tryParse(map['updatedAt']?.toString() ?? '');
    final type = RoutineOccurrenceOverrideType.values
        .where((item) => item.name == map['type'])
        .firstOrNull;
    if (createdAt == null || updatedAt == null || type == null) {
      throw const FormatException('invalid_routine_occurrence_override_v1');
    }
    return RoutineOccurrenceOverride(
      schemaVersion: map['schemaVersion'] as int? ?? 0,
      overrideId: map['overrideId']?.toString() ?? '',
      accountScopeId: map['accountScopeId']?.toString() ?? '',
      routineId: map['routineId']?.toString() ?? '',
      sourceDateIso: map['sourceDateIso']?.toString() ?? '',
      type: type,
      replacementDateIso: map['replacementDateIso'] as String?,
      replacementStartTime: map['replacementStartTime'] as String?,
      replacementEntityId: map['replacementEntityId'] as String?,
      tombstone: map['tombstone'] as bool? ?? false,
      overrideRevision: map['overrideRevision'] as int? ?? 0,
      lastMutationId: map['lastMutationId']?.toString() ?? '',
      createdAt: createdAt.toUtc(),
      updatedAt: updatedAt.toUtc(),
    );
  }

  static bool _validTime(String value) =>
      RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(value);

  static bool _validDateIso(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) return false;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final parsed = DateTime.utc(year, month, day);
    return parsed.year == year && parsed.month == month && parsed.day == day;
  }
}
