import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../models/routine/routine_schedule_definition.dart';
import '../../models/routine_model.dart';
import '../../models/user_profile.dart';
import '../school_schedule_metadata_service.dart';
import '../travel_context_service.dart';

typedef RoutineScheduleRoutineLoader = Future<List<RoutineModel>> Function(
  String accountScopeId,
);
typedef RoutineScheduleProfileLoader = Future<UserProfile?> Function();

/// Unifies canonical routines and the structured schedules stored in Profile.
///
/// Profile schedules are projected as deterministic, non-persisted
/// [RoutineModel] instances. This lets occurrence overrides use the exact same
/// engine for a routine, an activity, work hours, or another person's schedule
/// without turning any of them into an Event.
final class RoutineScheduleCatalogService {
  const RoutineScheduleCatalogService({
    required RoutineScheduleRoutineLoader loadRoutines,
    RoutineScheduleProfileLoader? loadProfile,
  })  : _loadRoutines = loadRoutines,
        _loadProfile = loadProfile;

  final RoutineScheduleRoutineLoader _loadRoutines;
  final RoutineScheduleProfileLoader? _loadProfile;

  Future<List<RoutineScheduleDefinition>> forAccount(
    String accountScopeId,
  ) async {
    final canonical = await _loadRoutines(accountScopeId);
    final profile = await _loadProfile?.call();
    final entries = canonical
        .map(
          (routine) => RoutineScheduleDefinition(
            routine: routine,
            kind: _canonicalKind(routine, profile),
            blocksPrimaryUser: _canonicalBlocksPrimaryUser(routine, profile),
            subjectLabel: _canonicalSubjectLabel(routine, profile),
          ),
        )
        .toList(growable: true);

    if (profile != null) {
      for (final profileEntry in fromProfile(
        profile: profile,
        accountScopeId: accountScopeId,
      )) {
        final duplicateIndex = entries.indexWhere(
          (entry) => _sameSchedule(entry.routine, profileEntry.routine),
        );
        if (duplicateIndex < 0) {
          entries.add(profileEntry);
        } else {
          // Keep the persisted canonical identity while retaining the richer
          // human meaning supplied by Profile.
          entries[duplicateIndex] = profileEntry.copyWith(
            routine: entries[duplicateIndex].routine,
          );
        }
      }
    }

    entries.sort((left, right) {
      final time = left.routine.startTime.compareTo(right.routine.startTime);
      return time != 0 ? time : left.routine.id.compareTo(right.routine.id);
    });
    return List.unmodifiable(entries);
  }

  static List<RoutineScheduleDefinition> fromProfile({
    required UserProfile profile,
    required String accountScopeId,
  }) {
    final entries = <RoutineScheduleDefinition>[];

    void addRange({
      required RoutineScheduleKind kind,
      required String title,
      required List<String> days,
      required TimeRangeModel range,
      required bool blocksPrimaryUser,
      String? subjectLabel,
      String? humanPersonId,
      String fallbackTravel = '',
    }) {
      final start = _time(range.startTime);
      final end = _time(range.endTime);
      final weekdays = _weekdays(days);
      if (start == null || end == null || weekdays.isEmpty) return;
      final duration = _duration(start, end);
      if (duration < 1) return;
      final informativeTitle = title.trim().isEmpty
          ? _fallbackTitle(kind, subjectLabel)
          : title.trim();
      final travel = TravelContextService.parseTravelMinutes(
        range.travelMinutes.trim().isNotEmpty
            ? range.travelMinutes
            : fallbackTravel,
      );
      final id = _profileScheduleId(
        accountScopeId: accountScopeId,
        kind: kind,
        title: informativeTitle,
        subjectLabel: subjectLabel,
        humanPersonId: humanPersonId,
        weekdays: weekdays,
        start: start,
        end: end,
      );
      final reference = DateTime.utc(2000);
      entries.add(
        RoutineScheduleDefinition(
          routine: RoutineModel(
            id: id,
            accountScopeId: accountScopeId,
            logicalRequestId: id,
            title: informativeTitle,
            humanPersonId:
                humanPersonId?.trim().isEmpty == false ? humanPersonId : null,
            recurrenceType: RoutineRecurrenceType.weekly,
            days: weekdays,
            startTime: start,
            durationMinutes: duration,
            travelGoMinutes: blocksPrimaryUser ? travel : 0,
            travelBackMinutes: blocksPrimaryUser ? travel : 0,
            marginMinutes: 0,
            createdAt: reference,
            updatedAt: reference,
          ),
          kind: kind,
          blocksPrimaryUser: blocksPrimaryUser,
          subjectLabel: subjectLabel?.trim().isEmpty == false
              ? subjectLabel!.trim()
              : null,
        ),
      );
    }

    for (final activity in profile.personalActivities) {
      for (final range in activity.timeRanges) {
        final rangeDays = SchoolScheduleMetadataService.daysFromRange(range);
        addRange(
          kind: RoutineScheduleKind.personalActivity,
          title: activity.title,
          days: rangeDays.isEmpty ? activity.days : rangeDays,
          range: range,
          blocksPrimaryUser: true,
          humanPersonId: profile.humanPersonId,
          fallbackTravel: activity.travelMinutes,
        );
      }
    }

    for (final range in profile.workTimeRanges) {
      final rangeDays = SchoolScheduleMetadataService.daysFromRange(range);
      addRange(
        kind: RoutineScheduleKind.work,
        title: range.label,
        days: rangeDays.isEmpty ? profile.workDays : rangeDays,
        range: range,
        blocksPrimaryUser: true,
        humanPersonId: profile.humanPersonId,
        fallbackTravel: profile.workTravelMinutes,
      );
    }
    for (final legacy in [
      (
        title: 'Travail matin',
        start: profile.morningStart,
        end: profile.morningEnd,
      ),
      (
        title: 'Travail après-midi',
        start: profile.afternoonStart,
        end: profile.afternoonEnd,
      ),
    ]) {
      addRange(
        kind: RoutineScheduleKind.work,
        title: legacy.title,
        days: profile.workDays,
        range: TimeRangeModel(
          startTime: legacy.start,
          endTime: legacy.end,
        ),
        blocksPrimaryUser: true,
        humanPersonId: profile.humanPersonId,
        fallbackTravel: profile.workTravelMinutes,
      );
    }

    for (final child in profile.children) {
      for (final range in child.schoolTimeRanges) {
        addRange(
          kind: RoutineScheduleKind.school,
          title: range.label.trim().isEmpty
              ? 'École ${child.firstName}'.trim()
              : range.label,
          days: SchoolScheduleMetadataService.daysFromRange(range),
          range: range,
          blocksPrimaryUser: false,
          subjectLabel: child.firstName,
          humanPersonId: child.humanPersonId,
        );
      }
      for (final activity in child.activities) {
        for (final range in activity.timeRanges) {
          final rangeDays = SchoolScheduleMetadataService.daysFromRange(range);
          addRange(
            kind: RoutineScheduleKind.householdActivity,
            title: activity.title,
            days: rangeDays.isEmpty ? activity.days : rangeDays,
            range: range,
            blocksPrimaryUser: false,
            subjectLabel: child.firstName,
            humanPersonId: child.humanPersonId,
            fallbackTravel: activity.travelMinutes,
          );
        }
      }
    }

    return List.unmodifiable(entries);
  }

  static RoutineScheduleKind _canonicalKind(
    RoutineModel routine,
    UserProfile? profile,
  ) {
    if (_canonicalBlocksPrimaryUser(routine, profile)) {
      return RoutineScheduleKind.routine;
    }
    return RoutineScheduleKind.householdActivity;
  }

  static bool _canonicalBlocksPrimaryUser(
    RoutineModel routine,
    UserProfile? profile,
  ) {
    final subject = routine.humanPersonId?.trim();
    final primary = profile?.humanPersonId.trim();
    if (subject == null || subject.isEmpty) return true;
    if (primary == null || primary.isEmpty) return false;
    return subject == primary;
  }

  static String? _canonicalSubjectLabel(
    RoutineModel routine,
    UserProfile? profile,
  ) {
    final subject = routine.humanPersonId?.trim();
    if (subject == null || subject.isEmpty || profile == null) return null;
    for (final child in profile.children) {
      if (child.humanPersonId.trim() == subject) return child.firstName.trim();
    }
    return null;
  }

  static bool _sameSchedule(RoutineModel left, RoutineModel right) =>
      _normalizedTitle(left.title) == _normalizedTitle(right.title) &&
      left.startTime == right.startTime &&
      left.durationMinutes == right.durationMinutes &&
      left.recurrenceType == right.recurrenceType &&
      left.days.length == right.days.length &&
      left.days.every(right.days.contains);

  static String _normalizedTitle(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[àâ]'), 'a')
      .replaceAll(RegExp('[îï]'), 'i')
      .replaceAll(RegExp('[ôö]'), 'o')
      .replaceAll(RegExp('[ùûü]'), 'u')
      .replaceAll('ç', 'c');

  static String _profileScheduleId({
    required String accountScopeId,
    required RoutineScheduleKind kind,
    required String title,
    required List<int> weekdays,
    required String start,
    required String end,
    String? subjectLabel,
    String? humanPersonId,
  }) {
    final digest = sha256
        .convert(
          utf8.encode(
            'profile-schedule-v1|$accountScopeId|${kind.name}|$title|'
            '${subjectLabel ?? ''}|${humanPersonId ?? ''}|'
            '${weekdays.join(',')}|$start|$end',
          ),
        )
        .toString();
    return 'profile-schedule-${digest.substring(0, 40)}';
  }

  static List<int> _weekdays(List<String> days) {
    final result = <int>{};
    for (final raw in days) {
      final day = _normalizeDay(raw);
      final weekday = switch (day) {
        'lundi' || 'monday' || 'mon' || '1' => DateTime.monday,
        'mardi' || 'tuesday' || 'tue' || '2' => DateTime.tuesday,
        'mercredi' || 'wednesday' || 'wed' || '3' => DateTime.wednesday,
        'jeudi' || 'thursday' || 'thu' || '4' => DateTime.thursday,
        'vendredi' || 'friday' || 'fri' || '5' => DateTime.friday,
        'samedi' || 'saturday' || 'sat' || '6' => DateTime.saturday,
        'dimanche' || 'sunday' || 'sun' || '7' => DateTime.sunday,
        _ => null,
      };
      if (weekday != null) result.add(weekday);
    }
    return result.toList()..sort();
  }

  static String _normalizeDay(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[àâ]'), 'a')
      .replaceAll(RegExp('[îï]'), 'i')
      .replaceAll(RegExp('[ôö]'), 'o')
      .replaceAll(RegExp('[ùûü]'), 'u')
      .replaceAll('ç', 'c');

  static String? _time(String value) {
    final match = RegExp(r'^(\d{1,2})(?:\s*[h:]\s*(\d{1,2}))?$')
        .firstMatch(value.trim().toLowerCase());
    if (match == null) return null;
    final hour = int.tryParse(match.group(1) ?? '');
    final minute = int.tryParse(match.group(2) ?? '0');
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return null;
    }
    return '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
  }

  static int _duration(String start, String end) {
    final startParts = start.split(':').map(int.parse).toList();
    final endParts = end.split(':').map(int.parse).toList();
    final startMinutes = startParts[0] * 60 + startParts[1];
    var endMinutes = endParts[0] * 60 + endParts[1];
    if (endMinutes <= startMinutes) endMinutes += 24 * 60;
    return endMinutes - startMinutes;
  }

  static String _fallbackTitle(
    RoutineScheduleKind kind,
    String? subjectLabel,
  ) =>
      switch (kind) {
        RoutineScheduleKind.routine => 'Routine',
        RoutineScheduleKind.personalActivity => 'Activité',
        RoutineScheduleKind.work => 'Travail',
        RoutineScheduleKind.school =>
          'École${subjectLabel?.trim().isNotEmpty == true ? ' ${subjectLabel!.trim()}' : ''}',
        RoutineScheduleKind.householdActivity =>
          'Activité${subjectLabel?.trim().isNotEmpty == true ? ' de ${subjectLabel!.trim()}' : ''}',
      };
}
