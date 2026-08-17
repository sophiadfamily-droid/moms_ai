import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/event_model.dart';
import '../models/human/human_model.dart';
import '../models/structured_schedule_import.dart';
import '../models/user_profile.dart';
import 'event_service.dart';
import 'human/human_model_edit_service.dart';
import 'school_schedule_metadata_service.dart';
import 'storage_service.dart';
import 'structured_schedule_import_application_service.dart';
import 'structured_schedule_profile_service.dart';

typedef StructuredScheduleProfileLoader = Future<UserProfile?> Function();
typedef StructuredScheduleProfileWriter = Future<UserProfile> Function(
  UserProfile profile,
);
typedef StructuredScheduleEventLoader = Future<List<EventModel>> Function();
typedef StructuredScheduleEventWriter = Future<void> Function(
  List<EventModel> events,
);
typedef StructuredScheduleHumanEditorFactory = Future<HumanModelEditService>
    Function();

/// Production adapter for one fully reviewed document.
///
/// The import marker and deterministic Event identifiers make a completed
/// import idempotent. Recurring schedule projections are also de-duplicated by
/// their canonical person, target, days and clock range.
final class ProductionStructuredScheduleApplicationGateway
    implements StructuredScheduleApplicationGateway {
  ProductionStructuredScheduleApplicationGateway({
    StructuredScheduleProfileLoader profileLoader =
        StorageService.getUserProfile,
    StructuredScheduleProfileWriter profileWriter =
        StorageService.saveUserProfile,
    StructuredScheduleEventLoader eventLoader = EventService.getEvents,
    StructuredScheduleEventWriter eventWriter = EventService.addEvents,
    StructuredScheduleHumanEditorFactory humanEditorFactory =
        HumanModelEditService.createProduction,
    Future<SharedPreferences> Function() preferences =
        SharedPreferences.getInstance,
  })  : _profileLoader = profileLoader,
        _profileWriter = profileWriter,
        _eventLoader = eventLoader,
        _eventWriter = eventWriter,
        _humanEditorFactory = humanEditorFactory,
        _preferences = preferences;

  static const _appliedPrefix = 'structured_schedule_import_applied_v1:';

  final StructuredScheduleProfileLoader _profileLoader;
  final StructuredScheduleProfileWriter _profileWriter;
  final StructuredScheduleEventLoader _eventLoader;
  final StructuredScheduleEventWriter _eventWriter;
  final StructuredScheduleHumanEditorFactory _humanEditorFactory;
  final Future<SharedPreferences> Function() _preferences;

  @override
  Future<StructuredScheduleApplicationResult> apply(
    StructuredScheduleApplicationBatch batch,
  ) async {
    final preferences = await _preferences();
    final marker = '$_appliedPrefix${batch.accountScopeId}:${batch.importId}';
    if (preferences.getBool(marker) == true) {
      return const StructuredScheduleApplicationResult(
        StructuredScheduleApplicationStatus.alreadyApplied,
      );
    }

    try {
      final profile = await _profileLoader();
      if (profile == null) {
        return const StructuredScheduleApplicationResult(
          StructuredScheduleApplicationStatus.unavailable,
        );
      }
      final editor = await _humanEditorFactory();
      final state = await editor.load(batch.accountScopeId);
      if (state == null) {
        return const StructuredScheduleApplicationResult(
          StructuredScheduleApplicationStatus.unavailable,
        );
      }
      final personIds = state.model.persons.map((person) => person.id).toSet();
      if (batch.proposals.any(
        (proposal) => !personIds.contains(proposal.subjectEntityId),
      )) {
        return const StructuredScheduleApplicationResult(
          StructuredScheduleApplicationStatus.invalidReview,
        );
      }

      final cleanedHuman = StructuredScheduleProfileService.pruneExpired(
        state.model,
        at: DateTime.now(),
      );
      final updatedHuman = _withHumanSchedules(cleanedHuman, batch);
      if (!identical(updatedHuman, state.model)) {
        final humanResult = await editor.commit(
          accountScopeId: batch.accountScopeId,
          transform: (latest) => _withHumanSchedules(
            StructuredScheduleProfileService.pruneExpired(
              latest,
              at: DateTime.now(),
            ),
            batch,
          ),
        );
        if (humanResult.status != HumanModelEditStatus.success) {
          return const StructuredScheduleApplicationResult(
            StructuredScheduleApplicationStatus.unavailable,
          );
        }
      }

      final updatedProfile = _withCompatibilitySchedules(profile, batch);
      await _profileWriter(updatedProfile);

      final datedEvents = _events(batch, profile.humanPersonId);
      if (datedEvents.isNotEmpty) {
        final existingIds = (await _eventLoader())
            .map((event) => event.id)
            .whereType<String>()
            .toSet();
        final missing = datedEvents
            .where((event) => !existingIds.contains(event.id))
            .toList(growable: false);
        if (missing.isNotEmpty) await _eventWriter(missing);
      }
      await preferences.setBool(marker, true);
      return const StructuredScheduleApplicationResult(
        StructuredScheduleApplicationStatus.applied,
      );
    } on Object {
      return const StructuredScheduleApplicationResult(
        StructuredScheduleApplicationStatus.unavailable,
      );
    }
  }

  HumanModel _withHumanSchedules(
    HumanModel current,
    StructuredScheduleApplicationBatch batch,
  ) {
    var changed = false;
    final persons = current.persons.map((person) {
      final additions = batch.proposals
          .where((proposal) => proposal.subjectEntityId == person.id)
          .map((proposal) => _humanRecord(batch.importId, proposal))
          .toList(growable: false);
      if (additions.isEmpty) return person;
      final existingRaw =
          person.customFields[StructuredScheduleProfileService.storageField];
      final existing = existingRaw is List
          ? existingRaw
              .whereType<Map>()
              .map((value) => Map<String, Object?>.from(value))
              .toList()
          : <Map<String, Object?>>[];
      final keys = existing.map((item) => item['sourceKey']).toSet();
      final fresh = additions
          .where((item) => !keys.contains(item['sourceKey']))
          .toList(growable: false);
      if (fresh.isEmpty) return person;
      changed = true;
      return person.copyWith(
        customFields: {
          ...person.customFields,
          StructuredScheduleProfileService.storageField: [
            ...existing,
            ...fresh
          ],
        },
      );
    }).toList(growable: false);
    return changed ? current.copyWith(persons: persons) : current;
  }

  Map<String, Object?> _humanRecord(
    String importId,
    StructuredScheduleProposal proposal,
  ) =>
      {
        'schemaVersion': 1,
        'sourceKey': '$importId:${proposal.proposalId}',
        'target': proposal.target.name,
        'temporalKind': proposal.temporalKind.name,
        'title': proposal.title.trim(),
        if (proposal.dateIso != null) 'dateIso': proposal.dateIso,
        if (proposal.weekdays.isNotEmpty) 'weekdays': proposal.weekdays,
        'startTime': proposal.startTime,
        'endTime': proposal.endTime,
        if (proposal.place != null) 'place': proposal.place!.trim(),
        if (proposal.spansMidnight) 'endsNextDay': true,
      };

  UserProfile _withCompatibilitySchedules(
    UserProfile current,
    StructuredScheduleApplicationBatch batch,
  ) {
    var work = List<TimeRangeModel>.of(current.workTimeRanges);
    var activities = List<ActivityModel>.of(current.personalActivities);
    var children = List<ChildProfile>.of(current.children);

    for (final proposal in batch.proposals) {
      if (proposal.temporalKind !=
          StructuredScheduleTemporalKind.recurringWeekly) {
        continue;
      }
      final range = _range(proposal);
      if (proposal.subjectEntityId == current.humanPersonId) {
        if (proposal.target == StructuredScheduleTarget.workSchedule) {
          work = _addRange(work, range);
        } else if (proposal.target ==
            StructuredScheduleTarget.activitySchedule) {
          activities = _addActivity(activities, proposal, range);
        }
        continue;
      }
      final childIndex = children.indexWhere(
        (child) => child.humanPersonId == proposal.subjectEntityId,
      );
      if (childIndex < 0) continue;
      final child = children[childIndex];
      if (proposal.target == StructuredScheduleTarget.schoolSchedule) {
        children[childIndex] = child.copyWith(
          schoolTimeRanges: _addRange(child.schoolTimeRanges, range),
        );
      } else if (proposal.target == StructuredScheduleTarget.activitySchedule) {
        children[childIndex] = child.copyWith(
          activities: _addActivity(child.activities, proposal, range),
        );
      }
    }
    return current.copyWith(
      workTimeRanges: work,
      personalActivities: activities,
      children: children,
    );
  }

  TimeRangeModel _range(StructuredScheduleProposal proposal) => TimeRangeModel(
        label: proposal.title.trim(),
        startTime: proposal.startTime!,
        endTime: proposal.endTime!,
        notes: SchoolScheduleMetadataService.encodeNotes(
          days: proposal.weekdays.map(_weekdayName).toList(),
          notes: '',
        ),
      );

  List<TimeRangeModel> _addRange(
    List<TimeRangeModel> source,
    TimeRangeModel addition,
  ) {
    final encoded = jsonEncode(addition.toJson());
    if (source.any((item) => jsonEncode(item.toJson()) == encoded)) {
      return List.of(source);
    }
    return [...source, addition];
  }

  List<ActivityModel> _addActivity(
    List<ActivityModel> source,
    StructuredScheduleProposal proposal,
    TimeRangeModel range,
  ) {
    final index = source.indexWhere(
      (activity) =>
          activity.title.trim().toLowerCase() ==
              proposal.title.trim().toLowerCase() &&
          activity.location.trim().toLowerCase() ==
              (proposal.place ?? '').trim().toLowerCase(),
    );
    if (index < 0) {
      return [
        ...source,
        ActivityModel(
          title: proposal.title.trim(),
          location: proposal.place?.trim() ?? '',
          days: proposal.weekdays.map(_weekdayName).toList(),
          timeRanges: [range],
        ),
      ];
    }
    final updated = List<ActivityModel>.of(source);
    final current = updated[index];
    updated[index] = current.copyWith(
      days: {...current.days, ...proposal.weekdays.map(_weekdayName)}.toList(),
      timeRanges: _addRange(current.timeRanges, range),
    );
    return updated;
  }

  List<EventModel> _events(
    StructuredScheduleApplicationBatch batch,
    String primaryPersonId,
  ) =>
      batch.proposals
          .where(
        (proposal) =>
            proposal.target == StructuredScheduleTarget.event &&
            proposal.subjectEntityId == primaryPersonId,
      )
          .map((proposal) {
        final date = DateTime.parse(proposal.dateIso!);
        final start = _localDateTime(date, proposal.startTime!);
        var end = _localDateTime(date, proposal.endTime!);
        if (proposal.spansMidnight) {
          end = end.add(const Duration(days: 1));
        }
        return EventModel(
          id: _deterministicUuid('${batch.importId}:${proposal.proposalId}'),
          title: proposal.title.trim(),
          date:
              '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}',
          time: proposal.startTime!,
          notes: '',
          category: 'Personnel',
          location: proposal.place?.trim() ?? '',
          createdAt: DateTime.now(),
          startDateTimeIso: start.toIso8601String(),
          endTime: proposal.endTime!,
          endDateTimeIso: end.toIso8601String(),
          durationMinutes: end.difference(start).inMinutes,
        );
      }).toList(growable: false);

  DateTime _localDateTime(DateTime date, String clock) {
    final parts = clock.split(':');
    return DateTime(
      date.year,
      date.month,
      date.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
  }

  String _weekdayName(int weekday) => const {
        DateTime.monday: 'Lundi',
        DateTime.tuesday: 'Mardi',
        DateTime.wednesday: 'Mercredi',
        DateTime.thursday: 'Jeudi',
        DateTime.friday: 'Vendredi',
        DateTime.saturday: 'Samedi',
        DateTime.sunday: 'Dimanche',
      }[weekday]!;

  String _deterministicUuid(String value) {
    int hash(int seed) {
      var result = seed;
      for (final unit in value.codeUnits) {
        result = ((result ^ unit) * 16777619) & 0xffffffff;
      }
      return result;
    }

    final hex = [
      hash(0x811c9dc5),
      hash(0x9e3779b9),
      hash(0x85ebca6b),
      hash(0xc2b2ae35),
    ].map((part) => part.toRadixString(16).padLeft(8, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-7${hex.substring(13, 16)}-a${hex.substring(17, 20)}-${hex.substring(20, 32)}';
  }
}
