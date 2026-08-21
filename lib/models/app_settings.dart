import 'user_profile.dart';

enum AppSettingsSource {
  legacyProfileMigration,
  explicitUserSetting,
}

/// Canonical owner for application-level preferences that are not human facts.
final class AppSettings {
  static const int currentSchemaVersion = 1;

  AppSettings({
    this.schemaVersion = currentSchemaVersion,
    required this.accountScopeId,
    required this.automaticTravelCalculationEnabled,
    required this.aiTone,
    required this.planningStyle,
    required this.notificationLevel,
    required this.spokenLanguage,
    required this.country,
    required this.timeZone,
    required this.changedAt,
    required this.source,
    required this.revision,
  }) {
    validate();
  }

  final int schemaVersion;
  final String accountScopeId;
  final bool automaticTravelCalculationEnabled;
  final String aiTone;
  final String planningStyle;
  final String notificationLevel;
  final String spokenLanguage;
  final String country;
  final String timeZone;
  final DateTime changedAt;
  final AppSettingsSource source;
  final int revision;

  void validate() {
    if (schemaVersion != currentSchemaVersion ||
        accountScopeId.trim().isEmpty ||
        revision < 1 ||
        changedAt != changedAt.toUtc() ||
        [
          aiTone,
          planningStyle,
          notificationLevel,
          spokenLanguage,
          country,
          timeZone,
        ].any((value) => value.length > 200)) {
      throw const FormatException('invalid_app_settings');
    }
  }

  factory AppSettings.fromLegacyProfile({
    required String accountScopeId,
    required UserProfile profile,
    required DateTime changedAt,
  }) =>
      AppSettings(
        accountScopeId: accountScopeId,
        automaticTravelCalculationEnabled:
            profile.automaticTravelCalculationEnabled,
        aiTone: profile.aiTone.trim(),
        planningStyle: profile.planningStyle.trim(),
        notificationLevel: profile.notificationLevel.trim(),
        spokenLanguage: profile.spokenLanguage.trim(),
        country: profile.country.trim(),
        timeZone: profile.timeZone.trim(),
        changedAt: changedAt.toUtc(),
        source: AppSettingsSource.legacyProfileMigration,
        revision: 1,
      );

  AppSettings copyWith({
    bool? automaticTravelCalculationEnabled,
    String? aiTone,
    String? planningStyle,
    String? notificationLevel,
    String? spokenLanguage,
    String? country,
    String? timeZone,
    DateTime? changedAt,
    AppSettingsSource? source,
    int? revision,
  }) =>
      AppSettings(
        accountScopeId: accountScopeId,
        automaticTravelCalculationEnabled: automaticTravelCalculationEnabled ??
            this.automaticTravelCalculationEnabled,
        aiTone: aiTone ?? this.aiTone,
        planningStyle: planningStyle ?? this.planningStyle,
        notificationLevel: notificationLevel ?? this.notificationLevel,
        spokenLanguage: spokenLanguage ?? this.spokenLanguage,
        country: country ?? this.country,
        timeZone: timeZone ?? this.timeZone,
        changedAt: (changedAt ?? this.changedAt).toUtc(),
        source: source ?? this.source,
        revision: revision ?? this.revision,
      );

  UserProfile projectOnto(UserProfile profile) => profile.copyWith(
        automaticTravelCalculationEnabled: automaticTravelCalculationEnabled,
        aiTone: aiTone,
        planningStyle: planningStyle,
        notificationLevel: notificationLevel,
        spokenLanguage: spokenLanguage,
        country: country,
        timeZone: timeZone,
      );

  bool hasSameValuesAsProfile(UserProfile profile) =>
      automaticTravelCalculationEnabled ==
          profile.automaticTravelCalculationEnabled &&
      aiTone == profile.aiTone.trim() &&
      planningStyle == profile.planningStyle.trim() &&
      notificationLevel == profile.notificationLevel.trim() &&
      spokenLanguage == profile.spokenLanguage.trim() &&
      country == profile.country.trim() &&
      timeZone == profile.timeZone.trim();

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'accountScopeId': accountScopeId,
        'automaticTravelCalculationEnabled': automaticTravelCalculationEnabled,
        'aiTone': aiTone,
        'planningStyle': planningStyle,
        'notificationLevel': notificationLevel,
        'spokenLanguage': spokenLanguage,
        'country': country,
        'timeZone': timeZone,
        'changedAt': changedAt.toIso8601String(),
        'source': source.name,
        'revision': revision,
      };

  factory AppSettings.fromJson(
    Map<String, Object?> json, {
    required String expectedAccountScopeId,
  }) {
    final settings = AppSettings(
      schemaVersion: json['schemaVersion'] as int? ?? -1,
      accountScopeId: json['accountScopeId'] as String? ?? '',
      automaticTravelCalculationEnabled:
          json['automaticTravelCalculationEnabled'] as bool? ?? false,
      aiTone: json['aiTone'] as String? ?? '',
      planningStyle: json['planningStyle'] as String? ?? '',
      notificationLevel: json['notificationLevel'] as String? ?? '',
      spokenLanguage: json['spokenLanguage'] as String? ?? '',
      country: json['country'] as String? ?? '',
      timeZone: json['timeZone'] as String? ?? '',
      changedAt: DateTime.parse(json['changedAt'] as String).toUtc(),
      source: AppSettingsSource.values.singleWhere(
        (value) => value.name == json['source'],
      ),
      revision: json['revision'] as int? ?? -1,
    );
    if (settings.accountScopeId != expectedAccountScopeId) {
      throw const FormatException('app_settings_account_mismatch');
    }
    return settings;
  }
}
