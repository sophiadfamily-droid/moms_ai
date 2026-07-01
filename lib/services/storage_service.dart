import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';
import 'cloud_profile_service.dart';

class StorageService {
  static const String userProfileKey = "user_profile";

  static const String onboardingDoneKey = "onboarding_done";

  static Future<void> saveUserProfile(
    UserProfile profile,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    final profileJson = jsonEncode(profile.toJson());

    await prefs.setString(
      userProfileKey,
      profileJson,
    );

    await prefs.setBool(
      onboardingDoneKey,
      true,
    );

    try {
      await CloudProfileService.saveProfile(profile);
    } catch (_) {
      // Zélia reste utilisable hors ligne ou sans compte connecté.
    }
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
      // Si Firestore est indisponible, on retombe sur le profil local.
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
