import 'package:flutter/foundation.dart';

import '../models/local_notification_models.dart';
import '../models/proactive_notification_policy.dart';
import 'proactive_notification_policy_service.dart';

final class ProactiveNotificationSettingsController extends ChangeNotifier {
  ProactiveNotificationSettingsController({
    required this.service,
    this.onPolicyChanged,
  });

  final ProactiveNotificationPolicyService service;
  final Future<void> Function()? onPolicyChanged;

  ProactiveNotificationPolicy? policy;
  bool loading = false;
  bool saving = false;
  String? message;

  Future<void> load() async {
    loading = true;
    message = null;
    notifyListeners();
    policy = await service.load();
    loading = false;
    notifyListeners();
  }

  Future<void> setEnabled(bool enabled) =>
      _update((current, changedAt, timezone) => current.copyWith(
            enabled: enabled,
            timezoneId: timezone,
            changedAt: changedAt,
            changeSource: ProactivePolicyChangeSource.explicitUserSetting,
            policyRevision: current.policyRevision + 1,
          ));

  Future<void> setCategoryEnabled(
    ProactiveAlertCategory category,
    bool enabled,
  ) =>
      _update((current, changedAt, timezone) {
        final categories =
            Map<ProactiveAlertCategory, AlertCategorySettings>.of(
          current.categorySettings,
        );
        categories[category] = categories[category]!.copyWith(
          enabled: enabled,
          deliveryMode: enabled
              ? NotificationDeliveryMode.immediateAndSummary
              : NotificationDeliveryMode.disabled,
          allowImmediateDelivery: enabled,
          includeInDailySummary: enabled,
        );
        final included = Set<ProactiveAlertCategory>.of(
          current.dailySummarySettings.includedCategories,
        );
        if (enabled && categories[category]!.includeInDailySummary) {
          included.add(category);
        } else if (!enabled) {
          included.remove(category);
        }
        return current.copyWith(
          categorySettings: categories,
          dailySummarySettings: current.dailySummarySettings.copyWith(
            includedCategories: included,
          ),
          timezoneId: timezone,
          changedAt: changedAt,
          changeSource: ProactivePolicyChangeSource.explicitUserSetting,
          policyRevision: current.policyRevision + 1,
        );
      });

  Future<void> setDailySummaryEnabled(bool enabled) =>
      _update((current, changedAt, timezone) {
        final categories =
            Map<ProactiveAlertCategory, AlertCategorySettings>.of(
          current.categorySettings,
        );
        categories[ProactiveAlertCategory.dailySummary] =
            categories[ProactiveAlertCategory.dailySummary]!.copyWith(
          enabled: enabled,
          deliveryMode: enabled
              ? NotificationDeliveryMode.immediate
              : NotificationDeliveryMode.disabled,
          allowImmediateDelivery: enabled,
        );
        return current.copyWith(
          categorySettings: categories,
          dailySummarySettings: current.dailySummarySettings.copyWith(
            enabled: enabled,
            timezoneId: timezone,
            includedCategories: enabled
                ? current.categorySettings.entries
                    .where(
                      (entry) =>
                          entry.value.enabled &&
                          entry.value.includeInDailySummary,
                    )
                    .map((entry) => entry.key)
                    .toSet()
                : current.dailySummarySettings.includedCategories,
          ),
          timezoneId: timezone,
          changedAt: changedAt,
          changeSource: ProactivePolicyChangeSource.explicitUserSetting,
          policyRevision: current.policyRevision + 1,
        );
      });

  Future<void> setSummaryHour(int hour) =>
      _update((current, changedAt, timezone) => current.copyWith(
            dailySummarySettings: current.dailySummarySettings.copyWith(
              localMinute: hour * 60,
              timezoneId: timezone,
            ),
            timezoneId: timezone,
            changedAt: changedAt,
            changeSource: ProactivePolicyChangeSource.explicitUserSetting,
            policyRevision: current.policyRevision + 1,
          ));

  Future<void> toggleSummaryWeekday(int weekday, bool included) =>
      _update((current, changedAt, timezone) {
        final weekdays = Set<int>.of(current.dailySummarySettings.weekdays);
        if (included) {
          weekdays.add(weekday);
        } else if (weekdays.length > 1) {
          weekdays.remove(weekday);
        }
        return current.copyWith(
          dailySummarySettings: current.dailySummarySettings.copyWith(
            weekdays: weekdays,
            timezoneId: timezone,
          ),
          timezoneId: timezone,
          changedAt: changedAt,
          changeSource: ProactivePolicyChangeSource.explicitUserSetting,
          policyRevision: current.policyRevision + 1,
        );
      });

  Future<void> setCategorySummaryInclusion(
    ProactiveAlertCategory category,
    bool included,
  ) =>
      _update((current, changedAt, timezone) {
        final categories = Set<ProactiveAlertCategory>.of(
          current.dailySummarySettings.includedCategories,
        );
        if (included) {
          categories.add(category);
        } else {
          categories.remove(category);
        }
        return current.copyWith(
          dailySummarySettings: current.dailySummarySettings.copyWith(
            includedCategories: categories,
            timezoneId: timezone,
          ),
          timezoneId: timezone,
          changedAt: changedAt,
          changeSource: ProactivePolicyChangeSource.explicitUserSetting,
          policyRevision: current.policyRevision + 1,
        );
      });

  Future<void> setQuietHoursEnabled(bool enabled) =>
      _update((current, changedAt, timezone) => current.copyWith(
            quietHours: enabled
                ? NotificationQuietHours(
                    startMinute: current.quietHours?.startMinute ?? 22 * 60,
                    endMinute: current.quietHours?.endMinute ?? 7 * 60,
                    timezoneId: timezone,
                    behavior: current.quietHours?.behavior ??
                        NotificationQuietHoursBehavior.deferUntilQuietHoursEnd,
                    changedAt: changedAt,
                  )
                : null,
            clearQuietHours: !enabled,
            timezoneId: timezone,
            changedAt: changedAt,
            changeSource: ProactivePolicyChangeSource.explicitUserSetting,
            policyRevision: current.policyRevision + 1,
          ));

  Future<void> setQuietHoursRange({
    int? startHour,
    int? endHour,
  }) =>
      _update((current, changedAt, timezone) {
        final quiet = current.quietHours;
        return current.copyWith(
          quietHours: NotificationQuietHours(
            startMinute:
                (startHour ?? (quiet?.startMinute ?? 22 * 60) ~/ 60) * 60,
            endMinute: (endHour ?? (quiet?.endMinute ?? 7 * 60) ~/ 60) * 60,
            timezoneId: timezone,
            weekdays: quiet?.weekdays ?? const {1, 2, 3, 4, 5, 6, 7},
            behavior: quiet?.behavior ??
                NotificationQuietHoursBehavior.deferUntilQuietHoursEnd,
            changedAt: changedAt,
          ),
          timezoneId: timezone,
          changedAt: changedAt,
          changeSource: ProactivePolicyChangeSource.explicitUserSetting,
          policyRevision: current.policyRevision + 1,
        );
      });

  Future<void> pauseFor(Duration duration) =>
      _update((current, changedAt, timezone) => current.copyWith(
            pause: ProactiveNotificationPause(
              state: ProactivePauseState.pausedUntil,
              startedAt: changedAt,
              resumesAt: changedAt.add(duration),
              reasonSource: ProactivePauseReasonSource.explicitUserSetting,
              createdByUser: true,
              policyRevision: current.policyRevision + 1,
              affectedCategories: _proactiveCategories,
            ),
            timezoneId: timezone,
            changedAt: changedAt,
            changeSource: ProactivePolicyChangeSource.explicitUserSetting,
            policyRevision: current.policyRevision + 1,
          ));

  Future<void> pauseIndefinitely() =>
      _update((current, changedAt, timezone) => current.copyWith(
            pause: ProactiveNotificationPause(
              state: ProactivePauseState.pausedIndefinitely,
              startedAt: changedAt,
              reasonSource: ProactivePauseReasonSource.explicitUserSetting,
              createdByUser: true,
              policyRevision: current.policyRevision + 1,
              affectedCategories: _proactiveCategories,
            ),
            timezoneId: timezone,
            changedAt: changedAt,
            changeSource: ProactivePolicyChangeSource.explicitUserSetting,
            policyRevision: current.policyRevision + 1,
          ));

  Future<void> resume() =>
      _update((current, changedAt, timezone) => current.copyWith(
            pause: ProactiveNotificationPause(
              state: ProactivePauseState.inactive,
              reasonSource: ProactivePauseReasonSource.explicitUserSetting,
              createdByUser: true,
              policyRevision: current.policyRevision + 1,
              affectedCategories: const {},
            ),
            timezoneId: timezone,
            changedAt: changedAt,
            changeSource: ProactivePolicyChangeSource.explicitUserSetting,
            policyRevision: current.policyRevision + 1,
          ));

  Future<void> setImportantAlerts(bool enabled) =>
      _update((current, changedAt, timezone) => current.copyWith(
            criticalProductAlertPolicy: CriticalProductAlertPolicy(
              enabled: enabled,
              allowDuringQuietHours: false,
              allowDuringTemporaryPause: false,
              maximumPerDay: current.criticalProductAlertPolicy.maximumPerDay,
              horizon: current.criticalProductAlertPolicy.horizon,
            ),
            timezoneId: timezone,
            changedAt: changedAt,
            changeSource: ProactivePolicyChangeSource.explicitUserSetting,
            policyRevision: current.policyRevision + 1,
          ));

  Future<void> setDailyMaximum(int maximum) =>
      _update((current, changedAt, timezone) {
        final rate = current.rateLimitPolicy;
        return current.copyWith(
          rateLimitPolicy: NotificationRateLimitPolicy(
            maximumTotalPerDay: maximum,
            maximumImmediatePerWindow:
                rate.maximumImmediatePerWindow.clamp(1, maximum),
            window: rate.window,
            minimumSpacing: rate.minimumSpacing,
            maximumReplacements: rate.maximumReplacements,
            maximumDeferrals: rate.maximumDeferrals,
            maximumActive: rate.maximumActive,
            maximumSummaryItems: rate.maximumSummaryItems,
            maximumCriticalItems: rate.maximumCriticalItems,
            afterLimit: rate.afterLimit,
          ),
          timezoneId: timezone,
          changedAt: changedAt,
          changeSource: ProactivePolicyChangeSource.explicitUserSetting,
          policyRevision: current.policyRevision + 1,
        );
      });

  Future<void> _update(
    ProactiveNotificationPolicy Function(
      ProactiveNotificationPolicy current,
      DateTime changedAt,
      String timezoneId,
    ) transform,
  ) async {
    saving = true;
    message = null;
    notifyListeners();
    try {
      policy = await service.update(transform);
      message = 'Réglages enregistrés.';
      try {
        await onPolicyChanged?.call();
      } on Object {
        // The setting is already durably saved. A later bounded lifecycle
        // evaluation will reconcile platform schedules.
      }
    } on Object {
      message = 'Les réglages n’ont pas pu être enregistrés.';
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  static const _proactiveCategories = {
    ProactiveAlertCategory.deadlineApproaching,
    ProactiveAlertCategory.deadlinePassed,
    ProactiveAlertCategory.objectivelyDelayed,
    ProactiveAlertCategory.structuredConflict,
    ProactiveAlertCategory.potentialOmission,
    ProactiveAlertCategory.pendingActionAttention,
    ProactiveAlertCategory.systemInformation,
    ProactiveAlertCategory.dailySummary,
  };
}
