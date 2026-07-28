import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'theme/app_theme.dart';

import 'screens/welcome_screen.dart';
import 'screens/name_screen.dart';
import 'screens/family_status_screen.dart';
import 'screens/work_status_screen.dart';
import 'screens/partner_screen.dart';
import 'screens/children_screen.dart';
import 'screens/main_navigation.dart';
import 'screens/daily_summary_screen.dart';

import 'models/user_profile.dart';

import 'services/storage_service.dart';
import 'services/notification_service.dart';
import 'services/notification_interaction_coordinator.dart';
import 'services/auth_service.dart';
import 'services/app_diagnostics.dart';
import 'services/app_error_classifier.dart';
import 'services/app_global_error_boundary.dart';
import 'services/firebase_security_bootstrap.dart';
import 'services/human/human_model_service.dart';
import 'services/identity/identity_production_services.dart';
import 'services/event_service.dart';
import 'services/proactive_detection_lifecycle.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppGlobalErrorBoundary.install();
  runZonedGuarded(_startApplication, AppGlobalErrorBoundary.captureZoneError);
}

Future<void> _startApplication() async {
  try {
    await AppDiagnostics.initializeLocal();
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    await FirebaseSecurityBootstrap.initializeProduction();

    await NotificationService.init();

    runApp(const ZeliaApp());
  } catch (error, stackTrace) {
    AppGlobalErrorBoundary.captureStartupError(error, stackTrace);
    runApp(const ZeliaStartupFailureApp());
  }
}

class ZeliaStartupFailureApp extends StatelessWidget {
  const ZeliaStartupFailureApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Zélia n’a pas pu démarrer. Ferme puis rouvre l’application.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
          ),
        ),
      );
}

class ZeliaApp extends StatefulWidget {
  const ZeliaApp({super.key});

  @override
  State<ZeliaApp> createState() => _ZeliaAppState();
}

class _ZeliaAppState extends State<ZeliaApp> with WidgetsBindingObserver {
  final navigatorKey = GlobalKey<NavigatorState>();
  int currentStep = 0;

  bool loading = true;
  bool onboardingDone = false;

  UserProfile? savedProfile;

  String firstName = "";
  String familyStatus = "";
  String workStatus = "";
  String partnerName = "";

  List<ChildProfile> children = [];
  StreamSubscription<User?>? _authSubscription;
  String? _activeAccountScopeId;
  int _accountGeneration = 0;

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
    WidgetsBinding.instance.addObserver(this);
    _activeAccountScopeId = AuthService.currentUserId;
    EventService.handleAccountScopeChanged(_activeAccountScopeId);
    _authSubscription = AuthService.authStateChanges.listen((user) {
      final nextScope = user?.uid;
      if (nextScope == _activeAccountScopeId) return;
      EventService.handleAccountScopeChanged(nextScope);
      _activeAccountScopeId = nextScope;
      _reloadForAccountChange();
    });
    loadProfile();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _reloadForAccountChange() async {
    final generation = ++_accountGeneration;
    if (mounted) {
      setState(() {
        loading = true;
        onboardingDone = false;
        savedProfile = null;
        firstName = "";
        familyStatus = "";
        workStatus = "";
        partnerName = "";
        children = [];
      });
    }
    await loadProfile(expectedGeneration: generation);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_evaluateForegroundDetections());
      _openPendingNotificationDestination();
    }
  }

  Future<void> _evaluateForegroundDetections() async {
    try {
      await NotificationService.evaluateDetections(
        DetectionEvaluationTrigger.foreground,
      );
    } catch (error) {
      final descriptor = AppErrorClassifier.classify(error);
      AppDiagnostics.record(
        component: 'notification_detection',
        domain: 'notification',
        operation: 'evaluate',
        step: 'foreground',
        code: descriptor.code,
        severity: descriptor.severity,
        retryStrategy: descriptor.retryStrategy,
        correlationId: descriptor.correlationId,
        sourceExceptionType: AppErrorClassifier.safeExceptionType(error),
      );
    }
  }

  Future<void> _openPendingNotificationDestination() async {
    final intent = await NotificationService.consumePendingInteraction();
    if (!mounted ||
        !onboardingDone ||
        intent?.type != NotificationNavigationIntentType.dailySummary) {
      return;
    }
    navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => const DailySummaryScreen(),
      ),
    );
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

  Future<void> loadProfile({int? expectedGeneration}) async {
    final generation = expectedGeneration ?? _accountGeneration;
    final expectedScope = _activeAccountScopeId;
    final loadedProfile = await StorageService.getUserProfile();
    if (generation != _accountGeneration ||
        expectedScope != AuthService.currentUserId) {
      return;
    }

    final accountScopeId = AuthService.currentUserId;
    if (accountScopeId != null && accountScopeId.trim().isNotEmpty) {
      try {
        final humanModelService = await HumanModelService.createProduction();
        await humanModelService.bootstrap(
          accountScopeId: accountScopeId,
          legacyProfile: loadedProfile,
        );
      } on Object {
        AppDiagnostics.record(
          component: 'human_model_storage',
          step: 'bootstrap',
          code: AppErrorCode.storageFailure,
        );
      }
      try {
        await NotificationService.evaluateDetections(
          DetectionEvaluationTrigger.authenticatedBootstrap,
        );
      } on Object {
        AppDiagnostics.record(
          component: 'proactive_detection',
          step: 'authenticated_bootstrap',
          code: AppErrorCode.storageFailure,
        );
      }
    }

    if (loadedProfile != null) {
      savedProfile = loadedProfile;
      firstName = loadedProfile.firstName;
      familyStatus = normalizeFamilyStatus(loadedProfile.familyStatus);
      workStatus = normalizeWorkStatus(loadedProfile.workStatus);
      partnerName = loadedProfile.partnerName;
      children = loadedProfile.children;
      onboardingDone = true;
    }

    if (!mounted ||
        generation != _accountGeneration ||
        expectedScope != AuthService.currentUserId) {
      return;
    }

    setState(() {
      loading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openPendingNotificationDestination();
    });
  }

  Future<void> saveProfileAndGoHome() async {
    final profile = currentProfile();

    final persistedProfile = await StorageService.saveUserProfile(profile);
    final accountScopeId = AuthService.currentUserId;
    if (accountScopeId != null && accountScopeId.trim().isNotEmpty) {
      try {
        final localHumanModelService = await HumanModelService.createLocal();
        await localHumanModelService.loadOrMigrate(
          accountScopeId: accountScopeId,
          legacyProfile: persistedProfile,
        );
        final humanModelService = await HumanModelService.createProduction();
        await humanModelService.bootstrap(
          accountScopeId: accountScopeId,
          legacyProfile: persistedProfile,
        );
      } on Object {
        AppDiagnostics.record(
          component: 'human_model_storage',
          step: 'onboarding_bootstrap',
          code: AppErrorCode.storageFailure,
        );
      }
    }

    if (!mounted) return;

    setState(() {
      savedProfile = persistedProfile;
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
        navigatorKey: navigatorKey,
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
        key: ValueKey('main-navigation:${_activeAccountScopeId ?? 'guest'}'),
        accountScopeId: _activeAccountScopeId,
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
            onNext: (name) async {
              setState(() {
                firstName = name;
              });
              await saveProfileAndGoHome();
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
            key: ValueKey(
              'main-navigation:${_activeAccountScopeId ?? 'guest'}',
            ),
            accountScopeId: _activeAccountScopeId,
            profile: currentProfile(),
            onProfileUpdated: updateSavedProfile,
            identityServices: buildIdentityServices(),
          );
      }
    }

    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: currentScreen,
    );
  }
}
