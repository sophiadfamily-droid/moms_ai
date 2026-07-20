import '../models/life_context/intent_context.dart';
import '../models/life_context/life_context_provenance.dart';
import '../models/life_context/life_context_snapshot.dart';
import '../models/life_context/schedule_context.dart';
import '../models/user_profile.dart';
import 'life_context/life_context_engine.dart';
import 'profile_reasoning_service.dart';

class ProfileContextBuilderService {
  /// Transitional compatibility bridge for callers that still own a profile.
  ///
  /// New consumers should call [buildStructuredContextFromSnapshot] directly.
  /// The legacy note parameters remain explicit until those fields are modeled
  /// by Life Context.
  static Map<String, dynamic> buildStructuredContext(
    UserProfile profile, {
    LifeContextEngine? lifeContextEngine,
    DateTime? generatedAt,
  }) {
    final snapshot = (lifeContextEngine ?? LifeContextEngine()).buildSnapshot(
      profile: profile,
      generatedAt: generatedAt ?? DateTime.now(),
    );

    return buildStructuredContextFromSnapshot(
      snapshot,
      legacyPersonalNotes: profile.personalNotes,
      legacyAdminNotes: profile.adminNotes,
      legacyBudgetNotes: profile.budgetNotes,
    );
  }

  static Map<String, dynamic> buildStructuredContextFromSnapshot(
    LifeContextSnapshot snapshot, {
    String legacyPersonalNotes = '',
    String legacyAdminNotes = '',
    String legacyBudgetNotes = '',
  }) {
    final profileReasoning = ProfileReasoningService.buildReasoningFromSnapshot(
      snapshot,
      legacyPersonalNotes: legacyPersonalNotes,
    );

    return {
      "identity": _identity(snapshot),
      "family": _family(snapshot),
      "work": _work(snapshot),
      "children": _children(snapshot),
      "preferences": _preferences(snapshot),
      "health": _health(snapshot),
      "lifeContext": _lifeContext(
        snapshot,
        legacyPersonalNotes: legacyPersonalNotes,
        legacyAdminNotes: legacyAdminNotes,
        legacyBudgetNotes: legacyBudgetNotes,
      ),
      "planningReasoning": profileReasoning,
    };
  }

  static Map<String, dynamic> _identity(LifeContextSnapshot snapshot) {
    return {
      "firstName": _value(snapshot.identity.firstName),
      "age": _value(snapshot.identity.age),
      "birthDate": _value(snapshot.identity.birthDate),
      "country": _value(snapshot.identity.country),
      "timeZone": _value(snapshot.identity.timeZone),
      "spokenLanguage": _value(snapshot.identity.spokenLanguage),
    };
  }

  static Map<String, dynamic> _family(LifeContextSnapshot snapshot) {
    return {
      "familyStatus": _value(snapshot.household.familyStatus),
      "relationshipStatus": _value(snapshot.household.relationshipStatus),
      "partnerName": _value(snapshot.household.partnerName),
      "childrenCount": snapshot.household.children.length,
      "childcareInfo": _value(snapshot.household.childcareInfo),
      "familyGoals": _goal(snapshot, GoalDomain.family),
    };
  }

  static Map<String, dynamic> _work(LifeContextSnapshot snapshot) {
    return {
      "workStatus": _value(snapshot.work.status),
      "workHours": _value(snapshot.work.legacyWorkHours),
      "workScheduleType": _value(snapshot.work.scheduleType),
      "workDays": snapshot.work.workDays?.value ?? const <String>[],
      "morningStart": _value(snapshot.work.legacyMorningStart),
      "morningEnd": _value(snapshot.work.legacyMorningEnd),
      "afternoonStart": _value(snapshot.work.legacyAfternoonStart),
      "afternoonEnd": _value(snapshot.work.legacyAfternoonEnd),
      "variableWorkDetails": _value(snapshot.work.variableWorkDetails),
      "workTimeRanges": snapshot.work.timeRanges.map(_timeRange).toList(),
      "businessGoals": _goal(snapshot, GoalDomain.professional),
    };
  }

  static List<Map<String, dynamic>> _children(
    LifeContextSnapshot snapshot,
  ) {
    return List.generate(snapshot.household.children.length, (index) {
      final child = snapshot.household.children[index];
      final routine = index < snapshot.routines.childRoutines.length
          ? snapshot.routines.childRoutines[index]
          : null;

      return {
        "firstName": _value(child.firstName),
        "age": _value(child.age),
        "birthDate": _value(child.birthDate),
        "gender": _value(child.gender),
        "school": _value(child.school),
        "className": _value(child.className),
        "allergies": _value(child.allergies),
        "medicalNotes": _value(child.medicalNotes),
        "schoolTimeRanges":
            routine?.schoolTimeRanges.map(_timeRange).toList() ??
                const <Map<String, dynamic>>[],
        "activities": routine?.activities.map(_activity).toList() ??
            const <Map<String, dynamic>>[],
        "notes": _value(child.notes),
      };
    });
  }

  static Map<String, dynamic> _preferences(LifeContextSnapshot snapshot) {
    return {
      "aiTone": _value(snapshot.preferences.aiTone),
      "planningStyle": _value(snapshot.preferences.planningStyle),
      "notificationLevel": _value(snapshot.preferences.notificationLevel),
      "mainLifePriority": _value(snapshot.preferences.mainLifePriority),
      "preferences": _value(snapshot.preferences.legacyPreferences),
      "habits": _value(snapshot.routines.legacyHabits),
      "goals": _goal(snapshot, GoalDomain.historical),
      "personalGoals": _goal(snapshot, GoalDomain.personal),
      "foodPreferences": _value(snapshot.preferences.foodPreferences),
    };
  }

  static Map<String, dynamic> _health(LifeContextSnapshot snapshot) {
    return {
      "allergies": _value(snapshot.constraints.allergies),
      "medicalNotes": _value(snapshot.constraints.medicalNotes),
      "bloodType": _value(snapshot.constraints.bloodType),
      "doctorName": _value(snapshot.constraints.doctorName),
      "emergencyContactName": _value(snapshot.constraints.emergencyContactName),
      "emergencyContactPhone":
          _value(snapshot.constraints.emergencyContactPhone),
    };
  }

  static Map<String, dynamic> _lifeContext(
    LifeContextSnapshot snapshot, {
    required String legacyPersonalNotes,
    required String legacyAdminNotes,
    required String legacyBudgetNotes,
  }) {
    return {
      "personalNotes": legacyPersonalNotes,
      "vehicleInfo": _value(snapshot.mobility.vehicleInfo),
      "petsInfo": _value(snapshot.household.petsInfo),
      "transportInfo": _value(snapshot.mobility.transportInfo),
      "adminNotes": legacyAdminNotes,
      "budgetNotes": legacyBudgetNotes,
      "importantPlaces": _value(snapshot.places.importantPlaces),
      "personalActivities":
          snapshot.routines.personalActivities.map(_activity).toList(),
    };
  }

  static Map<String, dynamic> _timeRange(LifeContextTimeRange range) {
    return {
      "label": _value(range.label),
      "startTime": _value(range.startTime),
      "endTime": _value(range.endTime),
      "travelMinutes": _value(range.travelMinutes),
      "notes": _value(range.notes),
    };
  }

  static Map<String, dynamic> _activity(LifeContextActivity activity) {
    return {
      "title": _value(activity.title),
      "location": _value(activity.location),
      "days": activity.days?.value ?? const <String>[],
      "timeRanges": activity.timeRanges.map(_timeRange).toList(),
      "travelMinutes": _value(activity.travelMinutes),
      "notes": _value(activity.notes),
    };
  }

  static String _goal(LifeContextSnapshot snapshot, GoalDomain domain) {
    for (final goal in snapshot.goals.goals) {
      if (goal.domain == domain) return goal.description.value;
    }
    return '';
  }

  static String _value(LifeContextFact<String>? fact) => fact?.value ?? '';

  static String buildReadableSummary(UserProfile profile) {
    final context = buildStructuredContext(profile);
    return context.entries
        .where((entry) => entry.value.toString().trim().isNotEmpty)
        .map((entry) => "${entry.key}: ${entry.value}")
        .join("\n");
  }
}
