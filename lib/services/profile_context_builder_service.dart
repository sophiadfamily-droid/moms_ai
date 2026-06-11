import '../models/user_profile.dart';
import 'profile_reasoning_service.dart';

class ProfileContextBuilderService {
  static Map<String, dynamic> buildStructuredContext(UserProfile profile) {
    final profileReasoning = ProfileReasoningService.buildReasoning(profile);

    return {
      "identity": _identity(profile),
      "family": _family(profile),
      "work": _work(profile),
      "children": _children(profile),
      "preferences": _preferences(profile),
      "health": _health(profile),
      "lifeContext": _lifeContext(profile),
      "planningReasoning": profileReasoning,
    };
  }

  static Map<String, dynamic> _identity(UserProfile profile) {
    return {
      "firstName": profile.firstName,
      "age": profile.age,
      "birthDate": profile.birthDate,
      "country": profile.country,
      "timeZone": profile.timeZone,
      "spokenLanguage": profile.spokenLanguage,
    };
  }

  static Map<String, dynamic> _family(UserProfile profile) {
    return {
      "familyStatus": profile.familyStatus,
      "relationshipStatus": profile.relationshipStatus,
      "partnerName": profile.partnerName,
      "childrenCount": profile.children.length,
      "childcareInfo": profile.childcareInfo,
      "familyGoals": profile.familyGoals,
    };
  }

  static Map<String, dynamic> _work(UserProfile profile) {
    return {
      "workStatus": profile.workStatus,
      "workHours": profile.workHours,
      "workScheduleType": profile.workScheduleType,
      "workDays": profile.workDays,
      "morningStart": profile.morningStart,
      "morningEnd": profile.morningEnd,
      "afternoonStart": profile.afternoonStart,
      "afternoonEnd": profile.afternoonEnd,
      "variableWorkDetails": profile.variableWorkDetails,
      "workTimeRanges":
          profile.workTimeRanges.map((range) => range.toJson()).toList(),
      "businessGoals": profile.businessGoals,
    };
  }

  static List<Map<String, dynamic>> _children(UserProfile profile) {
    return profile.children.map((child) {
      return {
        "firstName": child.firstName,
        "age": child.age,
        "birthDate": child.birthDate,
        "gender": child.gender,
        "school": child.school,
        "className": child.className,
        "allergies": child.allergies,
        "medicalNotes": child.medicalNotes,
        "schoolTimeRanges":
            child.schoolTimeRanges.map((range) => range.toJson()).toList(),
        "activities":
            child.activities.map((activity) => activity.toJson()).toList(),
        "notes": child.notes,
      };
    }).toList();
  }

  static Map<String, dynamic> _preferences(UserProfile profile) {
    return {
      "aiTone": profile.aiTone,
      "planningStyle": profile.planningStyle,
      "notificationLevel": profile.notificationLevel,
      "mainLifePriority": profile.mainLifePriority,
      "preferences": profile.preferences,
      "habits": profile.habits,
      "goals": profile.goals,
      "personalGoals": profile.personalGoals,
      "foodPreferences": profile.foodPreferences,
    };
  }

  static Map<String, dynamic> _health(UserProfile profile) {
    return {
      "allergies": profile.allergies,
      "medicalNotes": profile.medicalNotes,
      "bloodType": profile.bloodType,
      "doctorName": profile.doctorName,
      "emergencyContactName": profile.emergencyContactName,
      "emergencyContactPhone": profile.emergencyContactPhone,
    };
  }

  static Map<String, dynamic> _lifeContext(UserProfile profile) {
    return {
      "personalNotes": profile.personalNotes,
      "vehicleInfo": profile.vehicleInfo,
      "petsInfo": profile.petsInfo,
      "transportInfo": profile.transportInfo,
      "adminNotes": profile.adminNotes,
      "budgetNotes": profile.budgetNotes,
      "importantPlaces": profile.importantPlaces,
      "personalActivities": profile.personalActivities
          .map((activity) => activity.toJson())
          .toList(),
    };
  }

  static String buildReadableSummary(UserProfile profile) {
    final context = buildStructuredContext(profile);
    return context.entries
        .where((entry) => entry.value.toString().trim().isNotEmpty)
        .map((entry) => "${entry.key}: ${entry.value}")
        .join("\n");
  }
}
