import '../models/user_profile.dart';
import 'travel_context_service.dart';

class ProfileReasoningService {
  static List<Map<String, dynamic>> buildReasoning(UserProfile profile) {
    final reasoning = <Map<String, dynamic>>[];

    reasoning.addAll(_buildWorkReasoning(profile));
    reasoning.addAll(_buildChildrenSchoolReasoning(profile));
    reasoning.addAll(_buildChildrenActivitiesReasoning(profile));
    reasoning.addAll(_buildPersonalActivitiesReasoning(profile));
    reasoning.addAll(_buildPreferenceReasoning(profile));

    return reasoning;
  }

  static List<Map<String, dynamic>> _buildWorkReasoning(UserProfile profile) {
    final reasoning = <Map<String, dynamic>>[];

    for (final range in profile.workTimeRanges) {
      if (!_hasValidTimeRange(range)) continue;

      reasoning.add(_blockedPeriod(
        sourceType: "work",
        label: range.label.isNotEmpty ? range.label : "Travail",
        days: profile.workDays,
        startTime: range.startTime,
        endTime: range.endTime,
        travelMinutes: range.travelMinutes,
        notes: range.notes,
      ));
    }

    if (profile.morningStart.isNotEmpty && profile.morningEnd.isNotEmpty) {
      reasoning.add(_blockedPeriod(
        sourceType: "work",
        label: "Travail matin",
        days: profile.workDays,
        startTime: profile.morningStart,
        endTime: profile.morningEnd,
        travelMinutes: profile.transportInfo,
      ));
    }

    if (profile.afternoonStart.isNotEmpty && profile.afternoonEnd.isNotEmpty) {
      reasoning.add(_blockedPeriod(
        sourceType: "work",
        label: "Travail après-midi",
        days: profile.workDays,
        startTime: profile.afternoonStart,
        endTime: profile.afternoonEnd,
        travelMinutes: profile.transportInfo,
      ));
    }

    if (_containsAny(profile.workHours, [
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
        "source": profile.workHours,
      });
    } else if (_containsAny(profile.workHours, [
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
        "source": profile.workHours,
      });
    }

    return reasoning;
  }

  static List<Map<String, dynamic>> _buildChildrenSchoolReasoning(
    UserProfile profile,
  ) {
    final reasoning = <Map<String, dynamic>>[];

    for (final child in profile.children) {
      for (final range in child.schoolTimeRanges) {
        if (!_hasValidTimeRange(range)) continue;

        reasoning.add(_blockedPeriod(
          sourceType: "child_school",
          label: child.school.isNotEmpty
              ? "École ${child.firstName} - ${child.school}"
              : "École ${child.firstName}",
          startTime: range.startTime,
          endTime: range.endTime,
          travelMinutes: range.travelMinutes,
          notes: range.notes,
        ));
      }
    }

    return reasoning;
  }

  static List<Map<String, dynamic>> _buildChildrenActivitiesReasoning(
    UserProfile profile,
  ) {
    final reasoning = <Map<String, dynamic>>[];

    for (final child in profile.children) {
      for (final activity in child.activities) {
        for (final range in activity.timeRanges) {
          if (!_hasValidTimeRange(range)) continue;

          final travelMinutes = activity.travelMinutes.isNotEmpty
              ? activity.travelMinutes
              : range.travelMinutes;

          reasoning.add(_blockedPeriod(
            sourceType: "child_activity",
            label: "${activity.title} - ${child.firstName}",
            days: activity.days,
            startTime: range.startTime,
            endTime: range.endTime,
            travelMinutes: travelMinutes,
            location: activity.location,
            notes: activity.notes,
          ));
        }
      }
    }

    return reasoning;
  }

  static List<Map<String, dynamic>> _buildPersonalActivitiesReasoning(
    UserProfile profile,
  ) {
    final reasoning = <Map<String, dynamic>>[];

    for (final activity in profile.personalActivities) {
      for (final range in activity.timeRanges) {
        if (!_hasValidTimeRange(range)) continue;

        final travelMinutes = activity.travelMinutes.isNotEmpty
            ? activity.travelMinutes
            : range.travelMinutes;

        reasoning.add(_blockedPeriod(
          sourceType: "personal_activity",
          label: activity.title,
          days: activity.days,
          startTime: range.startTime,
          endTime: range.endTime,
          travelMinutes: travelMinutes,
          location: activity.location,
          notes: activity.notes,
        ));
      }
    }

    return reasoning;
  }

  static List<Map<String, dynamic>> _buildPreferenceReasoning(
    UserProfile profile,
  ) {
    final reasoning = <Map<String, dynamic>>[];

    final text = [
      profile.preferences,
      profile.habits,
      profile.planningStyle,
      profile.childcareInfo,
      profile.transportInfo,
      profile.personalNotes,
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

  static bool _hasValidTimeRange(TimeRangeModel range) {
    return range.startTime.trim().isNotEmpty && range.endTime.trim().isNotEmpty;
  }

  static bool _containsAny(String text, List<String> values) {
    final lower = text.trim().toLowerCase();
    return values.any(lower.contains);
  }
}
