import 'dart:collection';

enum NotificationPlatform { ios, android, unsupported }

enum NotificationPermissionStatus {
  unknown,
  notDetermined,
  authorized,
  denied,
  provisional,
  restricted,
  unavailable,
  permanentlyDenied,
  error,
}

enum NotificationPermissionWarning {
  channelDisabled,
  exactSchedulingUnavailable,
  platformUnavailable,
  checkFailed,
}

final class NotificationPermissionState {
  static const currentSchemaVersion = 1;

  const NotificationPermissionState({
    this.schemaVersion = currentSchemaVersion,
    required this.platform,
    required this.state,
    required this.checkedAt,
    required this.canRequest,
    required this.canOpenSettings,
    required this.notificationsEnabled,
    this.exactSchedulingCapability,
    this.warningCodes = const {},
  });

  final int schemaVersion;
  final NotificationPlatform platform;
  final NotificationPermissionStatus state;
  final DateTime checkedAt;
  final bool canRequest;
  final bool canOpenSettings;
  final bool notificationsEnabled;
  final bool? exactSchedulingCapability;
  final Set<NotificationPermissionWarning> warningCodes;

  void validate() {
    if (schemaVersion != currentSchemaVersion) {
      throw const FormatException('notification_permission_version');
    }
  }
}

enum NotificationPrivacyMode { genericOnly, hiddenContent, systemDefault }

enum NotificationSettingsSource {
  restrictiveDefault,
  explicitUserSetting,
}

enum NotificationQuietHoursBehavior {
  deferUntilQuietHoursEnd,
  includeInNextSummary,
  suppressLowPriority,
  allowCriticalProductAlertsOnly,
}

final class NotificationQuietHours {
  NotificationQuietHours({
    this.enabled = true,
    required this.startMinute,
    required this.endMinute,
    this.timezoneId = 'Etc/UTC',
    Set<int> weekdays = const {1, 2, 3, 4, 5, 6, 7},
    this.behavior = NotificationQuietHoursBehavior.deferUntilQuietHoursEnd,
    DateTime? changedAt,
  })  : weekdays = UnmodifiableSetView(Set<int>.of(weekdays)),
        changedAt =
            (changedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
                .toUtc() {
    if (startMinute < 0 ||
        startMinute > 1439 ||
        endMinute < 0 ||
        endMinute > 1439 ||
        startMinute == endMinute ||
        timezoneId.trim().isEmpty ||
        timezoneId.length > 100 ||
        weekdays.isEmpty ||
        weekdays.any((day) => day < 1 || day > 7)) {
      throw const FormatException('notification_quiet_hours_invalid');
    }
  }

  factory NotificationQuietHours.fromJson(Map<String, Object?> json) {
    const legacyKeys = {'startMinute', 'endMinute'};
    const keys = {
      'enabled',
      'startMinute',
      'endMinute',
      'timezoneId',
      'weekdays',
      'behavior',
      'changedAt',
    };
    final actual = json.keys.toSet();
    if (actual.difference(keys).isNotEmpty &&
        actual.difference(legacyKeys).isNotEmpty) {
      throw const FormatException('notification_quiet_hours_invalid');
    }
    final behavior = json['behavior'] == null
        ? NotificationQuietHoursBehavior.deferUntilQuietHoursEnd
        : NotificationQuietHoursBehavior.values
            .where((item) => item.name == json['behavior'])
            .single;
    return NotificationQuietHours(
      enabled: json['enabled'] as bool? ?? true,
      startMinute: json['startMinute'] as int,
      endMinute: json['endMinute'] as int,
      timezoneId: json['timezoneId'] as String? ?? 'Etc/UTC',
      weekdays: json['weekdays'] == null
          ? const {1, 2, 3, 4, 5, 6, 7}
          : (json['weekdays'] as List).cast<int>().toSet(),
      behavior: behavior,
      changedAt: json['changedAt'] == null
          ? null
          : DateTime.parse(json['changedAt'] as String),
    );
  }

  final bool enabled;
  final int startMinute;
  final int endMinute;
  final String timezoneId;
  final Set<int> weekdays;
  final NotificationQuietHoursBehavior behavior;
  final DateTime changedAt;

  bool get crossesMidnight => startMinute > endMinute;

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'startMinute': startMinute,
        'endMinute': endMinute,
        'timezoneId': timezoneId,
        'weekdays': weekdays.toList()..sort(),
        'behavior': behavior.name,
        'changedAt': changedAt.toUtc().toIso8601String(),
      };
}

final class NotificationSettings {
  static const currentSchemaVersion = 1;

  const NotificationSettings({
    this.schemaVersion = currentSchemaVersion,
    required this.accountScopeId,
    required this.enabled,
    required this.permissionPromptExplained,
    required this.privacyMode,
    required this.soundEnabled,
    required this.vibrationEnabled,
    required this.badgeEnabled,
    this.quietHours,
    required this.timezoneId,
    required this.changedAt,
    required this.source,
    required this.policyRevision,
  });

  factory NotificationSettings.restrictiveDefault({
    required String accountScopeId,
    required String timezoneId,
    required DateTime changedAt,
  }) =>
      NotificationSettings(
        accountScopeId: accountScopeId,
        enabled: false,
        permissionPromptExplained: false,
        privacyMode: NotificationPrivacyMode.genericOnly,
        soundEnabled: false,
        vibrationEnabled: false,
        badgeEnabled: false,
        timezoneId: timezoneId,
        changedAt: changedAt.toUtc(),
        source: NotificationSettingsSource.restrictiveDefault,
        policyRevision: 0,
      );

  factory NotificationSettings.fromJson(
    Map<String, Object?> json, {
    required String expectedAccountScopeId,
  }) {
    const keys = {
      'schemaVersion',
      'accountScopeId',
      'enabled',
      'permissionPromptExplained',
      'privacyMode',
      'soundEnabled',
      'vibrationEnabled',
      'badgeEnabled',
      'quietHours',
      'timezoneId',
      'changedAt',
      'source',
      'policyRevision',
    };
    if (json.keys.toSet().difference(keys).isNotEmpty ||
        json['schemaVersion'] != currentSchemaVersion ||
        json['accountScopeId'] != expectedAccountScopeId) {
      throw const FormatException('notification_settings_invalid');
    }
    T enumValue<T extends Enum>(List<T> values, Object? raw) =>
        values.where((item) => item.name == raw).single;
    final quiet = json['quietHours'];
    final value = NotificationSettings(
      accountScopeId: expectedAccountScopeId,
      enabled: json['enabled'] as bool,
      permissionPromptExplained: json['permissionPromptExplained'] as bool,
      privacyMode:
          enumValue(NotificationPrivacyMode.values, json['privacyMode']),
      soundEnabled: json['soundEnabled'] as bool,
      vibrationEnabled: json['vibrationEnabled'] as bool,
      badgeEnabled: json['badgeEnabled'] as bool,
      quietHours: quiet == null
          ? null
          : NotificationQuietHours.fromJson(
              Map<String, Object?>.from(quiet as Map),
            ),
      timezoneId: json['timezoneId'] as String,
      changedAt: DateTime.parse(json['changedAt'] as String).toUtc(),
      source: enumValue(NotificationSettingsSource.values, json['source']),
      policyRevision: json['policyRevision'] as int,
    );
    value.validate();
    return value;
  }

  final int schemaVersion;
  final String accountScopeId;
  final bool enabled;
  final bool permissionPromptExplained;
  final NotificationPrivacyMode privacyMode;
  final bool soundEnabled;
  final bool vibrationEnabled;
  final bool badgeEnabled;
  final NotificationQuietHours? quietHours;
  final String timezoneId;
  final DateTime changedAt;
  final NotificationSettingsSource source;
  final int policyRevision;

  void validate() {
    if (schemaVersion != currentSchemaVersion ||
        accountScopeId.trim().isEmpty ||
        accountScopeId.length > 200 ||
        timezoneId.trim().isEmpty ||
        timezoneId.length > 100 ||
        policyRevision < 0) {
      throw const FormatException('notification_settings_invalid');
    }
  }

  NotificationSettings copyWith({
    bool? enabled,
    bool? permissionPromptExplained,
    NotificationPrivacyMode? privacyMode,
    bool? soundEnabled,
    bool? vibrationEnabled,
    bool? badgeEnabled,
    String? timezoneId,
    DateTime? changedAt,
    NotificationSettingsSource? source,
    int? policyRevision,
  }) =>
      NotificationSettings(
        accountScopeId: accountScopeId,
        enabled: enabled ?? this.enabled,
        permissionPromptExplained:
            permissionPromptExplained ?? this.permissionPromptExplained,
        privacyMode: privacyMode ?? this.privacyMode,
        soundEnabled: soundEnabled ?? this.soundEnabled,
        vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
        badgeEnabled: badgeEnabled ?? this.badgeEnabled,
        quietHours: quietHours,
        timezoneId: timezoneId ?? this.timezoneId,
        changedAt: changedAt ?? this.changedAt,
        source: source ?? this.source,
        policyRevision: policyRevision ?? this.policyRevision,
      );

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'accountScopeId': accountScopeId,
        'enabled': enabled,
        'permissionPromptExplained': permissionPromptExplained,
        'privacyMode': privacyMode.name,
        'soundEnabled': soundEnabled,
        'vibrationEnabled': vibrationEnabled,
        'badgeEnabled': badgeEnabled,
        'quietHours': quietHours?.toJson(),
        'timezoneId': timezoneId,
        'changedAt': changedAt.toUtc().toIso8601String(),
        'source': source.name,
        'policyRevision': policyRevision,
      };
}

enum LocalNotificationCategory {
  test,
  explicitReminder,
  pendingActionAttention,
  systemInformation,
  forgottenItemDetection,
  conflictDetection,
  delayDetection,
  deadlineDetection,
  dailySummary,
  criticalAlert,
  thirdPartyUpdate,
}

extension LocalNotificationCategoryPolicy on LocalNotificationCategory {
  bool get isAvailableInN1 => switch (this) {
        LocalNotificationCategory.test ||
        LocalNotificationCategory.explicitReminder ||
        LocalNotificationCategory.pendingActionAttention ||
        LocalNotificationCategory.systemInformation =>
          true,
        _ => false,
      };

  bool get isAvailableInN2 =>
      isAvailableInN1 ||
      switch (this) {
        LocalNotificationCategory.forgottenItemDetection ||
        LocalNotificationCategory.conflictDetection ||
        LocalNotificationCategory.delayDetection ||
        LocalNotificationCategory.deadlineDetection =>
          true,
        _ => false,
      };

  bool get isAvailableInN3 =>
      isAvailableInN2 || this == LocalNotificationCategory.dailySummary;
}

enum NotificationPrivacyLevel { generic, hidden }

enum NotificationInteractionType { openOnly, openSafeDestination }

enum NotificationDestinationType {
  home,
  actionHistory,
  notificationsSettings,
  dailySummary,
}

enum LocalNotificationSource {
  explicitUserRequest,
  explicitTest,
  completedDomainAction,
  deterministicDetection,
  proactivePolicy,
  dailySummary,
}

enum LocalNotificationStatus {
  registered,
  scheduled,
  delivered,
  cancelled,
  expired,
  failed,
}

enum NotificationScheduleMeaning { absoluteInstant, localWallClock }

final class LocalNotificationRequest {
  static const currentSchemaVersion = 1;

  const LocalNotificationRequest({
    this.schemaVersion = currentSchemaVersion,
    required this.logicalNotificationId,
    required this.accountScopeId,
    required this.category,
    required this.createdAt,
    required this.scheduledAt,
    this.expiresAt,
    required this.timezoneId,
    required this.scheduleMeaning,
    required this.privacyLevel,
    required this.interactionType,
    required this.destinationType,
    required this.destinationReference,
    this.replacementKey,
    required this.source,
    required this.status,
    required this.platformNotificationId,
    required this.correlationId,
    required this.policyVersionObserved,
  });

  factory LocalNotificationRequest.fromJson(
    Map<String, Object?> json, {
    required String expectedAccountScopeId,
  }) {
    const keys = {
      'schemaVersion',
      'logicalNotificationId',
      'accountScopeId',
      'category',
      'createdAt',
      'scheduledAt',
      'expiresAt',
      'timezoneId',
      'scheduleMeaning',
      'privacyLevel',
      'interactionType',
      'destinationType',
      'destinationReference',
      'replacementKey',
      'source',
      'status',
      'platformNotificationId',
      'correlationId',
      'policyVersionObserved',
    };
    if (json.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(json.keys.toSet()).isNotEmpty ||
        json['schemaVersion'] != currentSchemaVersion) {
      throw const FormatException('local_notification_request_invalid');
    }
    T enumValue<T extends Enum>(List<T> values, Object? raw) =>
        values.where((item) => item.name == raw).single;
    final value = LocalNotificationRequest(
      schemaVersion: json['schemaVersion'] as int,
      logicalNotificationId: json['logicalNotificationId'] as String,
      accountScopeId: json['accountScopeId'] as String,
      category: enumValue(LocalNotificationCategory.values, json['category']),
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      scheduledAt: DateTime.parse(json['scheduledAt'] as String).toUtc(),
      expiresAt: json['expiresAt'] == null
          ? null
          : DateTime.parse(json['expiresAt'] as String).toUtc(),
      timezoneId: json['timezoneId'] as String,
      scheduleMeaning: enumValue(
        NotificationScheduleMeaning.values,
        json['scheduleMeaning'],
      ),
      privacyLevel:
          enumValue(NotificationPrivacyLevel.values, json['privacyLevel']),
      interactionType: enumValue(
        NotificationInteractionType.values,
        json['interactionType'],
      ),
      destinationType: enumValue(
        NotificationDestinationType.values,
        json['destinationType'],
      ),
      destinationReference: json['destinationReference'] as String,
      replacementKey: json['replacementKey'] as String?,
      source: enumValue(LocalNotificationSource.values, json['source']),
      status: enumValue(LocalNotificationStatus.values, json['status']),
      platformNotificationId: json['platformNotificationId'] as int,
      correlationId: json['correlationId'] as String,
      policyVersionObserved: json['policyVersionObserved'] as int,
    );
    if (value.accountScopeId != expectedAccountScopeId) {
      throw const FormatException('notification_account_mismatch');
    }
    value.validate();
    return value;
  }

  final int schemaVersion;
  final String logicalNotificationId;
  final String accountScopeId;
  final LocalNotificationCategory category;
  final DateTime createdAt;
  final DateTime scheduledAt;
  final DateTime? expiresAt;
  final String timezoneId;
  final NotificationScheduleMeaning scheduleMeaning;
  final NotificationPrivacyLevel privacyLevel;
  final NotificationInteractionType interactionType;
  final NotificationDestinationType destinationType;
  final String destinationReference;
  final String? replacementKey;
  final LocalNotificationSource source;
  final LocalNotificationStatus status;
  final int platformNotificationId;
  final String correlationId;
  final int policyVersionObserved;

  void validate() {
    if (schemaVersion != currentSchemaVersion ||
        logicalNotificationId.trim().isEmpty ||
        logicalNotificationId.length > 160 ||
        accountScopeId.trim().isEmpty ||
        !category.isAvailableInN3 ||
        timezoneId.trim().isEmpty ||
        destinationReference.trim().isEmpty ||
        destinationReference.length > 160 ||
        platformNotificationId <= 0 ||
        correlationId.trim().isEmpty ||
        policyVersionObserved < 0 ||
        (expiresAt != null &&
            (!expiresAt!.isAfter(createdAt) ||
                scheduledAt.isAfter(expiresAt!)))) {
      throw const FormatException('local_notification_request_invalid');
    }
  }

  String get structuralReceipt => [
        schemaVersion,
        logicalNotificationId,
        category.name,
        scheduledAt.toUtc().toIso8601String(),
        expiresAt?.toUtc().toIso8601String() ?? '-',
        timezoneId,
        scheduleMeaning.name,
        privacyLevel.name,
        interactionType.name,
        destinationType.name,
        destinationReference,
        replacementKey ?? '-',
        source.name,
        policyVersionObserved,
      ].join('|');

  LocalNotificationRequest withStatus(LocalNotificationStatus value) =>
      LocalNotificationRequest(
        logicalNotificationId: logicalNotificationId,
        accountScopeId: accountScopeId,
        category: category,
        createdAt: createdAt,
        scheduledAt: scheduledAt,
        expiresAt: expiresAt,
        timezoneId: timezoneId,
        scheduleMeaning: scheduleMeaning,
        privacyLevel: privacyLevel,
        interactionType: interactionType,
        destinationType: destinationType,
        destinationReference: destinationReference,
        replacementKey: replacementKey,
        source: source,
        status: value,
        platformNotificationId: platformNotificationId,
        correlationId: correlationId,
        policyVersionObserved: policyVersionObserved,
      );

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'logicalNotificationId': logicalNotificationId,
        'accountScopeId': accountScopeId,
        'category': category.name,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'scheduledAt': scheduledAt.toUtc().toIso8601String(),
        'expiresAt': expiresAt?.toUtc().toIso8601String(),
        'timezoneId': timezoneId,
        'scheduleMeaning': scheduleMeaning.name,
        'privacyLevel': privacyLevel.name,
        'interactionType': interactionType.name,
        'destinationType': destinationType.name,
        'destinationReference': destinationReference,
        'replacementKey': replacementKey,
        'source': source.name,
        'status': status.name,
        'platformNotificationId': platformNotificationId,
        'correlationId': correlationId,
        'policyVersionObserved': policyVersionObserved,
      };
}

final class NotificationPrivacyPolicy {
  static const currentVersion = 1;
  const NotificationPrivacyPolicy();

  bool allows(NotificationPrivacyMode mode, NotificationPrivacyLevel level) =>
      mode != NotificationPrivacyMode.systemDefault ||
      level == NotificationPrivacyLevel.generic;
}

final class NotificationRegistryState {
  static const currentSchemaVersion = 1;
  static const maximumEntries = 128;

  NotificationRegistryState({
    this.schemaVersion = currentSchemaVersion,
    required this.accountScopeId,
    required Iterable<LocalNotificationRequest> entries,
  }) : _entries = List.unmodifiable(entries) {
    final logicalIds = _entries.map((entry) => entry.logicalNotificationId);
    final platformIds = _entries.map((entry) => entry.platformNotificationId);
    if (schemaVersion != currentSchemaVersion ||
        accountScopeId.trim().isEmpty ||
        _entries.length > maximumEntries ||
        _entries.any((entry) => entry.accountScopeId != accountScopeId) ||
        logicalIds.toSet().length != _entries.length ||
        platformIds.toSet().length != _entries.length) {
      throw const FormatException('notification_registry_invalid');
    }
  }

  final int schemaVersion;
  final String accountScopeId;
  final List<LocalNotificationRequest> _entries;

  UnmodifiableListView<LocalNotificationRequest> get entries =>
      UnmodifiableListView(_entries);
}
