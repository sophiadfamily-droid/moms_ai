import 'dart:collection';

import 'local_notification_models.dart';
import 'proactive_detection.dart';

bool _hasExactKeys(Map<String, Object?> json, Set<String> keys) =>
    json.length == keys.length && json.keys.toSet().containsAll(keys);

enum ProactiveAlertCategory {
  deadlineApproaching,
  deadlinePassed,
  objectivelyDelayed,
  structuredConflict,
  potentialOmission,
  explicitReminder,
  pendingActionAttention,
  systemInformation,
  dailySummary,
}

enum NotificationDeliveryMode {
  immediate,
  dailySummaryOnly,
  immediateAndSummary,
  disabled,
}

enum ProactivePolicyChangeSource {
  explicitUserSetting,
  restrictiveDefault,
  migrationLegacy,
}

enum ProactivePauseState {
  inactive,
  pausedUntil,
  pausedIndefinitely,
}

enum ProactivePauseReasonSource { explicitUserSetting }

enum NotificationRateLimitStrategy {
  includeInDailySummary,
  defer,
  suppressWithCooldown,
  keepHighestPriorityOnly,
}

enum DailySummaryWeekendBehavior { followSelectedDays, weekdaysOnly }

enum DailySummaryStatus {
  built,
  scheduled,
  cancelled,
  expired,
  noSummary,
}

enum ProactivePolicyWarning {
  migratedLegacy,
  partialCoverage,
  timezoneChanged,
  restrictiveFallback,
}

enum NotificationDeliveryDecisionType {
  deliverNow,
  schedule,
  includeInDailySummary,
  deferUntil,
  suppressDisabled,
  suppressPaused,
  suppressQuietHours,
  suppressRateLimit,
  suppressDuplicate,
  suppressInsufficientEvidence,
  suppressStale,
  suppressPermission,
  replaceExisting,
  cancelExisting,
  noAction,
}

enum NotificationDeliveryReason {
  eligibleImmediate,
  eligibleScheduled,
  summarySelected,
  policyDisabled,
  categoryDisabled,
  paused,
  quietHours,
  rateLimit,
  duplicate,
  insufficientEvidence,
  staleCoverage,
  permissionMissing,
  settingsDisabled,
  incidentReplaced,
  signalResolved,
  summaryEmpty,
  expired,
}

final class AlertCategorySettings {
  const AlertCategorySettings({
    required this.enabled,
    required this.deliveryMode,
    required this.includeInDailySummary,
    required this.allowImmediateDelivery,
    required this.allowDuringQuietHours,
    required this.criticalEligibility,
    required this.cooldown,
    required this.dailyMaximum,
    required this.priority,
    required this.minimumConfidence,
    required this.minimumEvidenceLevel,
  });

  factory AlertCategorySettings.restrictive() => const AlertCategorySettings(
        enabled: false,
        deliveryMode: NotificationDeliveryMode.disabled,
        includeInDailySummary: false,
        allowImmediateDelivery: false,
        allowDuringQuietHours: false,
        criticalEligibility: false,
        cooldown: Duration(hours: 12),
        dailyMaximum: 1,
        priority: 0,
        minimumConfidence: DetectionConfidenceLevel.certain,
        minimumEvidenceLevel: DetectionEvidenceLevel.confirmedStructured,
      );

  final bool enabled;
  final NotificationDeliveryMode deliveryMode;
  final bool includeInDailySummary;
  final bool allowImmediateDelivery;
  final bool allowDuringQuietHours;
  final bool criticalEligibility;
  final Duration cooldown;
  final int dailyMaximum;
  final int priority;
  final DetectionConfidenceLevel minimumConfidence;
  final DetectionEvidenceLevel minimumEvidenceLevel;

  void validate() {
    if (cooldown < Duration.zero ||
        cooldown > const Duration(days: 30) ||
        dailyMaximum < 0 ||
        dailyMaximum > 20 ||
        priority < 0 ||
        priority > 100 ||
        (!enabled && deliveryMode != NotificationDeliveryMode.disabled) ||
        (deliveryMode == NotificationDeliveryMode.disabled &&
            allowImmediateDelivery)) {
      throw const FormatException('alert_category_settings_invalid');
    }
  }

  AlertCategorySettings copyWith({
    bool? enabled,
    NotificationDeliveryMode? deliveryMode,
    bool? includeInDailySummary,
    bool? allowImmediateDelivery,
    bool? allowDuringQuietHours,
    bool? criticalEligibility,
    Duration? cooldown,
    int? dailyMaximum,
    int? priority,
  }) =>
      AlertCategorySettings(
        enabled: enabled ?? this.enabled,
        deliveryMode: deliveryMode ?? this.deliveryMode,
        includeInDailySummary:
            includeInDailySummary ?? this.includeInDailySummary,
        allowImmediateDelivery:
            allowImmediateDelivery ?? this.allowImmediateDelivery,
        allowDuringQuietHours:
            allowDuringQuietHours ?? this.allowDuringQuietHours,
        criticalEligibility: criticalEligibility ?? this.criticalEligibility,
        cooldown: cooldown ?? this.cooldown,
        dailyMaximum: dailyMaximum ?? this.dailyMaximum,
        priority: priority ?? this.priority,
        minimumConfidence: minimumConfidence,
        minimumEvidenceLevel: minimumEvidenceLevel,
      );

  factory AlertCategorySettings.fromJson(Map<String, Object?> json) {
    const keys = {
      'enabled',
      'deliveryMode',
      'includeInDailySummary',
      'allowImmediateDelivery',
      'allowDuringQuietHours',
      'criticalEligibility',
      'cooldownMinutes',
      'dailyMaximum',
      'priority',
      'minimumConfidence',
      'minimumEvidenceLevel',
    };
    if (!_hasExactKeys(json, keys)) {
      throw const FormatException('alert_category_settings_invalid');
    }
    T parse<T extends Enum>(List<T> values, Object? raw) =>
        values.where((item) => item.name == raw).single;
    final value = AlertCategorySettings(
      enabled: json['enabled'] as bool,
      deliveryMode:
          parse(NotificationDeliveryMode.values, json['deliveryMode']),
      includeInDailySummary: json['includeInDailySummary'] as bool,
      allowImmediateDelivery: json['allowImmediateDelivery'] as bool,
      allowDuringQuietHours: json['allowDuringQuietHours'] as bool,
      criticalEligibility: json['criticalEligibility'] as bool,
      cooldown: Duration(minutes: json['cooldownMinutes'] as int),
      dailyMaximum: json['dailyMaximum'] as int,
      priority: json['priority'] as int,
      minimumConfidence: parse(
        DetectionConfidenceLevel.values,
        json['minimumConfidence'],
      ),
      minimumEvidenceLevel: parse(
        DetectionEvidenceLevel.values,
        json['minimumEvidenceLevel'],
      ),
    );
    value.validate();
    return value;
  }

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'deliveryMode': deliveryMode.name,
        'includeInDailySummary': includeInDailySummary,
        'allowImmediateDelivery': allowImmediateDelivery,
        'allowDuringQuietHours': allowDuringQuietHours,
        'criticalEligibility': criticalEligibility,
        'cooldownMinutes': cooldown.inMinutes,
        'dailyMaximum': dailyMaximum,
        'priority': priority,
        'minimumConfidence': minimumConfidence.name,
        'minimumEvidenceLevel': minimumEvidenceLevel.name,
      };
}

final class DailySummarySettings {
  DailySummarySettings({
    required this.enabled,
    required this.localMinute,
    required this.timezoneId,
    Set<int> weekdays = const {1, 2, 3, 4, 5},
    required this.weekendBehavior,
    required this.deferAfterQuietHours,
    Set<ProactiveAlertCategory> includedCategories = const {},
  })  : weekdays = UnmodifiableSetView(Set<int>.of(weekdays)),
        includedCategories = UnmodifiableSetView(Set<ProactiveAlertCategory>.of(
          includedCategories,
        )) {
    validate();
  }

  factory DailySummarySettings.restrictive(String timezoneId) =>
      DailySummarySettings(
        enabled: false,
        localMinute: 8 * 60,
        timezoneId: timezoneId,
        weekendBehavior: DailySummaryWeekendBehavior.followSelectedDays,
        deferAfterQuietHours: true,
      );

  final bool enabled;
  final int localMinute;
  final String timezoneId;
  final Set<int> weekdays;
  final DailySummaryWeekendBehavior weekendBehavior;
  final bool deferAfterQuietHours;
  final Set<ProactiveAlertCategory> includedCategories;

  void validate() {
    if (localMinute < 0 ||
        localMinute > 1439 ||
        timezoneId.trim().isEmpty ||
        timezoneId.length > 100 ||
        weekdays.isEmpty ||
        weekdays.any((day) => day < 1 || day > 7) ||
        includedCategories.length > ProactiveAlertCategory.values.length) {
      throw const FormatException('daily_summary_settings_invalid');
    }
  }

  DailySummarySettings copyWith({
    bool? enabled,
    int? localMinute,
    String? timezoneId,
    Set<int>? weekdays,
    DailySummaryWeekendBehavior? weekendBehavior,
    bool? deferAfterQuietHours,
    Set<ProactiveAlertCategory>? includedCategories,
  }) =>
      DailySummarySettings(
        enabled: enabled ?? this.enabled,
        localMinute: localMinute ?? this.localMinute,
        timezoneId: timezoneId ?? this.timezoneId,
        weekdays: weekdays ?? this.weekdays,
        weekendBehavior: weekendBehavior ?? this.weekendBehavior,
        deferAfterQuietHours: deferAfterQuietHours ?? this.deferAfterQuietHours,
        includedCategories: includedCategories ?? this.includedCategories,
      );

  factory DailySummarySettings.fromJson(Map<String, Object?> json) {
    const keys = {
      'enabled',
      'localMinute',
      'timezoneId',
      'weekdays',
      'weekendBehavior',
      'deferAfterQuietHours',
      'includedCategories',
    };
    if (!_hasExactKeys(json, keys)) {
      throw const FormatException('daily_summary_settings_invalid');
    }
    final value = DailySummarySettings(
      enabled: json['enabled'] as bool,
      localMinute: json['localMinute'] as int,
      timezoneId: json['timezoneId'] as String,
      weekdays: (json['weekdays'] as List).cast<int>().toSet(),
      weekendBehavior: DailySummaryWeekendBehavior.values
          .where((item) => item.name == json['weekendBehavior'])
          .single,
      deferAfterQuietHours: json['deferAfterQuietHours'] as bool,
      includedCategories: (json['includedCategories'] as List)
          .map(
            (raw) => ProactiveAlertCategory.values
                .where((item) => item.name == raw)
                .single,
          )
          .toSet(),
    );
    return value;
  }

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'localMinute': localMinute,
        'timezoneId': timezoneId,
        'weekdays': weekdays.toList()..sort(),
        'weekendBehavior': weekendBehavior.name,
        'deferAfterQuietHours': deferAfterQuietHours,
        'includedCategories':
            includedCategories.map((item) => item.name).toList()..sort(),
      };
}

final class ProactiveNotificationPause {
  const ProactiveNotificationPause({
    required this.state,
    this.startedAt,
    this.resumesAt,
    required this.reasonSource,
    required this.createdByUser,
    required this.policyRevision,
    required this.affectedCategories,
  });

  factory ProactiveNotificationPause.inactive() =>
      const ProactiveNotificationPause(
        state: ProactivePauseState.inactive,
        reasonSource: ProactivePauseReasonSource.explicitUserSetting,
        createdByUser: false,
        policyRevision: 0,
        affectedCategories: {},
      );

  final ProactivePauseState state;
  final DateTime? startedAt;
  final DateTime? resumesAt;
  final ProactivePauseReasonSource reasonSource;
  final bool createdByUser;
  final int policyRevision;
  final Set<ProactiveAlertCategory> affectedCategories;

  bool isActiveAt(DateTime instant, ProactiveAlertCategory category) {
    if (!affectedCategories.contains(category)) return false;
    return switch (state) {
      ProactivePauseState.inactive => false,
      ProactivePauseState.pausedIndefinitely => true,
      ProactivePauseState.pausedUntil =>
        resumesAt != null && instant.toUtc().isBefore(resumesAt!.toUtc()),
    };
  }

  void validate() {
    if (policyRevision < 0 ||
        affectedCategories.length > ProactiveAlertCategory.values.length ||
        (state != ProactivePauseState.inactive &&
            (!createdByUser || startedAt == null)) ||
        (state == ProactivePauseState.pausedUntil &&
            (resumesAt == null || !resumesAt!.isAfter(startedAt!))) ||
        (state != ProactivePauseState.pausedUntil && resumesAt != null)) {
      throw const FormatException('proactive_pause_invalid');
    }
  }

  factory ProactiveNotificationPause.fromJson(Map<String, Object?> json) {
    const keys = {
      'state',
      'startedAt',
      'resumesAt',
      'reasonSource',
      'createdByUser',
      'policyRevision',
      'affectedCategories',
    };
    if (!_hasExactKeys(json, keys)) {
      throw const FormatException('proactive_pause_invalid');
    }
    final value = ProactiveNotificationPause(
      state: ProactivePauseState.values
          .where((item) => item.name == json['state'])
          .single,
      startedAt: json['startedAt'] == null
          ? null
          : DateTime.parse(json['startedAt'] as String).toUtc(),
      resumesAt: json['resumesAt'] == null
          ? null
          : DateTime.parse(json['resumesAt'] as String).toUtc(),
      reasonSource: ProactivePauseReasonSource.values
          .where((item) => item.name == json['reasonSource'])
          .single,
      createdByUser: json['createdByUser'] as bool,
      policyRevision: json['policyRevision'] as int,
      affectedCategories: (json['affectedCategories'] as List)
          .map(
            (raw) => ProactiveAlertCategory.values
                .where((item) => item.name == raw)
                .single,
          )
          .toSet(),
    );
    value.validate();
    return value;
  }

  Map<String, Object?> toJson() => {
        'state': state.name,
        'startedAt': startedAt?.toUtc().toIso8601String(),
        'resumesAt': resumesAt?.toUtc().toIso8601String(),
        'reasonSource': reasonSource.name,
        'createdByUser': createdByUser,
        'policyRevision': policyRevision,
        'affectedCategories':
            affectedCategories.map((item) => item.name).toList()..sort(),
      };
}

final class CriticalProductAlertPolicy {
  const CriticalProductAlertPolicy({
    required this.enabled,
    required this.allowDuringQuietHours,
    required this.allowDuringTemporaryPause,
    required this.maximumPerDay,
    required this.horizon,
  });

  factory CriticalProductAlertPolicy.restrictive() =>
      const CriticalProductAlertPolicy(
        enabled: false,
        allowDuringQuietHours: false,
        allowDuringTemporaryPause: false,
        maximumPerDay: 1,
        horizon: Duration(hours: 6),
      );

  final bool enabled;
  final bool allowDuringQuietHours;
  final bool allowDuringTemporaryPause;
  final int maximumPerDay;
  final Duration horizon;

  void validate() {
    if (maximumPerDay < 0 ||
        maximumPerDay > 5 ||
        horizon <= Duration.zero ||
        horizon > const Duration(days: 2)) {
      throw const FormatException('critical_product_alert_policy_invalid');
    }
  }

  factory CriticalProductAlertPolicy.fromJson(Map<String, Object?> json) {
    const keys = {
      'enabled',
      'allowDuringQuietHours',
      'allowDuringTemporaryPause',
      'maximumPerDay',
      'horizonMinutes',
    };
    if (!_hasExactKeys(json, keys)) {
      throw const FormatException('critical_product_alert_policy_invalid');
    }
    final value = CriticalProductAlertPolicy(
      enabled: json['enabled'] as bool,
      allowDuringQuietHours: json['allowDuringQuietHours'] as bool,
      allowDuringTemporaryPause: json['allowDuringTemporaryPause'] as bool,
      maximumPerDay: json['maximumPerDay'] as int,
      horizon: Duration(minutes: json['horizonMinutes'] as int),
    );
    value.validate();
    return value;
  }

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'allowDuringQuietHours': allowDuringQuietHours,
        'allowDuringTemporaryPause': allowDuringTemporaryPause,
        'maximumPerDay': maximumPerDay,
        'horizonMinutes': horizon.inMinutes,
      };
}

final class NotificationRateLimitPolicy {
  const NotificationRateLimitPolicy({
    required this.maximumTotalPerDay,
    required this.maximumImmediatePerWindow,
    required this.window,
    required this.minimumSpacing,
    required this.maximumReplacements,
    required this.maximumDeferrals,
    required this.maximumActive,
    required this.maximumSummaryItems,
    required this.maximumCriticalItems,
    required this.afterLimit,
  });

  factory NotificationRateLimitPolicy.restrictive() =>
      const NotificationRateLimitPolicy(
        maximumTotalPerDay: 4,
        maximumImmediatePerWindow: 1,
        window: Duration(hours: 1),
        minimumSpacing: Duration(minutes: 30),
        maximumReplacements: 2,
        maximumDeferrals: 1,
        maximumActive: 8,
        maximumSummaryItems: 8,
        maximumCriticalItems: 1,
        afterLimit: NotificationRateLimitStrategy.includeInDailySummary,
      );

  final int maximumTotalPerDay;
  final int maximumImmediatePerWindow;
  final Duration window;
  final Duration minimumSpacing;
  final int maximumReplacements;
  final int maximumDeferrals;
  final int maximumActive;
  final int maximumSummaryItems;
  final int maximumCriticalItems;
  final NotificationRateLimitStrategy afterLimit;

  void validate() {
    if (maximumTotalPerDay < 1 ||
        maximumTotalPerDay > 20 ||
        maximumImmediatePerWindow < 1 ||
        maximumImmediatePerWindow > maximumTotalPerDay ||
        window <= Duration.zero ||
        window > const Duration(days: 1) ||
        minimumSpacing < Duration.zero ||
        maximumReplacements < 0 ||
        maximumReplacements > 10 ||
        maximumDeferrals < 0 ||
        maximumDeferrals > 3 ||
        maximumActive < 1 ||
        maximumActive > 64 ||
        maximumSummaryItems < 1 ||
        maximumSummaryItems > 20 ||
        maximumCriticalItems < 0 ||
        maximumCriticalItems > 5) {
      throw const FormatException('notification_rate_limit_invalid');
    }
  }

  factory NotificationRateLimitPolicy.fromJson(Map<String, Object?> json) {
    const keys = {
      'maximumTotalPerDay',
      'maximumImmediatePerWindow',
      'windowMinutes',
      'minimumSpacingMinutes',
      'maximumReplacements',
      'maximumDeferrals',
      'maximumActive',
      'maximumSummaryItems',
      'maximumCriticalItems',
      'afterLimit',
    };
    if (!_hasExactKeys(json, keys)) {
      throw const FormatException('notification_rate_limit_invalid');
    }
    final value = NotificationRateLimitPolicy(
      maximumTotalPerDay: json['maximumTotalPerDay'] as int,
      maximumImmediatePerWindow: json['maximumImmediatePerWindow'] as int,
      window: Duration(minutes: json['windowMinutes'] as int),
      minimumSpacing: Duration(minutes: json['minimumSpacingMinutes'] as int),
      maximumReplacements: json['maximumReplacements'] as int,
      maximumDeferrals: json['maximumDeferrals'] as int,
      maximumActive: json['maximumActive'] as int,
      maximumSummaryItems: json['maximumSummaryItems'] as int,
      maximumCriticalItems: json['maximumCriticalItems'] as int,
      afterLimit: NotificationRateLimitStrategy.values
          .where((item) => item.name == json['afterLimit'])
          .single,
    );
    value.validate();
    return value;
  }

  Map<String, Object?> toJson() => {
        'maximumTotalPerDay': maximumTotalPerDay,
        'maximumImmediatePerWindow': maximumImmediatePerWindow,
        'windowMinutes': window.inMinutes,
        'minimumSpacingMinutes': minimumSpacing.inMinutes,
        'maximumReplacements': maximumReplacements,
        'maximumDeferrals': maximumDeferrals,
        'maximumActive': maximumActive,
        'maximumSummaryItems': maximumSummaryItems,
        'maximumCriticalItems': maximumCriticalItems,
        'afterLimit': afterLimit.name,
      };
}

final class ProactiveNotificationPolicy {
  static const currentSchemaVersion = 1;

  ProactiveNotificationPolicy({
    this.schemaVersion = currentSchemaVersion,
    required this.enabled,
    required Map<ProactiveAlertCategory, AlertCategorySettings>
        categorySettings,
    required this.dailySummarySettings,
    this.quietHours,
    required this.pause,
    required this.criticalProductAlertPolicy,
    required this.rateLimitPolicy,
    required this.timezoneId,
    required this.changedAt,
    required this.changeSource,
    required this.accountScopeId,
    required this.policyRevision,
    required this.notificationPrivacyMode,
    Set<ProactivePolicyWarning> warningCodes = const {},
  })  : categorySettings = UnmodifiableMapView(
          Map<ProactiveAlertCategory, AlertCategorySettings>.of(
            categorySettings,
          ),
        ),
        warningCodes = UnmodifiableSetView(warningCodes) {
    validate();
  }

  factory ProactiveNotificationPolicy.restrictiveDefault({
    required String accountScopeId,
    required String timezoneId,
    required DateTime changedAt,
  }) =>
      ProactiveNotificationPolicy(
        enabled: false,
        categorySettings: {
          for (final category in ProactiveAlertCategory.values)
            category: AlertCategorySettings(
              enabled: false,
              deliveryMode: NotificationDeliveryMode.disabled,
              includeInDailySummary:
                  category != ProactiveAlertCategory.explicitReminder &&
                      category != ProactiveAlertCategory.dailySummary,
              allowImmediateDelivery: false,
              allowDuringQuietHours: false,
              criticalEligibility: {
                ProactiveAlertCategory.deadlineApproaching,
                ProactiveAlertCategory.deadlinePassed,
                ProactiveAlertCategory.objectivelyDelayed,
                ProactiveAlertCategory.structuredConflict,
              }.contains(category),
              cooldown: const Duration(hours: 12),
              dailyMaximum:
                  category == ProactiveAlertCategory.potentialOmission ? 1 : 2,
              priority: switch (category) {
                ProactiveAlertCategory.structuredConflict => 90,
                ProactiveAlertCategory.deadlinePassed => 80,
                ProactiveAlertCategory.objectivelyDelayed => 70,
                ProactiveAlertCategory.deadlineApproaching => 60,
                ProactiveAlertCategory.potentialOmission => 40,
                _ => 30,
              },
              minimumConfidence: DetectionConfidenceLevel.strong,
              minimumEvidenceLevel: DetectionEvidenceLevel.explicit,
            ),
        },
        dailySummarySettings: DailySummarySettings.restrictive(timezoneId),
        pause: ProactiveNotificationPause.inactive(),
        criticalProductAlertPolicy: CriticalProductAlertPolicy.restrictive(),
        rateLimitPolicy: NotificationRateLimitPolicy.restrictive(),
        timezoneId: timezoneId,
        changedAt: changedAt.toUtc(),
        changeSource: ProactivePolicyChangeSource.restrictiveDefault,
        accountScopeId: accountScopeId,
        policyRevision: 0,
        notificationPrivacyMode: NotificationPrivacyMode.genericOnly,
        warningCodes: const {ProactivePolicyWarning.restrictiveFallback},
      );

  final int schemaVersion;
  final bool enabled;
  final Map<ProactiveAlertCategory, AlertCategorySettings> categorySettings;
  final DailySummarySettings dailySummarySettings;
  final NotificationQuietHours? quietHours;
  final ProactiveNotificationPause pause;
  final CriticalProductAlertPolicy criticalProductAlertPolicy;
  final NotificationRateLimitPolicy rateLimitPolicy;
  final String timezoneId;
  final DateTime changedAt;
  final ProactivePolicyChangeSource changeSource;
  final String accountScopeId;
  final int policyRevision;
  final NotificationPrivacyMode notificationPrivacyMode;
  final Set<ProactivePolicyWarning> warningCodes;

  void validate() {
    if (schemaVersion != currentSchemaVersion ||
        accountScopeId.trim().isEmpty ||
        accountScopeId.length > 200 ||
        timezoneId.trim().isEmpty ||
        timezoneId.length > 100 ||
        policyRevision < 0 ||
        categorySettings.length != ProactiveAlertCategory.values.length ||
        !categorySettings.keys
            .toSet()
            .containsAll(ProactiveAlertCategory.values) ||
        notificationPrivacyMode != NotificationPrivacyMode.genericOnly ||
        warningCodes.length > 8) {
      throw const FormatException('proactive_notification_policy_invalid');
    }
    for (final settings in categorySettings.values) {
      settings.validate();
    }
    dailySummarySettings.validate();
    pause.validate();
    criticalProductAlertPolicy.validate();
    rateLimitPolicy.validate();
  }

  ProactiveNotificationPolicy copyWith({
    bool? enabled,
    Map<ProactiveAlertCategory, AlertCategorySettings>? categorySettings,
    DailySummarySettings? dailySummarySettings,
    NotificationQuietHours? quietHours,
    bool clearQuietHours = false,
    ProactiveNotificationPause? pause,
    CriticalProductAlertPolicy? criticalProductAlertPolicy,
    NotificationRateLimitPolicy? rateLimitPolicy,
    String? timezoneId,
    DateTime? changedAt,
    ProactivePolicyChangeSource? changeSource,
    int? policyRevision,
    Set<ProactivePolicyWarning>? warningCodes,
  }) =>
      ProactiveNotificationPolicy(
        enabled: enabled ?? this.enabled,
        categorySettings: categorySettings ?? this.categorySettings,
        dailySummarySettings: dailySummarySettings ?? this.dailySummarySettings,
        quietHours: clearQuietHours ? null : quietHours ?? this.quietHours,
        pause: pause ?? this.pause,
        criticalProductAlertPolicy:
            criticalProductAlertPolicy ?? this.criticalProductAlertPolicy,
        rateLimitPolicy: rateLimitPolicy ?? this.rateLimitPolicy,
        timezoneId: timezoneId ?? this.timezoneId,
        changedAt: changedAt ?? this.changedAt,
        changeSource: changeSource ?? this.changeSource,
        accountScopeId: accountScopeId,
        policyRevision: policyRevision ?? this.policyRevision,
        notificationPrivacyMode: notificationPrivacyMode,
        warningCodes: warningCodes ?? this.warningCodes,
      );

  factory ProactiveNotificationPolicy.fromJson(
    Map<String, Object?> json, {
    required String expectedAccountScopeId,
  }) {
    const keys = {
      'schemaVersion',
      'enabled',
      'categorySettings',
      'dailySummarySettings',
      'quietHours',
      'pause',
      'criticalProductAlertPolicy',
      'rateLimitPolicy',
      'timezoneId',
      'changedAt',
      'changeSource',
      'accountScopeId',
      'policyRevision',
      'notificationPrivacyMode',
      'warningCodes',
    };
    if (!_hasExactKeys(json, keys) ||
        json['schemaVersion'] != currentSchemaVersion ||
        json['accountScopeId'] != expectedAccountScopeId) {
      throw const FormatException('proactive_notification_policy_invalid');
    }
    final rawCategories = Map<String, Object?>.from(
      json['categorySettings'] as Map,
    );
    final categories = <ProactiveAlertCategory, AlertCategorySettings>{};
    for (final category in ProactiveAlertCategory.values) {
      final raw = rawCategories.remove(category.name);
      if (raw is! Map) {
        throw const FormatException('proactive_notification_policy_invalid');
      }
      categories[category] =
          AlertCategorySettings.fromJson(Map<String, Object?>.from(raw));
    }
    if (rawCategories.isNotEmpty) {
      throw const FormatException('proactive_notification_policy_invalid');
    }
    return ProactiveNotificationPolicy(
      enabled: json['enabled'] as bool,
      categorySettings: categories,
      dailySummarySettings: DailySummarySettings.fromJson(
        Map<String, Object?>.from(json['dailySummarySettings'] as Map),
      ),
      quietHours: json['quietHours'] == null
          ? null
          : NotificationQuietHours.fromJson(
              Map<String, Object?>.from(json['quietHours'] as Map),
            ),
      pause: ProactiveNotificationPause.fromJson(
        Map<String, Object?>.from(json['pause'] as Map),
      ),
      criticalProductAlertPolicy: CriticalProductAlertPolicy.fromJson(
        Map<String, Object?>.from(
          json['criticalProductAlertPolicy'] as Map,
        ),
      ),
      rateLimitPolicy: NotificationRateLimitPolicy.fromJson(
        Map<String, Object?>.from(json['rateLimitPolicy'] as Map),
      ),
      timezoneId: json['timezoneId'] as String,
      changedAt: DateTime.parse(json['changedAt'] as String).toUtc(),
      changeSource: ProactivePolicyChangeSource.values
          .where((item) => item.name == json['changeSource'])
          .single,
      accountScopeId: expectedAccountScopeId,
      policyRevision: json['policyRevision'] as int,
      notificationPrivacyMode: NotificationPrivacyMode.values
          .where((item) => item.name == json['notificationPrivacyMode'])
          .single,
      warningCodes: (json['warningCodes'] as List)
          .map(
            (raw) => ProactivePolicyWarning.values
                .where((item) => item.name == raw)
                .single,
          )
          .toSet(),
    );
  }

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'enabled': enabled,
        'categorySettings': {
          for (final category in ProactiveAlertCategory.values)
            category.name: categorySettings[category]!.toJson(),
        },
        'dailySummarySettings': dailySummarySettings.toJson(),
        'quietHours': quietHours?.toJson(),
        'pause': pause.toJson(),
        'criticalProductAlertPolicy': criticalProductAlertPolicy.toJson(),
        'rateLimitPolicy': rateLimitPolicy.toJson(),
        'timezoneId': timezoneId,
        'changedAt': changedAt.toUtc().toIso8601String(),
        'changeSource': changeSource.name,
        'accountScopeId': accountScopeId,
        'policyRevision': policyRevision,
        'notificationPrivacyMode': notificationPrivacyMode.name,
        'warningCodes': warningCodes.map((item) => item.name).toList()..sort(),
      };
}

final class DailySummarySnapshot {
  static const currentSchemaVersion = 1;

  DailySummarySnapshot({
    this.schemaVersion = currentSchemaVersion,
    required this.summaryId,
    required this.accountScopeId,
    required this.localDate,
    required this.timezoneId,
    required this.generatedAt,
    required this.coverageState,
    required Map<String, int> sourceRevisions,
    required List<String> itemReferences,
    required Map<ProactiveAlertCategory, int> categoryCounts,
    required this.highestTechnicalSeverity,
    required this.omittedCount,
    required this.resolvedSinceLastSummaryCount,
    Set<ProactivePolicyWarning> warningCodes = const {},
    required this.expiresAt,
    required this.replacementKey,
    required this.status,
  })  : sourceRevisions =
            UnmodifiableMapView(Map<String, int>.of(sourceRevisions)),
        itemReferences = UnmodifiableListView(List<String>.of(itemReferences)),
        categoryCounts = UnmodifiableMapView(
          Map<ProactiveAlertCategory, int>.of(categoryCounts),
        ),
        warningCodes = UnmodifiableSetView(warningCodes) {
    if (schemaVersion != currentSchemaVersion ||
        summaryId.trim().isEmpty ||
        accountScopeId.trim().isEmpty ||
        timezoneId.trim().isEmpty ||
        itemReferences.length > 20 ||
        itemReferences.toSet().length != itemReferences.length ||
        sourceRevisions.length > 40 ||
        omittedCount < 0 ||
        resolvedSinceLastSummaryCount < 0 ||
        !expiresAt.isAfter(generatedAt) ||
        replacementKey.trim().isEmpty) {
      throw const FormatException('daily_summary_snapshot_invalid');
    }
  }

  final int schemaVersion;
  final String summaryId;
  final String accountScopeId;
  final String localDate;
  final String timezoneId;
  final DateTime generatedAt;
  final DetectionCoverageKind coverageState;
  final Map<String, int> sourceRevisions;
  final List<String> itemReferences;
  final Map<ProactiveAlertCategory, int> categoryCounts;
  final DetectionTechnicalSeverity highestTechnicalSeverity;
  final int omittedCount;
  final int resolvedSinceLastSummaryCount;
  final Set<ProactivePolicyWarning> warningCodes;
  final DateTime expiresAt;
  final String replacementKey;
  final DailySummaryStatus status;
}

final class NotificationDeliveryRecord {
  const NotificationDeliveryRecord({
    required this.incidentFingerprint,
    required this.category,
    required this.decidedAt,
    required this.decision,
    required this.replacementCount,
    required this.deferralCount,
    required this.critical,
  });

  final String incidentFingerprint;
  final ProactiveAlertCategory category;
  final DateTime decidedAt;
  final NotificationDeliveryDecisionType decision;
  final int replacementCount;
  final int deferralCount;
  final bool critical;
}

final class NotificationDeliveryDecision {
  const NotificationDeliveryDecision({
    required this.type,
    required this.reasonCode,
    required this.category,
    this.scheduledAt,
    required this.replacementKey,
    required this.policyRevision,
    required this.priority,
    required this.isCriticalProductAlert,
    required this.dailyCount,
    required this.windowCount,
    required this.revalidationRequired,
  });

  final NotificationDeliveryDecisionType type;
  final NotificationDeliveryReason reasonCode;
  final ProactiveAlertCategory category;
  final DateTime? scheduledAt;
  final String replacementKey;
  final int policyRevision;
  final int priority;
  final bool isCriticalProductAlert;
  final int dailyCount;
  final int windowCount;
  final bool revalidationRequired;
}
