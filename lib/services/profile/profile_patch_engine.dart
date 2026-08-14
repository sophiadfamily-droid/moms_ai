import 'dart:convert';

import '../../models/profile/profile_patch_models.dart';
import '../../models/revisioned_domain_models.dart';
import '../../models/user_profile.dart';

/// V1-PR.1 applies only Profile-owned corrections, without persistence.
final class ProfilePatchEngine {
  const ProfilePatchEngine();

  ProfilePatchResult apply({
    required String accountScopeId,
    required UserProfile current,
    required ProfilePatch patch,
  }) {
    if (accountScopeId != patch.accountScopeId) {
      throw const ProfilePatchException('profile_patch_account_mismatch');
    }
    final names = patch.changes.keys.map((field) => field.name).toSet();
    try {
      ProfileFieldOwnership.validatePatch(names);
    } on FormatException {
      throw const ProfilePatchException('profile_patch_ownership_mismatch');
    }

    final json = Map<String, dynamic>.from(current.toJson());
    for (final entry in patch.changes.entries) {
      _validateValue(entry.key, entry.value);
      json[entry.key.name] = _jsonValue(entry.value);
    }
    final updated = UserProfile.fromJson(json);
    _preserveHumanOwned(current, updated);
    return ProfilePatchResult(
      accountScopeId: accountScopeId,
      expectedRevision: patch.expectedRevision,
      nextRevision: patch.expectedRevision + 1,
      changedFields: patch.changes.keys.toList(),
      profile: updated,
    );
  }

  void _validateValue(ProfileOwnedField field, Object value) {
    if (field == ProfileOwnedField.wantsNotifications ||
        field == ProfileOwnedField.automaticTravelCalculationEnabled) {
      if (value is! bool) _invalidValue();
      return;
    }
    if (field == ProfileOwnedField.workDays) {
      if (value is! List<String> ||
          value.length > 7 ||
          value.any((item) => item.length > 40)) {
        _invalidValue();
      }
      return;
    }
    if (field == ProfileOwnedField.workTimeRanges) {
      if (value is! List<TimeRangeModel> || value.length > 20) _invalidValue();
      return;
    }
    if (field == ProfileOwnedField.personalActivities) {
      if (value is! List<ActivityModel> || value.length > 50) _invalidValue();
      return;
    }
    if (value is! String || value.length > 4000) _invalidValue();
  }

  Never _invalidValue() =>
      throw const ProfilePatchException('invalid_profile_patch_value');

  Object _jsonValue(Object value) => switch (value) {
        List<TimeRangeModel>() => value.map((item) => item.toJson()).toList(),
        List<ActivityModel>() => value.map((item) => item.toJson()).toList(),
        _ => value,
      };

  void _preserveHumanOwned(UserProfile before, UserProfile after) {
    final left = before.toJson();
    final right = after.toJson();
    if (ProfileFieldOwnership.humanModelFields
        .any((field) => jsonEncode(left[field]) != jsonEncode(right[field]))) {
      throw const ProfilePatchException('profile_human_fields_changed');
    }
  }
}
