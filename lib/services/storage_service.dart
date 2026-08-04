import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';
import '../models/revisioned_domain_models.dart';
import '../models/revisioned_sync_protocol.dart';
import '../core/identity/uuid_v7_entity_id_generator.dart';
import 'auth_service.dart';
import 'app_diagnostics.dart';
import 'app_error_classifier.dart';
import 'revisioned_cloud_repositories.dart';
import 'revisioned_domain_sync_service.dart';
import 'revisioned_action_ledger_observer.dart';
import 'profile/profile_patch_mutation_adapter.dart';

class StorageService {
  static const String userProfileKey = "user_profile";

  static const String onboardingDoneKey = "onboarding_done";
  static final ProfileRevisionSyncService _sync = ProfileRevisionSyncService(
    cloud: const FirestoreRevisionedProfileRepository(),
    currentAccountScope: () => AuthService.currentUserId,
  );

  static String _scopedCompatibilityKey(String scope) =>
      'user_profile_compatibility_v1:$scope';

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
    final scope = _currentAccountScope();

    final profileJson = jsonEncode(persistedProfile.toJson());

    await prefs.setString(
      scope == null ? userProfileKey : _scopedCompatibilityKey(scope),
      profileJson,
    );

    await prefs.setBool(
      onboardingDoneKey,
      true,
    );

    try {
      if (scope != null) {
        final current = await _sync.bootstrap(scope);
        final mutationId = idGenerator.generate();
        final patchPlan = current == null
            ? null
            : const ProfilePatchMutationAdapter().plan(
                accountScopeId: scope,
                current: current,
                proposed: persistedProfile,
              );
        if (current != null && patchPlan == null) return persistedProfile;
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
    return persistedProfile;
  }

  static Future<void> saveCompatibilityProfile(UserProfile profile) async {
    final scope = _currentAccountScope();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      scope == null ? userProfileKey : _scopedCompatibilityKey(scope),
      jsonEncode(profile.toJson()),
    );
  }

  static Future<UserProfile?> getUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final scope = _currentAccountScope();

    try {
      final cloudProfile =
          scope == null ? null : (await _sync.bootstrap(scope))?.profile;

      if (cloudProfile != null) {
        await prefs.setString(
          _scopedCompatibilityKey(scope!),
          jsonEncode(cloudProfile.toJson()),
        );

        await prefs.setBool(
          onboardingDoneKey,
          true,
        );

        return cloudProfile;
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

    final profileData = prefs.getString(
      scope == null ? userProfileKey : _scopedCompatibilityKey(scope),
    );

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
