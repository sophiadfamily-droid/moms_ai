import 'dart:convert';

import '../../models/profile/profile_patch_models.dart';
import '../../models/revisioned_domain_models.dart';
import '../../models/user_profile.dart';
import 'profile_patch_engine.dart';

/// PR.2 validates changed Profile-owned fields through PR.1 before persistence.
final class ProfilePatchMutationPlan {
  const ProfilePatchMutationPlan({required this.result});

  final ProfilePatchResult result;

  Set<String> get changedFields =>
      result.changedFields.map((field) => field.name).toSet();

  UserProfile get profile => result.profile;
}

final class ProfilePatchMutationAdapter {
  const ProfilePatchMutationAdapter();

  ProfilePatchMutationPlan? plan({
    required String accountScopeId,
    required RevisionedProfileState current,
    required UserProfile proposed,
  }) {
    final before = current.profile.toJson();
    final after = proposed.toJson();
    final changes = <ProfileOwnedField, Object>{};
    for (final field in ProfileOwnedField.values) {
      if (jsonEncode(before[field.name]) == jsonEncode(after[field.name])) {
        continue;
      }
      changes[field] = _typedValue(field, proposed, after[field.name]);
    }
    if (changes.isEmpty) return null;
    final result = const ProfilePatchEngine().apply(
      accountScopeId: accountScopeId,
      current: current.profile,
      patch: ProfilePatch(
        accountScopeId: accountScopeId,
        expectedRevision: current.revision,
        changes: changes,
      ),
    );
    return ProfilePatchMutationPlan(result: result);
  }

  Object _typedValue(
    ProfileOwnedField field,
    UserProfile profile,
    Object? jsonValue,
  ) =>
      switch (field) {
        ProfileOwnedField.wantsNotifications => profile.wantsNotifications,
        ProfileOwnedField.automaticTravelCalculationEnabled =>
          profile.automaticTravelCalculationEnabled,
        ProfileOwnedField.workDays => List<String>.of(profile.workDays),
        ProfileOwnedField.workTimeRanges =>
          List<TimeRangeModel>.of(profile.workTimeRanges),
        ProfileOwnedField.personalActivities =>
          List<ActivityModel>.of(profile.personalActivities),
        _ => jsonValue is String
            ? jsonValue
            : throw const ProfilePatchException(
                'invalid_profile_patch_value',
              ),
      };
}
