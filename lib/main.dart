import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';
import 'theme/app_theme.dart';

import 'screens/welcome_screen.dart';
import 'screens/name_screen.dart';
import 'screens/family_status_screen.dart';
import 'screens/work_status_screen.dart';
import 'screens/partner_screen.dart';
import 'screens/children_screen.dart';
import 'screens/main_navigation.dart';

import 'models/user_profile.dart';

import 'services/storage_service.dart';
import 'services/notification_service.dart';
import 'services/auth_service.dart';
import 'services/identity/identity_production_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await NotificationService.init();

  runApp(const ZeliaApp());
}

class ZeliaApp extends StatefulWidget {
  const ZeliaApp({super.key});

  @override
  State<ZeliaApp> createState() => _ZeliaAppState();
}

class _ZeliaAppState extends State<ZeliaApp> {
  int currentStep = 0;

  bool loading = true;
  bool onboardingDone = false;

  UserProfile? savedProfile;

  String firstName = "";
  String familyStatus = "";
  String workStatus = "";
  String partnerName = "";

  List<ChildProfile> children = [];

  IdentityProductionServices? buildIdentityServices() {
    final accountId = AuthService.currentUserId;
    if (accountId == null || accountId.trim().isEmpty) return null;
    return IdentityProductionServices.create(
      firestore: FirebaseFirestore.instance,
      accountId: accountId,
    );
  }

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  String normalizeFamilyStatus(String value) {
    final status = value.toLowerCase();

    if (status.contains("seule")) return "Je vis seule 💕";

    if (status.contains("maman solo") || status.contains("monoparent")) {
      return "Famille monoparentale 🌸";
    }

    if (status.contains("enfant") || status.contains("famille")) {
      return "Nous sommes une famille avec enfants 👨‍👩‍👧";
    }

    if (status.contains("couple") || status.contains("partenaire")) {
      return "Je vis avec mon partenaire 🫶🏻";
    }

    if (status.contains("compli")) return "C’est un peu compliqué ✨";

    return value;
  }

  String normalizeWorkStatus(String value) {
    final status = value.toLowerCase();

    if (status.contains("entrepreneuse")) return "Je suis entrepreneuse ✨";

    if (status.contains("temps plein") ||
        status.contains("temps partiel") ||
        status.contains("salari")) {
      return "Je suis salariée 💼";
    }

    if (status.contains("maison") || status.contains("foyer")) {
      return "Je suis maman au foyer 🌸";
    }

    if (status.contains("étudiante") || status.contains("etudiante")) {
      return "Je suis étudiante 📚";
    }

    if (status.contains("transition") ||
        status.contains("recherche") ||
        status.contains("autre")) {
      return "Autre / recherche 🌿";
    }

    return value;
  }

  UserProfile currentProfile() {
    final cleanFamilyStatus = normalizeFamilyStatus(familyStatus);
    final cleanWorkStatus = normalizeWorkStatus(workStatus);

    final existing = savedProfile;

    if (existing != null) {
      return existing.copyWith(
        firstName: firstName.isNotEmpty ? firstName : existing.firstName,
        familyStatus: cleanFamilyStatus.isNotEmpty
            ? cleanFamilyStatus
            : existing.familyStatus,
        workStatus:
            cleanWorkStatus.isNotEmpty ? cleanWorkStatus : existing.workStatus,
        partnerName:
            partnerName.isNotEmpty ? partnerName : existing.partnerName,
        children: children,
      );
    }

    return UserProfile(
      firstName: firstName,
      familyStatus: cleanFamilyStatus,
      workStatus: cleanWorkStatus,
      partnerName: partnerName,
      wantsNotifications: true,
      children: children,
    );
  }

  Future<void> loadProfile() async {
    final loadedProfile = await StorageService.getUserProfile();

    if (loadedProfile != null) {
      savedProfile = loadedProfile;
      firstName = loadedProfile.firstName;
      familyStatus = normalizeFamilyStatus(loadedProfile.familyStatus);
      workStatus = normalizeWorkStatus(loadedProfile.workStatus);
      partnerName = loadedProfile.partnerName;
      children = loadedProfile.children;
      onboardingDone = true;
    }

    if (!mounted) return;

    setState(() {
      loading = false;
    });
  }

  Future<void> saveProfileAndGoHome() async {
    final profile = currentProfile();

    await StorageService.saveUserProfile(profile);

    if (!mounted) return;

    setState(() {
      savedProfile = profile;
      onboardingDone = true;
    });
  }

  bool needsPartnerScreen() {
    final status = normalizeFamilyStatus(familyStatus).toLowerCase();

    if (status.contains("monoparent")) return false;

    return status.contains("partenaire") ||
        status.contains("famille avec enfants");
  }

  bool needsChildrenScreen() {
    final status = normalizeFamilyStatus(familyStatus).toLowerCase();

    return status.contains("enfant") ||
        status.contains("monoparent") ||
        status.contains("famille");
  }

  void goToNextAfterWorkStatus() {
    if (needsPartnerScreen()) {
      setState(() {
        currentStep = 4;
      });
    } else if (needsChildrenScreen()) {
      setState(() {
        currentStep = 5;
      });
    } else {
      saveProfileAndGoHome();
    }
  }

  void goToNextAfterPartner() {
    if (needsChildrenScreen()) {
      setState(() {
        currentStep = 5;
      });
    } else {
      saveProfileAndGoHome();
    }
  }

  void updateSavedProfile(UserProfile updatedProfile) {
    setState(() {
      savedProfile = updatedProfile;
      firstName = updatedProfile.firstName;
      familyStatus = normalizeFamilyStatus(updatedProfile.familyStatus);
      workStatus = normalizeWorkStatus(updatedProfile.workStatus);
      partnerName = updatedProfile.partnerName;
      children = updatedProfile.children;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    Widget currentScreen;

    if (onboardingDone) {
      currentScreen = MainNavigation(
        profile: currentProfile(),
        onProfileUpdated: updateSavedProfile,
        identityServices: buildIdentityServices(),
      );
    } else {
      switch (currentStep) {
        case 0:
          currentScreen = WelcomeScreen(
            onStart: () {
              setState(() {
                currentStep = 1;
              });
            },
          );
          break;

        case 1:
          currentScreen = NameScreen(
            onNext: (name) {
              setState(() {
                firstName = name;
                currentStep = 2;
              });
            },
          );
          break;

        case 2:
          currentScreen = FamilyStatusScreen(
            onNext: (status) {
              setState(() {
                familyStatus = normalizeFamilyStatus(status);
                currentStep = 3;
              });
            },
          );
          break;

        case 3:
          currentScreen = WorkStatusScreen(
            onNext: (status) {
              setState(() {
                workStatus = normalizeWorkStatus(status);
              });
              goToNextAfterWorkStatus();
            },
          );
          break;

        case 4:
          currentScreen = PartnerScreen(
            onNext: (partner) {
              setState(() {
                partnerName = partner;
              });
              goToNextAfterPartner();
            },
          );
          break;

        case 5:
          currentScreen = ChildrenScreen(
            onNext: (kids) async {
              setState(() {
                children = kids;
              });
              await saveProfileAndGoHome();
            },
          );
          break;

        default:
          currentScreen = MainNavigation(
            profile: currentProfile(),
            onProfileUpdated: updateSavedProfile,
            identityServices: buildIdentityServices(),
          );
      }
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: currentScreen,
    );
  }
}
