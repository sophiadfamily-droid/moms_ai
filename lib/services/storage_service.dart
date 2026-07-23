import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';
import '../core/identity/uuid_v7_entity_id_generator.dart';
import 'cloud_profile_service.dart';
import 'app_diagnostics.dart';

class StorageService {
  static const String userProfileKey = "user_profile";

  static const String onboardingDoneKey = "onboarding_done";

  static Future<UserProfile> saveUserProfile(
    UserProfile profile,
  ) async {
    const idGenerator = UuidV7EntityIdGenerator();
    final persistedProfile = profile.copyWith(
      humanPersonId: profile.humanPersonId.trim().isEmpty
          ? idGenerator.generate()
          : profile.humanPersonId,
      partnerHumanPersonId: profile.partnerName.trim().isNotEmpty &&
              profile.partnerHumanPersonId.trim().isEmpty
          ? idGenerator.generate()
          : profile.partnerHumanPersonId,
      children: profile.children
          .map(
            (child) => child.humanPersonId.trim().isEmpty
                ? child.copyWith(humanPersonId: idGenerator.generate())
                : child,
          )
          .toList(growable: false),
    );
    final prefs = await SharedPreferences.getInstance();

    final profileJson = jsonEncode(persistedProfile.toJson());

    await prefs.setString(
      userProfileKey,
      profileJson,
    );

    await prefs.setBool(
      onboardingDoneKey,
      true,
    );

    try {
      await CloudProfileService.saveProfile(persistedProfile);
    } catch (_) {
      AppDiagnostics.record(
        component: 'profile_storage',
        step: 'cloud_sync',
        code: AppErrorCode.syncFailure,
      );
    }
    return persistedProfile;
  }

  static Future<UserProfile?> getUserProfile() async {
    final prefs = await SharedPreferences.getInstance();

    try {
      final cloudProfile = await CloudProfileService.getProfile();

      if (cloudProfile != null) {
        await prefs.setString(
          userProfileKey,
          jsonEncode(cloudProfile.toJson()),
        );

        await prefs.setBool(
          onboardingDoneKey,
          true,
        );

        return cloudProfile;
      }
    } catch (_) {
      AppDiagnostics.record(
        component: 'profile_storage',
        step: 'cloud_load',
        code: AppErrorCode.syncFailure,
      );
    }

    final profileData = prefs.getString(userProfileKey);

    if (profileData == null) {
      return null;
    }

    final decodedData = jsonDecode(profileData);

    return UserProfile.fromJson(
      Map<String, dynamic>.from(decodedData),
    );
  }

  static Future<bool> isOnboardingDone() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getBool(
          onboardingDoneKey,
        ) ??
        false;
  }

  static Future<void> resetOnboarding() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(userProfileKey);

    await prefs.setBool(
      onboardingDoneKey,
      false,
    );
  }
}
