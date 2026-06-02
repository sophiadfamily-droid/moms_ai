import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';

class StorageService {
  static const String userProfileKey =
      "user_profile";

  static const String onboardingDoneKey =
      "onboarding_done";

  static Future<void> saveUserProfile(
    UserProfile profile,
  ) async {
    final prefs =
        await SharedPreferences.getInstance();

    final profileJson =
        jsonEncode(profile.toJson());

    await prefs.setString(
      userProfileKey,
      profileJson,
    );

    await prefs.setBool(
      onboardingDoneKey,
      true,
    );
  }

  static Future<UserProfile?>
      getUserProfile() async {
    final prefs =
        await SharedPreferences.getInstance();

    final profileData =
        prefs.getString(userProfileKey);

    if (profileData == null) {
      return null;
    }

    final decodedData =
        jsonDecode(profileData);

    return UserProfile.fromJson(
      Map<String, dynamic>.from(decodedData),
    );
  }

  static Future<bool>
      isOnboardingDone() async {
    final prefs =
        await SharedPreferences.getInstance();

    return prefs.getBool(
          onboardingDoneKey,
        ) ??
        false;
  }

  static Future<void>
      resetOnboarding() async {
    final prefs =
        await SharedPreferences.getInstance();

    await prefs.remove(userProfileKey);

    await prefs.setBool(
      onboardingDoneKey,
      false,
    );
  }
}

