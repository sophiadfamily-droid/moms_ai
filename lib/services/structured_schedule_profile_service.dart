import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/human/human_model.dart';
import '../models/user_profile.dart';
import 'school_schedule_metadata_service.dart';

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

  Map<String, Object?> toJson() => {
        'schemaVersion': 1,
        'sourceKey': sourceKey,
        'target': target,
        'temporalKind': temporalKind,
        'title': title,
        if (dateIso != null) 'dateIso': dateIso,
        if (weekdays.isNotEmpty) 'weekdays': weekdays,
        'startTime': startTime,
        'endTime': endTime,
        if (place?.trim().isNotEmpty == true) 'place': place!.trim(),
        if (endsNextDay) 'endsNextDay': true,
      };

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
  static const _compatibilitySourcePrefix = 'compatibility-profile-v1:';

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

  /// Moves every structured schedule still edited through [UserProfile] into
  /// the person-owned schedule extension.
  ///
  /// Records created by document imports are retained. Records derived from
  /// the compatibility profile are replaced as one closed set, so deleting a
  /// range in the profile also deletes its canonical counterpart. Stable
  /// content-derived keys make repeated migrations idempotent.
  static HumanModel reconcileCompatibilitySchedules({
    required HumanModel model,
    required UserProfile profile,
  }) {
    final linkedProfile = profile.humanPersonId.trim().isEmpty
        ? profile.copyWith(humanPersonId: model.primaryPersonId)
        : profile;
    final additions = _compatibilityEntries(linkedProfile);
    var changed = false;
    final persons = model.persons.map((person) {
      final raw = person.customFields[storageField];
      final existing = raw is List
          ? raw
              .map(StructuredScheduleProfileEntry.fromJson)
              .whereType<StructuredScheduleProfileEntry>()
              .toList(growable: false)
          : const <StructuredScheduleProfileEntry>[];
      final retained = existing
          .where((entry) =>
              !entry.sourceKey.startsWith(_compatibilitySourcePrefix))
          .toList(growable: true);
      retained.addAll(additions[person.id] ?? const []);
      final before = existing.map((entry) => entry.toJson()).toList();
      final after = retained.map((entry) => entry.toJson()).toList();
      if (jsonEncode(before) == jsonEncode(after)) return person;
      changed = true;
      final fields = Map<String, Object?>.from(person.customFields);
      if (after.isEmpty) {
        fields.remove(storageField);
      } else {
        fields[storageField] = after;
      }
      return person.copyWith(customFields: fields);
    }).toList(growable: false);
    return changed ? model.copyWith(persons: persons) : model;
  }

  /// Rebuilds the historical profile fields from the canonical person-owned
  /// schedules. This is a temporary presentation adapter for screens that
  /// still edit [UserProfile]. It never becomes a second source of truth.
  static UserProfile projectOntoCompatibilityProfile({
    required HumanModel model,
    required UserProfile profile,
    DateTime? at,
  }) {
    final readAt = at ?? DateTime.now();
    final primary = model.personById(model.primaryPersonId);
    final primaryEntries = primary == null
        ? const <StructuredScheduleProfileEntry>[]
        : entriesForPerson(primary, at: readAt)
            .where((entry) => !entry.isDated)
            .toList(growable: false);
    final workEntries = primaryEntries
        .where((entry) => entry.target == 'workSchedule')
        .toList(growable: false);
    final activityEntries = primaryEntries
        .where((entry) => entry.target == 'activitySchedule')
        .toList(growable: false);

    final projectedChildren = profile.children.map((child) {
      final person = model.personById(child.humanPersonId);
      if (person == null) return child;
      final entries = entriesForPerson(person, at: readAt)
          .where((entry) => !entry.isDated)
          .toList(growable: false);
      final school = entries
          .where((entry) => entry.target == 'schoolSchedule')
          .map(_rangeFromEntry)
          .toList(growable: false);
      final activities = _activitiesFromEntries(
        entries.where((entry) => entry.target == 'activitySchedule'),
        unscheduled: child.activities
            .where((activity) => activity.timeRanges.isEmpty)
            .toList(growable: false),
      );
      return child.copyWith(
        schoolTimeRanges: school,
        activities: activities,
      );
    }).toList(growable: false);

    return profile.copyWith(
      workDays: _dayNames(
        workEntries.expand((entry) => entry.weekdays),
      ),
      workTimeRanges: workEntries.map(_rangeFromEntry).toList(growable: false),
      personalActivities: _activitiesFromEntries(
        activityEntries,
        unscheduled: profile.personalActivities
            .where((activity) => activity.timeRanges.isEmpty)
            .toList(growable: false),
      ),
      children: projectedChildren,
    );
  }

  static Map<String, List<StructuredScheduleProfileEntry>>
      _compatibilityEntries(UserProfile profile) {
    final result = <String, List<StructuredScheduleProfileEntry>>{};

    void add({
      required String personId,
      required String target,
      required String title,
      required Iterable<String> days,
      required TimeRangeModel range,
      String? place,
    }) {
      final normalizedPerson = personId.trim();
      final start = range.startTime.trim();
      final end = range.endTime.trim();
      if (normalizedPerson.isEmpty || start.isEmpty || end.isEmpty) return;
      final rangeDays = SchoolScheduleMetadataService.daysFromRange(range);
      final weekdays = _weekdayNumbers(
        rangeDays.isEmpty ? days : rangeDays,
      );
      if (weekdays.isEmpty) return;
      final normalizedTitle =
          title.trim().isEmpty ? _fallback(target) : title.trim();
      final normalizedPlace = place?.trim();
      final signature = jsonEncode({
        'person': normalizedPerson,
        'target': target,
        'title': normalizedTitle.toLowerCase(),
        'weekdays': weekdays,
        'start': start,
        'end': end,
        'place': normalizedPlace?.toLowerCase() ?? '',
      });
      final digest = sha256.convert(utf8.encode(signature)).toString();
      result.putIfAbsent(normalizedPerson, () => []).add(
            StructuredScheduleProfileEntry(
              sourceKey: '$_compatibilitySourcePrefix$digest',
              target: target,
              temporalKind: 'recurringWeekly',
              title: normalizedTitle,
              weekdays: weekdays,
              startTime: start,
              endTime: end,
              place: normalizedPlace,
              endsNextDay: _minutes(end) <= _minutes(start),
            ),
          );
    }

    for (final range in profile.workTimeRanges) {
      add(
        personId: profile.humanPersonId,
        target: 'workSchedule',
        title: range.label,
        days: profile.workDays,
        range: range,
        place: profile.workAddress,
      );
    }
    for (final legacy in [
      (
        title: 'Travail matin',
        start: profile.morningStart,
        end: profile.morningEnd
      ),
      (
        title: 'Travail après-midi',
        start: profile.afternoonStart,
        end: profile.afternoonEnd
      ),
    ]) {
      add(
        personId: profile.humanPersonId,
        target: 'workSchedule',
        title: legacy.title,
        days: profile.workDays,
        range: TimeRangeModel(startTime: legacy.start, endTime: legacy.end),
        place: profile.workAddress,
      );
    }
    for (final activity in profile.personalActivities) {
      for (final range in activity.timeRanges) {
        add(
          personId: profile.humanPersonId,
          target: 'activitySchedule',
          title: activity.title,
          days: activity.days,
          range: range,
          place: activity.location,
        );
      }
    }
    for (final child in profile.children) {
      for (final range in child.schoolTimeRanges) {
        add(
          personId: child.humanPersonId,
          target: 'schoolSchedule',
          title: range.label.trim().isEmpty
              ? 'École ${child.firstName}'.trim()
              : range.label,
          days: const [],
          range: range,
        );
      }
      for (final activity in child.activities) {
        for (final range in activity.timeRanges) {
          add(
            personId: child.humanPersonId,
            target: 'activitySchedule',
            title: activity.title,
            days: activity.days,
            range: range,
            place: activity.location,
          );
        }
      }
    }
    for (final entries in result.values) {
      entries.sort((left, right) => left.sourceKey.compareTo(right.sourceKey));
    }
    return result;
  }

  static TimeRangeModel _rangeFromEntry(StructuredScheduleProfileEntry entry) =>
      TimeRangeModel(
        label: entry.title,
        startTime: entry.startTime,
        endTime: entry.endTime,
        notes: SchoolScheduleMetadataService.encodeNotes(
          days: _dayNames(entry.weekdays),
          notes: '',
        ),
      );

  static List<ActivityModel> _activitiesFromEntries(
    Iterable<StructuredScheduleProfileEntry> entries, {
    List<ActivityModel> unscheduled = const [],
  }) {
    final activities = List<ActivityModel>.of(unscheduled);
    for (final entry in entries) {
      final index = activities.indexWhere((activity) =>
          activity.title.trim().toLowerCase() == entry.title.toLowerCase() &&
          activity.location.trim().toLowerCase() ==
              (entry.place ?? '').trim().toLowerCase());
      final range = _rangeFromEntry(entry);
      if (index < 0) {
        activities.add(ActivityModel(
          title: entry.title,
          location: entry.place ?? '',
          days: _dayNames(entry.weekdays),
          timeRanges: [range],
        ));
      } else {
        final current = activities[index];
        activities[index] = current.copyWith(
          days: {...current.days, ..._dayNames(entry.weekdays)}.toList(),
          timeRanges: [...current.timeRanges, range],
        );
      }
    }
    return activities;
  }

  static List<int> _weekdayNumbers(Iterable<String> values) {
    final result = values
        .map((value) => switch (_normalize(value)) {
              'lundi' => DateTime.monday,
              'mardi' => DateTime.tuesday,
              'mercredi' => DateTime.wednesday,
              'jeudi' => DateTime.thursday,
              'vendredi' => DateTime.friday,
              'samedi' => DateTime.saturday,
              'dimanche' => DateTime.sunday,
              _ => null,
            })
        .whereType<int>()
        .toSet()
        .toList()
      ..sort();
    return result;
  }

  static List<String> _dayNames(Iterable<int> values) {
    final unique = values.toSet().toList()..sort();
    return unique
        .map((day) => switch (day) {
              DateTime.monday => 'Lundi',
              DateTime.tuesday => 'Mardi',
              DateTime.wednesday => 'Mercredi',
              DateTime.thursday => 'Jeudi',
              DateTime.friday => 'Vendredi',
              DateTime.saturday => 'Samedi',
              DateTime.sunday => 'Dimanche',
              _ => '',
            })
        .where((day) => day.isNotEmpty)
        .toList(growable: false);
  }

  static String _normalize(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('ê', 'e');

  static int _minutes(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  static String _fallback(String target) => switch (target) {
        'workSchedule' => 'Travail',
        'schoolSchedule' => 'École',
        'activitySchedule' => 'Activité',
        _ => 'Horaire',
      };
}
