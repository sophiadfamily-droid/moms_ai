import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';
import '../models/revisioned_domain_models.dart';
import '../models/revisioned_sync_protocol.dart';
import 'app_settings_service.dart';
import '../core/identity/uuid_v7_entity_id_generator.dart';
import 'auth_service.dart';
import 'app_diagnostics.dart';
import 'app_error_classifier.dart';
import 'revisioned_cloud_repositories.dart';
import 'revisioned_domain_sync_service.dart';
import 'revisioned_action_ledger_observer.dart';
import 'profile/profile_patch_mutation_adapter.dart';
import 'settings_context_version.dart';
import 'legacy_profile_memory_migration_service.dart';
import 'memory_lifecycle_repository.dart';
import 'memory_service.dart';

class StorageService {
  static const String userProfileKey = "user_profile";

  static const String onboardingDoneKey = "onboarding_done";
  static final ProfileRevisionSyncService _sync = ProfileRevisionSyncService(
    cloud: const FirestoreRevisionedProfileRepository(),
    currentAccountScope: () => AuthService.currentUserId,
  );

  static String _scopedCompatibilityKey(String scope) =>
      'user_profile_compatibility_v1:$scope';

  static String _profileMemoryMigrationKey(String scope) =>
      'legacy_profile_memory_migration_v1:$scope';

  static Future<UserProfile> saveUserProfile(
    UserProfile profile,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final scope = _currentAccountScope();
    var persistedProfile = prepareCompatibilityProfile(profile);

    if (scope != null) {
      final settings = await AppSettingsService(
        repository: SharedPreferencesAppSettingsRepository(prefs),
      ).saveFromCompatibilityProfile(
        accountScopeId: scope,
        profile: persistedProfile,
      );
      persistedProfile = settings.projectOnto(persistedProfile);
    }

    final profileJson = jsonEncode(persistedProfile.toJson());

    await prefs.setString(
      scope == null ? userProfileKey : _scopedCompatibilityKey(scope),
      profileJson,
    );

    await prefs.setBool(
      onboardingDoneKey,
      true,
    );
    SettingsContextVersion.notifyChanged();

    try {
      if (scope != null) {
        final current = await _sync.bootstrap(scope);
        final idGenerator = UuidV7EntityIdGenerator();
        final mutationId = idGenerator.generate();
        final patchPlan = current == null
            ? null
            : const ProfilePatchMutationAdapter().plan(
                accountScopeId: scope,
                current: current,
                proposed: persistedProfile,
              );
        if (current == null || patchPlan != null) {
          final mutation = ProfileMutation(
            mutationId: mutationId,
            targetId: RevisionedProfileState.entityId,
            expectedRevision: current?.revision ?? 0,
            createdAt: DateTime.now().toUtc(),
            attempt: 0,
            nextRetryAt: null,
            state: RevisionedMutationState.queued,
            type: current == null
                ? ProfileMutationType.updateCompatibilityProjection
                : ProfileMutationType.updateProfileFields,
            changedFields: patchPlan?.changedFields ??
                ProfileFieldOwnership.profileOwnedFields,
            profile: patchPlan?.profile ?? persistedProfile,
          );
          final result = await RevisionedActionLedgerObserver.profile(
            scope,
            mutation,
            () => _sync.apply(scope, mutation),
          );
          if (!result.isRealSuccess &&
              result.status != RevisionedCloudWriteStatus.unavailable) {
            throw const FormatException('profile_sync_conflict');
          }
        }
      }
    } catch (error) {
      final descriptor = AppErrorClassifier.classify(
        error,
        boundary: AppErrorBoundaryKind.synchronization,
      );
      AppDiagnostics.record(
        component: 'profile_storage',
        domain: 'profile',
        operation: 'save',
        step: 'cloud_sync',
        code: descriptor.code,
        severity: descriptor.severity,
        retryStrategy: descriptor.retryStrategy,
        correlationId: descriptor.correlationId,
        sourceExceptionType: AppErrorClassifier.safeExceptionType(error),
      );
    }
    if (scope != null) {
      await _migrateSafeLegacyProfileMemories(
        preferences: prefs,
        accountScopeId: scope,
        profile: persistedProfile,
      );
    }
    return persistedProfile;
  }

  /// Ensures that the compatibility view points at stable HumanModel records.
  ///
  /// This does not persist anything. Profile screens can therefore prepare a
  /// candidate, commit it to HumanModel first, and only then store the derived
  /// compatibility projection.
  static UserProfile prepareCompatibilityProfile(UserProfile profile) {
    const idGenerator = UuidV7EntityIdGenerator();
    return profile.copyWith(
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
  }

  static Future<void> saveCompatibilityProfile(UserProfile profile) async {
    final scope = _currentAccountScope();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      scope == null ? userProfileKey : _scopedCompatibilityKey(scope),
      jsonEncode(profile.toJson()),
    );
    SettingsContextVersion.notifyChanged();
  }

  static Future<UserProfile?> getUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final scope = _currentAccountScope();
    final compatibilityKey =
        scope == null ? userProfileKey : _scopedCompatibilityKey(scope);
    final localCompatibility = _decodeProfile(
      prefs.getString(compatibilityKey),
    );

    try {
      final cloudProfile =
          scope == null ? null : (await _sync.bootstrap(scope))?.profile;

      if (cloudProfile != null) {
        final restoredProfile = mergeProfileOwnedCloudWithCompatibility(
          cloud: cloudProfile,
          localCompatibility: localCompatibility,
        );
        await prefs.setString(
          _scopedCompatibilityKey(scope!),
          jsonEncode(restoredProfile.toJson()),
        );

        await prefs.setBool(
          onboardingDoneKey,
          true,
        );

        final projected = await _projectCanonicalSettings(
          preferences: prefs,
          accountScopeId: scope,
          compatibility: restoredProfile,
        );
        await _migrateSafeLegacyProfileMemories(
          preferences: prefs,
          accountScopeId: scope,
          profile: projected,
        );
        return projected;
      }
    } catch (error) {
      final descriptor = AppErrorClassifier.classify(
        error,
        boundary: AppErrorBoundaryKind.synchronization,
      );
      AppDiagnostics.record(
        component: 'profile_storage',
        domain: 'profile',
        operation: 'load',
        step: 'cloud_load',
        code: descriptor.code,
        severity: descriptor.severity,
        retryStrategy: descriptor.retryStrategy,
        correlationId: descriptor.correlationId,
        sourceExceptionType: AppErrorClassifier.safeExceptionType(error),
      );
    }

    if (scope == null || localCompatibility == null) {
      return localCompatibility;
    }
    final projected = await _projectCanonicalSettings(
      preferences: prefs,
      accountScopeId: scope,
      compatibility: localCompatibility,
    );
    await _migrateSafeLegacyProfileMemories(
      preferences: prefs,
      accountScopeId: scope,
      profile: projected,
    );
    return projected;
  }

  static Future<void> _migrateSafeLegacyProfileMemories({
    required SharedPreferences preferences,
    required String accountScopeId,
    required UserProfile profile,
  }) async {
    final fingerprint =
        LegacyProfileMemoryMigrationService.profileFingerprint(profile);
    final markerKey = _profileMemoryMigrationKey(accountScopeId);
    if (preferences.getString(markerKey) == fingerprint) return;
    try {
      final result = await const LegacyProfileMemoryMigrationService().migrate(
        accountScopeId: accountScopeId,
        profile: profile,
        repository: FirestoreMemoryLifecycleRepository(),
        referenceDate: DateTime.now().toUtc(),
      );
      if (result.createdCount > 0) {
        MemoryService.notifyMemoriesChanged();
      }
      await preferences.setString(markerKey, fingerprint);
    } catch (error) {
      final descriptor = AppErrorClassifier.classify(
        error,
        boundary: AppErrorBoundaryKind.synchronization,
      );
      AppDiagnostics.record(
        component: 'profile_memory_migration',
        domain: 'memory',
        operation: 'migrate',
        step: 'safe_legacy_profile_fields',
        code: descriptor.code,
        severity: descriptor.severity,
        retryStrategy: descriptor.retryStrategy,
        correlationId: descriptor.correlationId,
        sourceExceptionType: AppErrorClassifier.safeExceptionType(error),
      );
    }
  }

  static Future<UserProfile> _projectCanonicalSettings({
    required SharedPreferences preferences,
    required String accountScopeId,
    required UserProfile compatibility,
  }) async {
    final settings = await AppSettingsService(
      repository: SharedPreferencesAppSettingsRepository(preferences),
    ).loadOrMigrate(
      accountScopeId: accountScopeId,
      legacyProfile: compatibility,
    );
    return settings.projectOnto(compatibility);
  }

  static UserProfile mergeProfileOwnedCloudWithCompatibility({
    required UserProfile cloud,
    required UserProfile? localCompatibility,
  }) {
    if (localCompatibility == null) return cloud;
    final merged = Map<String, dynamic>.from(localCompatibility.toJson());
    final cloudJson = cloud.toJson();
    for (final field in ProfileFieldOwnership.profileOwnedFields) {
      if (cloudJson.containsKey(field)) merged[field] = cloudJson[field];
    }
    merged.addAll(cloud.legacyExtensions);
    return UserProfile.fromJson(merged);
  }

  static UserProfile? _decodeProfile(String? encoded) {
    if (encoded == null) return null;
    try {
      return UserProfile.fromJson(
        Map<String, dynamic>.from(jsonDecode(encoded) as Map),
      );
    } on Object {
      return null;
    }
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
    final scope = _currentAccountScope();

    await prefs.remove(
      scope == null ? userProfileKey : _scopedCompatibilityKey(scope),
    );

    await prefs.setBool(
      onboardingDoneKey,
      false,
    );
  }

  static String? _currentAccountScope() {
    try {
      return AuthService.currentUserId;
    } on Object {
      return null;
    }
  }
}
