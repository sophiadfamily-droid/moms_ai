import 'dart:collection';

import '../user_profile.dart';

enum ProfileOwnedField {
  workStatus,
  wantsNotifications,
  automaticTravelCalculationEnabled,
  workHours,
  workScheduleType,
  workDays,
  morningStart,
  morningEnd,
  afternoonStart,
  afternoonEnd,
  variableWorkDetails,
  workTimeRanges,
  workTravelMinutes,
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
  personalActivities,
  partnerNotes,
  partnerWorkSchedule,
}

final class ProfilePatchException implements Exception {
  const ProfilePatchException(this.code);

  final String code;

  @override
  String toString() => 'ProfilePatchException($code)';
}

final class ProfilePatch {
  static const int currentSchemaVersion = 1;
  static const int maximumFields = 20;

  ProfilePatch({
    this.schemaVersion = currentSchemaVersion,
    required this.accountScopeId,
    required this.expectedRevision,
    required Map<ProfileOwnedField, Object> changes,
  }) : changes = UnmodifiableMapView(Map.of(changes)) {
    if (schemaVersion != currentSchemaVersion ||
        accountScopeId.trim().isEmpty ||
        expectedRevision < 1 ||
        changes.isEmpty ||
        changes.length > maximumFields) {
      throw const ProfilePatchException('invalid_profile_patch');
    }
  }

  final int schemaVersion;
  final String accountScopeId;
  final int expectedRevision;
  final Map<ProfileOwnedField, Object> changes;
}

final class ProfilePatchResult {
  static const int currentSchemaVersion = 1;

  ProfilePatchResult({
    this.schemaVersion = currentSchemaVersion,
    required this.accountScopeId,
    required this.expectedRevision,
    required this.nextRevision,
    required List<ProfileOwnedField> changedFields,
    required this.profile,
  }) : changedFields = UnmodifiableListView(
          List<ProfileOwnedField>.of(changedFields)
            ..sort((left, right) => left.index.compareTo(right.index)),
        ) {
    if (schemaVersion != currentSchemaVersion ||
        accountScopeId.trim().isEmpty ||
        expectedRevision < 1 ||
        nextRevision != expectedRevision + 1 ||
        this.changedFields.isEmpty ||
        this.changedFields.toSet().length != this.changedFields.length) {
      throw const ProfilePatchException('invalid_profile_patch_result');
    }
  }

  final int schemaVersion;
  final String accountScopeId;
  final int expectedRevision;
  final int nextRevision;
  final List<ProfileOwnedField> changedFields;
  final UserProfile profile;

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'accountScopeId': accountScopeId,
        'expectedRevision': expectedRevision,
        'nextRevision': nextRevision,
        'changedFields': changedFields.map((field) => field.name).toList(),
        'profile': profile.toJson(),
      };
}
