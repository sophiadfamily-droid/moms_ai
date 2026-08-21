import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/action_autonomy_policy.dart';
import 'package:moms_ai/models/app_settings.dart';
import 'package:moms_ai/models/life_context/life_context_domains.dart';
import 'package:moms_ai/models/local_notification_models.dart';
import 'package:moms_ai/models/memory_policy.dart';
import 'package:moms_ai/services/life_context/life_context_adapter.dart';
import 'package:moms_ai/services/life_context/life_context_domain_adapters.dart';

void main() {
  final now = DateTime.utc(2026, 8, 21, 10);

  test('agrège les propriétaires canoniques sans devenir une nouvelle source',
      () async {
    final section = await SettingsLifeContextAdapter(
      loadAppSettings: (scope) async => AppSettings(
        accountScopeId: scope,
        automaticTravelCalculationEnabled: true,
        aiTone: '',
        planningStyle: ' souple ',
        notificationLevel: ' essentiel ',
        spokenLanguage: ' Français ',
        country: ' France ',
        timeZone: ' Europe/Paris ',
        changedAt: now,
        source: AppSettingsSource.explicitUserSetting,
        revision: 4,
      ),
      loadNotifications: (scope) async => NotificationSettings(
        accountScopeId: scope,
        enabled: true,
        permissionPromptExplained: true,
        privacyMode: NotificationPrivacyMode.genericOnly,
        soundEnabled: true,
        vibrationEnabled: false,
        badgeEnabled: true,
        timezoneId: 'Europe/Paris',
        changedAt: now,
        source: NotificationSettingsSource.explicitUserSetting,
        policyRevision: 2,
      ),
      loadActionAutonomy: (scope) async => ActionAutonomyPolicy(
        mode: ActionAutonomyMode.normal,
        changedAt: now,
        changeSource: ActionAutonomyChangeSource.explicitUserSetting,
        accountScopeId: scope,
        policyRevision: 3,
      ),
      loadMemoryPolicy: (scope) async => MemoryPolicy(
        accountScopeId: scope,
        generalMode: MemoryGeneralMode.automatic,
        healthMode: MemoryHealthMode.askEveryTime,
        healthConsentGranted: false,
        changedAt: now,
        changeSource: MemoryPolicyChangeSource.explicitUserSetting,
      ),
    ).load(
      LifeContextAdapterRequest(accountScopeId: 'account-a', readAt: now),
    );

    expect(section.metadata.source, LifeContextSourceKind.settingsRegistry);
    expect(section.metadata.syncStatus, 'aggregated');
    expect(section.automaticTravelCalculationEnabled, isTrue);
    expect(section.notificationsEnabled, isTrue);
    expect(section.notificationSoundEnabled, isTrue);
    expect(section.notificationVibrationEnabled, isFalse);
    expect(section.notificationBadgeEnabled, isTrue);
    expect(section.actionAutonomyMode, 'normal');
    expect(section.memoryGeneralMode, 'automatic');
    expect(section.memoryHealthMode, 'askEveryTime');
    expect(section.planningStyle, 'souple');
    expect(section.notificationLevel, 'essentiel');
    expect(section.spokenLanguage, 'Français');
    expect(section.country, 'France');
    expect(section.timeZone, 'Europe/Paris');
    expect(section.metadata.warningCodes, isEmpty);
    expect(section.metadata.revision, 4);
  });

  test('refuse tout mélange de comptes', () async {
    final section = await SettingsLifeContextAdapter(
      loadAppSettings: (scope) async => _settings(scope, now),
      loadNotifications: (_) async => NotificationSettings.restrictiveDefault(
        accountScopeId: 'account-b',
        timezoneId: 'Europe/Paris',
        changedAt: now,
      ),
      loadActionAutonomy: (scope) async =>
          ActionAutonomyPolicy.restrictiveDefault(
        accountScopeId: scope,
        changedAt: now,
      ),
      loadMemoryPolicy: (scope) async => MemoryPolicy.restrictiveDefault(
        accountScopeId: scope,
        changedAt: now,
      ),
    ).load(
      LifeContextAdapterRequest(accountScopeId: 'account-a', readAt: now),
    );

    expect(
      section.metadata.availability,
      LifeContextAvailability.accountMismatch,
    );
    expect(section.notificationsEnabled, isFalse);
    expect(section.actionAutonomyMode, 'suggestions');
  });

  test('une source illisible produit un état indisponible et restrictif',
      () async {
    final section = await SettingsLifeContextAdapter(
      loadAppSettings: (_) async => throw StateError('settings_unavailable'),
      loadNotifications: (scope) async =>
          NotificationSettings.restrictiveDefault(
        accountScopeId: scope,
        timezoneId: 'Europe/Paris',
        changedAt: now,
      ),
      loadActionAutonomy: (scope) async =>
          ActionAutonomyPolicy.restrictiveDefault(
        accountScopeId: scope,
        changedAt: now,
      ),
      loadMemoryPolicy: (scope) async => MemoryPolicy.restrictiveDefault(
        accountScopeId: scope,
        changedAt: now,
      ),
    ).load(
      LifeContextAdapterRequest(accountScopeId: 'account-a', readAt: now),
    );

    expect(
      section.metadata.availability,
      LifeContextAvailability.unavailable,
    );
    expect(section.metadata.errorCode, 'settings_domain_unavailable');
    expect(section.automaticTravelCalculationEnabled, isFalse);
    expect(section.notificationsEnabled, isFalse);
    expect(section.memoryGeneralMode, 'askEveryTime');
    expect(section.memoryHealthMode, 'disabled');
  });
}

AppSettings _settings(String scope, DateTime now) => AppSettings(
      accountScopeId: scope,
      automaticTravelCalculationEnabled: false,
      aiTone: '',
      planningStyle: '',
      notificationLevel: '',
      spokenLanguage: 'Français',
      country: 'France',
      timeZone: 'Europe/Paris',
      changedAt: now,
      source: AppSettingsSource.legacyProfileMigration,
      revision: 1,
    );
