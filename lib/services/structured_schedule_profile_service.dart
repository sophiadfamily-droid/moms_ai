import '../models/human/human_model.dart';

final class StructuredScheduleProfileEntry {
  const StructuredScheduleProfileEntry({
    required this.sourceKey,
    required this.target,
    required this.temporalKind,
    required this.title,
    required this.weekdays,
    required this.startTime,
    required this.endTime,
    this.dateIso,
    this.place,
    this.endsNextDay = false,
  });

  final String sourceKey;
  final String target;
  final String temporalKind;
  final String title;
  final List<int> weekdays;
  final String startTime;
  final String endTime;
  final String? dateIso;
  final String? place;
  final bool endsNextDay;

  bool get isDated => temporalKind == 'dated' && dateIso != null;

  bool isExpiredAt(DateTime instant) {
    if (!isDated) return false;
    final date = DateTime.tryParse(dateIso!);
    final end = _clock(endTime);
    if (date == null || end == null) return false;
    var endAt = DateTime(date.year, date.month, date.day, end.$1, end.$2);
    final start = _clock(startTime);
    if (endsNextDay ||
        (start != null &&
            endAt.hour * 60 + endAt.minute <= start.$1 * 60 + start.$2)) {
      endAt = endAt.add(const Duration(days: 1));
    }
    return instant.isAfter(endAt);
  }

  static (int, int)? _clock(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return (hour, minute);
  }

  static StructuredScheduleProfileEntry? fromJson(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, Object?>.from(value);
    final sourceKey = map['sourceKey']?.toString().trim() ?? '';
    final target = map['target']?.toString().trim() ?? '';
    final temporalKind = map['temporalKind']?.toString().trim() ?? '';
    final title = map['title']?.toString().trim() ?? '';
    final startTime = map['startTime']?.toString().trim() ?? '';
    final endTime = map['endTime']?.toString().trim() ?? '';
    if (sourceKey.isEmpty ||
        target.isEmpty ||
        temporalKind.isEmpty ||
        title.isEmpty ||
        startTime.isEmpty ||
        endTime.isEmpty) {
      return null;
    }
    return StructuredScheduleProfileEntry(
      sourceKey: sourceKey,
      target: target,
      temporalKind: temporalKind,
      title: title,
      dateIso: map['dateIso']?.toString().trim(),
      weekdays: map['weekdays'] is List
          ? (map['weekdays'] as List)
              .map((item) => int.tryParse(item.toString()))
              .whereType<int>()
              .toList(growable: false)
          : const [],
      startTime: startTime,
      endTime: endTime,
      place: map['place']?.toString().trim(),
      endsNextDay: map['endsNextDay'] == true,
    );
  }
}

abstract final class StructuredScheduleProfileService {
  static const storageField = 'structuredSchedulesV1';

  static List<StructuredScheduleProfileEntry> entriesForPerson(
    HumanPerson person, {
    required DateTime at,
  }) {
    final raw = person.customFields[storageField];
    if (raw is! List) return const [];
    final entries = raw
        .map(StructuredScheduleProfileEntry.fromJson)
        .whereType<StructuredScheduleProfileEntry>()
        .where((entry) => !entry.isExpiredAt(at))
        .toList(growable: false);
    entries.sort((a, b) {
      final byDate = (a.dateIso ?? '').compareTo(b.dateIso ?? '');
      return byDate != 0 ? byDate : a.startTime.compareTo(b.startTime);
    });
    return entries;
  }

  static HumanModel pruneExpired(HumanModel model, {required DateTime at}) {
    var changed = false;
    final persons = model.persons.map((person) {
      final raw = person.customFields[storageField];
      if (raw is! List) return person;
      final kept = raw.where((item) {
        final entry = StructuredScheduleProfileEntry.fromJson(item);
        return entry == null || !entry.isExpiredAt(at);
      }).toList(growable: false);
      if (kept.length == raw.length) return person;
      changed = true;
      final fields = Map<String, Object?>.from(person.customFields);
      if (kept.isEmpty) {
        fields.remove(storageField);
      } else {
        fields[storageField] = kept;
      }
      return person.copyWith(customFields: fields);
    }).toList(growable: false);
    return changed ? model.copyWith(persons: persons) : model;
  }
}
