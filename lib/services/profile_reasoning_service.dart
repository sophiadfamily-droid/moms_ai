import '../models/life_context/life_context_provenance.dart';
import '../models/life_context/life_context_snapshot.dart';
import '../models/life_context/schedule_context.dart';
import '../models/user_profile.dart';
import 'life_context/life_context_engine.dart';
import 'travel_context_service.dart';
import 'school_schedule_metadata_service.dart';

class ProfileReasoningService {
  /// Transitional compatibility bridge for progressive migration only.
  ///
  /// New consumers must call [buildReasoningFromSnapshot] directly. This
  /// method will be removed once every consumer provides a LifeContextSnapshot.
  static List<Map<String, dynamic>> buildReasoning(
    UserProfile profile, {
    LifeContextEngine? lifeContextEngine,
    DateTime? generatedAt,
  }) {
    final snapshot = (lifeContextEngine ?? LifeContextEngine()).buildSnapshot(
      profile: profile,
      generatedAt: generatedAt ?? DateTime.now(),
    );

    return buildReasoningFromSnapshot(
      snapshot,
      legacyPersonalNotes: profile.personalNotes,
    );
  }

  static List<Map<String, dynamic>> buildReasoningFromSnapshot(
    LifeContextSnapshot snapshot, {
    String legacyPersonalNotes = '',
  }) {
    final reasoning = <Map<String, dynamic>>[];

    reasoning.addAll(_buildWorkReasoning(snapshot));
    reasoning.addAll(_buildChildrenSchoolReasoning(snapshot));
    reasoning.addAll(_buildChildrenActivitiesReasoning(snapshot));
    reasoning.addAll(_buildPersonalActivitiesReasoning(snapshot));
    reasoning.addAll(
      _buildPreferenceReasoning(
        snapshot,
        legacyPersonalNotes: legacyPersonalNotes,
      ),
    );

    return reasoning;
  }

  static List<Map<String, dynamic>> _buildWorkReasoning(
    LifeContextSnapshot snapshot,
  ) {
    final reasoning = <Map<String, dynamic>>[];
    final work = snapshot.work;
    final workDays = work.workDays?.value ?? const <String>[];
    final transportInfo = snapshot.mobility.transportInfo?.value ?? '';

    for (final range in work.timeRanges) {
      if (!_hasValidTimeRange(range)) continue;

      reasoning.add(_blockedPeriod(
        sourceType: "work",
        label: _value(range.label).isNotEmpty ? _value(range.label) : "Travail",
        days: workDays,
        startTime: _value(range.startTime),
        endTime: _value(range.endTime),
        travelMinutes: _value(range.travelMinutes),
        notes: _value(range.notes),
      ));
    }

    final morningStart = _value(work.legacyMorningStart);
    final morningEnd = _value(work.legacyMorningEnd);
    if (morningStart.isNotEmpty && morningEnd.isNotEmpty) {
      reasoning.add(_blockedPeriod(
        sourceType: "work",
        label: "Travail matin",
        days: workDays,
        startTime: morningStart,
        endTime: morningEnd,
        travelMinutes: transportInfo,
      ));
    }

    final afternoonStart = _value(work.legacyAfternoonStart);
    final afternoonEnd = _value(work.legacyAfternoonEnd);
    if (afternoonStart.isNotEmpty && afternoonEnd.isNotEmpty) {
      reasoning.add(_blockedPeriod(
        sourceType: "work",
        label: "Travail après-midi",
        days: workDays,
        startTime: afternoonStart,
        endTime: afternoonEnd,
        travelMinutes: transportInfo,
      ));
    }

    final workHours = _value(work.legacyWorkHours);
    if (_containsAny(workHours, [
      "travail de nuit",
      "horaires de nuit",
      "je travaille de nuit",
      "poste de nuit",
    ])) {
      reasoning.add({
        "type": "schedule_constraint",
        "sourceType": "work",
        "scheduleMode": "night",
        "avoidMorning": true,
        "source": workHours,
      });
    } else if (_containsAny(workHours, [
      "travail le soir",
      "je travaille le soir",
      "horaires du soir",
      "poste du soir",
      "je termine tard",
      "horaires tardifs",
    ])) {
      reasoning.add({
        "type": "schedule_constraint",
        "sourceType": "work",
        "scheduleMode": "late",
        "avoidMorning": false,
        "source": workHours,
      });
    }

    return reasoning;
  }

  static List<Map<String, dynamic>> _buildChildrenSchoolReasoning(
    LifeContextSnapshot snapshot,
  ) {
    final reasoning = <Map<String, dynamic>>[];

    for (var index = 0;
        index < snapshot.routines.childRoutines.length;
        index++) {
      final routine = snapshot.routines.childRoutines[index];
      final child = index < snapshot.household.children.length
          ? snapshot.household.children[index]
          : null;
      final childName = _value(routine.childName);
      final school = _value(child?.school);

      for (final range in routine.schoolTimeRanges) {
        if (!_hasValidTimeRange(range)) continue;
        final legacyRange = _legacyTimeRange(range);

        reasoning.add(_blockedPeriod(
          sourceType: "child_school",
          label: school.isNotEmpty
              ? "École $childName - $school"
              : "École $childName",
          days: SchoolScheduleMetadataService.daysFromRange(legacyRange),
          startTime: _value(range.startTime),
          endTime: _value(range.endTime),
          travelMinutes: _value(range.travelMinutes),
          notes: SchoolScheduleMetadataService.cleanNotes(legacyRange),
        ));
      }
    }

    return reasoning;
  }

  static List<Map<String, dynamic>> _buildChildrenActivitiesReasoning(
    LifeContextSnapshot snapshot,
  ) {
    final reasoning = <Map<String, dynamic>>[];

    for (final childRoutine in snapshot.routines.childRoutines) {
      final childName = _value(childRoutine.childName);
      for (final activity in childRoutine.activities) {
        for (final range in activity.timeRanges) {
          if (!_hasValidTimeRange(range)) continue;

          final activityTravel = _value(activity.travelMinutes);
          final travelMinutes = activityTravel.isNotEmpty
              ? activityTravel
              : _value(range.travelMinutes);

          reasoning.add(_blockedPeriod(
            sourceType: "child_activity",
            label: "${_value(activity.title)} - $childName",
            days: activity.days?.value ?? const <String>[],
            startTime: _value(range.startTime),
            endTime: _value(range.endTime),
            travelMinutes: travelMinutes,
            location: _value(activity.location),
            notes: _value(activity.notes),
          ));
        }
      }
    }

    return reasoning;
  }

  static List<Map<String, dynamic>> _buildPersonalActivitiesReasoning(
    LifeContextSnapshot snapshot,
  ) {
    final reasoning = <Map<String, dynamic>>[];

    for (final activity in snapshot.routines.personalActivities) {
      for (final range in activity.timeRanges) {
        if (!_hasValidTimeRange(range)) continue;

        final activityTravel = _value(activity.travelMinutes);
        final travelMinutes = activityTravel.isNotEmpty
            ? activityTravel
            : _value(range.travelMinutes);

        reasoning.add(_blockedPeriod(
          sourceType: "personal_activity",
          label: _value(activity.title),
          days: activity.days?.value ?? const <String>[],
          startTime: _value(range.startTime),
          endTime: _value(range.endTime),
          travelMinutes: travelMinutes,
          location: _value(activity.location),
          notes: _value(activity.notes),
        ));
      }
    }

    return reasoning;
  }

  static List<Map<String, dynamic>> _buildPreferenceReasoning(
    LifeContextSnapshot snapshot, {
    required String legacyPersonalNotes,
  }) {
    final reasoning = <Map<String, dynamic>>[];

    final text = [
      _value(snapshot.preferences.legacyPreferences),
      _value(snapshot.routines.legacyHabits),
      _value(snapshot.preferences.planningStyle),
      _value(snapshot.household.childcareInfo),
      _value(snapshot.mobility.transportInfo),
      legacyPersonalNotes,
    ].join(" ").toLowerCase();

    if (_containsAny(text, [
      "après-midi",
      "apres-midi",
      "l'après-midi",
      "lapres-midi",
    ])) {
      reasoning.add({
        "type": "schedule_preference",
        "sourceType": "profile",
        "preferredPeriod": "afternoon",
        "source": text,
      });
    }

    if (_containsAny(text, [
      "pas le matin",
      "éviter le matin",
      "eviter le matin",
      "je n'aime pas le matin",
      "je naime pas le matin",
    ])) {
      reasoning.add({
        "type": "schedule_constraint",
        "sourceType": "profile",
        "avoidMorning": true,
        "source": text,
      });
    }

    return reasoning;
  }

  static Map<String, dynamic> _blockedPeriod({
    required String sourceType,
    required String label,
    required String startTime,
    required String endTime,
    List<String> days = const [],
    dynamic travelMinutes,
    String location = "",
    String notes = "",
  }) {
    final travel = TravelContextService.buildTravelMetadata(
      travelMinutes: travelMinutes,
      origin: "",
      destination: location,
      mode: "unknown",
      provider: "manual_profile",
    );

    return {
      "type": "blocked_period",
      "sourceType": sourceType,
      "label": label,
      "days": days,
      "startTime": startTime,
      "endTime": endTime,
      "location": location,
      "notes": notes,
      ...travel,
    };
  }

  static TimeRangeModel _legacyTimeRange(LifeContextTimeRange range) {
    return TimeRangeModel(
      label: _value(range.label),
      startTime: _value(range.startTime),
      endTime: _value(range.endTime),
      travelMinutes: _value(range.travelMinutes),
      notes: _value(range.notes),
    );
  }

  static bool _hasValidTimeRange(LifeContextTimeRange range) {
    return _value(range.startTime).trim().isNotEmpty &&
        _value(range.endTime).trim().isNotEmpty;
  }

  static String _value(LifeContextFact<String>? fact) {
    return fact?.value ?? '';
  }

  static bool _containsAny(String text, List<String> values) {
    final lower = text.trim().toLowerCase();
    return values.any(lower.contains);
  }
}
