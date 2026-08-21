import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/app_settings.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/services/app_settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final now = DateTime.utc(2026, 8, 21, 12);

  test('migrates legacy profile once then keeps canonical settings', () async {
    final repository = _MemoryRepository();
    final service = AppSettingsService(
      repository: repository,
      now: () => now,
    );

    final migrated = await service.loadOrMigrate(
      accountScopeId: 'account-a',
      legacyProfile: _profile(planningStyle: 'Souple'),
    );
    final canonical = await service.loadOrMigrate(
      accountScopeId: 'account-a',
      legacyProfile: _profile(planningStyle: 'Rigide'),
    );

    expect(migrated.source, AppSettingsSource.legacyProfileMigration);
    expect(migrated.revision, 1);
    expect(canonical.planningStyle, 'Souple');
    expect(repository.saveCount, 1);
  });

  test('explicit profile setting change increments canonical revision',
      () async {
    final repository = _MemoryRepository();
    final service = AppSettingsService(
      repository: repository,
      now: () => now,
    );
    await service.loadOrMigrate(
      accountScopeId: 'account-a',
      legacyProfile: _profile(planningStyle: 'Souple'),
    );

    final saved = await service.saveFromCompatibilityProfile(
      accountScopeId: 'account-a',
      profile: _profile(
        planningStyle: 'Structuré',
        automaticTravelCalculationEnabled: true,
      ),
    );

    expect(saved.revision, 2);
    expect(saved.source, AppSettingsSource.explicitUserSetting);
    expect(saved.planningStyle, 'Structuré');
    expect(saved.automaticTravelCalculationEnabled, isTrue);
  });

  test('compatibility view is projected from canonical settings', () {
    final settings = AppSettings.fromLegacyProfile(
      accountScopeId: 'account-a',
      profile: _profile(
        planningStyle: 'Canonique',
        automaticTravelCalculationEnabled: true,
      ),
      changedAt: now,
    );

    final projected = settings.projectOnto(
      _profile(planningStyle: 'Ancien affichage'),
    );

    expect(projected.planningStyle, 'Canonique');
    expect(projected.automaticTravelCalculationEnabled, isTrue);
    expect(projected.firstName, 'Sophia');
  });

  test('shared preferences repository isolates account scopes', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = SharedPreferencesAppSettingsRepository(preferences);
    final first = AppSettings.fromLegacyProfile(
      accountScopeId: 'account-a',
      profile: _profile(planningStyle: 'A'),
      changedAt: now,
    );
    final second = AppSettings.fromLegacyProfile(
      accountScopeId: 'account-b',
      profile: _profile(planningStyle: 'B'),
      changedAt: now,
    );

    await repository.save(first);
    await repository.save(second);

    expect((await repository.load('account-a'))?.planningStyle, 'A');
    expect((await repository.load('account-b'))?.planningStyle, 'B');
  });
}

UserProfile _profile({
  required String planningStyle,
  bool automaticTravelCalculationEnabled = false,
}) =>
    UserProfile(
      firstName: 'Sophia',
      familyStatus: '',
      workStatus: '',
      partnerName: '',
      wantsNotifications: true,
      automaticTravelCalculationEnabled: automaticTravelCalculationEnabled,
      children: const [],
      aiTone: 'Doux',
      planningStyle: planningStyle,
      notificationLevel: 'Essentiel',
      spokenLanguage: 'Français',
      country: 'France',
      timeZone: 'Europe/Paris',
    );

final class _MemoryRepository implements AppSettingsRepository {
  final Map<String, AppSettings> values = {};
  int saveCount = 0;

  @override
  Future<AppSettings?> load(String accountScopeId) async =>
      values[accountScopeId];

  @override
  Future<void> save(AppSettings settings) async {
    saveCount += 1;
    values[settings.accountScopeId] = settings;
  }
}
