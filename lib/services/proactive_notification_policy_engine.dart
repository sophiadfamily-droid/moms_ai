import 'package:timezone/timezone.dart' as tz;

import '../models/local_notification_models.dart';
import '../models/proactive_detection.dart';
import '../models/proactive_notification_policy.dart';

/// Pure N.3 decision boundary. It consumes N.2 evidence and never creates it.
final class ProactiveNotificationPolicyEngine {
  const ProactiveNotificationPolicyEngine();

  NotificationDeliveryDecision decideSignal({
    required ProactiveNotificationPolicy policy,
    required ProactiveDetectionSignal signal,
    required List<NotificationDeliveryRecord> history,
    required NotificationPermissionState permission,
    required NotificationSettings notificationSettings,
    required DateTime now,
  }) {
    policy.validate();
    final current = now.toUtc();
    final category = categoryForSignal(signal);
    final settings = policy.categorySettings[category]!;
    NotificationDeliveryDecision decision(
      NotificationDeliveryDecisionType type,
      NotificationDeliveryReason reason, {
      DateTime? scheduledAt,
      bool critical = false,
    }) =>
        NotificationDeliveryDecision(
          type: type,
          reasonCode: reason,
          category: category,
          scheduledAt: scheduledAt,
          replacementKey: signal.replacementKey,
          policyRevision: policy.policyRevision,
          priority: settings.priority,
          isCriticalProductAlert: critical,
          dailyCount: _daily(history, current).length,
          windowCount: _window(history, current, policy.rateLimitPolicy).length,
          revalidationRequired: true,
        );

    if (!policy.enabled) {
      return decision(
        NotificationDeliveryDecisionType.suppressDisabled,
        NotificationDeliveryReason.policyDisabled,
      );
    }
    if (!settings.enabled ||
        settings.deliveryMode == NotificationDeliveryMode.disabled) {
      return decision(
        NotificationDeliveryDecisionType.suppressDisabled,
        NotificationDeliveryReason.categoryDisabled,
      );
    }
    if (signal.accountScopeId != policy.accountScopeId) {
      throw const FormatException('proactive_policy_account_mismatch');
    }
    if (signal.coverageState == DetectionCoverageKind.stale ||
        signal.coverageState == DetectionCoverageKind.unavailable ||
        signal.coverageState == DetectionCoverageKind.corrupted ||
        !signal.validUntil.isAfter(current)) {
      return decision(
        NotificationDeliveryDecisionType.suppressStale,
        signal.validUntil.isAfter(current)
            ? NotificationDeliveryReason.staleCoverage
            : NotificationDeliveryReason.expired,
      );
    }
    if (!notificationSettings.enabled ||
        !permission.notificationsEnabled ||
        permission.state == NotificationPermissionStatus.denied ||
        permission.state == NotificationPermissionStatus.permanentlyDenied) {
      return decision(
        NotificationDeliveryDecisionType.suppressPermission,
        notificationSettings.enabled
            ? NotificationDeliveryReason.permissionMissing
            : NotificationDeliveryReason.settingsDisabled,
      );
    }

    final critical = _isCritical(
      policy: policy,
      settings: settings,
      signal: signal,
      history: history,
      now: current,
    );
    if (policy.pause.isActiveAt(current, category) &&
        !(critical &&
            policy.pause.state == ProactivePauseState.pausedUntil &&
            policy.criticalProductAlertPolicy.allowDuringTemporaryPause)) {
      return decision(
        NotificationDeliveryDecisionType.suppressPaused,
        NotificationDeliveryReason.paused,
      );
    }
    if (!signal.isNotifiable ||
        !_confidenceMeets(
          signal.confidenceLevel,
          settings.minimumConfidence,
        ) ||
        !_evidenceMeets(
          signal.evidenceLevel,
          settings.minimumEvidenceLevel,
        )) {
      return decision(
        NotificationDeliveryDecisionType.suppressInsufficientEvidence,
        NotificationDeliveryReason.insufficientEvidence,
      );
    }
    final duplicate = history.where(
      (item) =>
          item.incidentFingerprint == signal.incidentFingerprint &&
          current.difference(item.decidedAt.toUtc()) < settings.cooldown,
    );
    if (duplicate.isNotEmpty) {
      return decision(
        NotificationDeliveryDecisionType.suppressDuplicate,
        NotificationDeliveryReason.duplicate,
      );
    }

    final quietEnd = _quietHoursEnd(policy.quietHours, current);
    if (quietEnd != null &&
        !(critical &&
            policy.criticalProductAlertPolicy.allowDuringQuietHours &&
            settings.allowDuringQuietHours)) {
      return switch (policy.quietHours!.behavior) {
        NotificationQuietHoursBehavior.deferUntilQuietHoursEnd =>
          quietEnd.isBefore(signal.validUntil)
              ? decision(
                  NotificationDeliveryDecisionType.deferUntil,
                  NotificationDeliveryReason.quietHours,
                  scheduledAt: quietEnd,
                )
              : decision(
                  NotificationDeliveryDecisionType.includeInDailySummary,
                  NotificationDeliveryReason.summarySelected,
                ),
        NotificationQuietHoursBehavior.includeInNextSummary => decision(
            NotificationDeliveryDecisionType.includeInDailySummary,
            NotificationDeliveryReason.summarySelected,
          ),
        NotificationQuietHoursBehavior.suppressLowPriority ||
        NotificationQuietHoursBehavior.allowCriticalProductAlertsOnly =>
          decision(
            NotificationDeliveryDecisionType.suppressQuietHours,
            NotificationDeliveryReason.quietHours,
          ),
      };
    }

    final day = _daily(history, current);
    final byCategory = day.where((item) => item.category == category).length;
    final window = _window(history, current, policy.rateLimitPolicy);
    final last = history.isEmpty
        ? null
        : (history.toList()..sort((a, b) => b.decidedAt.compareTo(a.decidedAt)))
            .first;
    final spacingBlocked = last != null &&
        current.difference(last.decidedAt.toUtc()) <
            policy.rateLimitPolicy.minimumSpacing;
    if (day.length >= policy.rateLimitPolicy.maximumTotalPerDay ||
        byCategory >= settings.dailyMaximum ||
        window.length >= policy.rateLimitPolicy.maximumImmediatePerWindow ||
        spacingBlocked) {
      return _afterLimit(
        policy: policy,
        signal: signal,
        category: category,
        settings: settings,
        dailyCount: day.length,
        windowCount: window.length,
      );
    }

    if (settings.deliveryMode == NotificationDeliveryMode.dailySummaryOnly ||
        !settings.allowImmediateDelivery) {
      return decision(
        NotificationDeliveryDecisionType.includeInDailySummary,
        NotificationDeliveryReason.summarySelected,
        critical: critical,
      );
    }
    return decision(
      NotificationDeliveryDecisionType.schedule,
      NotificationDeliveryReason.eligibleScheduled,
      scheduledAt: signal.validFrom.isAfter(current)
          ? signal.validFrom
          : current.add(const Duration(minutes: 1)),
      critical: critical,
    );
  }

  NotificationDeliveryDecision _afterLimit({
    required ProactiveNotificationPolicy policy,
    required ProactiveDetectionSignal signal,
    required ProactiveAlertCategory category,
    required AlertCategorySettings settings,
    required int dailyCount,
    required int windowCount,
  }) {
    final canSummarize =
        settings.includeInDailySummary && policy.dailySummarySettings.enabled;
    final type = switch (policy.rateLimitPolicy.afterLimit) {
      NotificationRateLimitStrategy.includeInDailySummary when canSummarize =>
        NotificationDeliveryDecisionType.includeInDailySummary,
      NotificationRateLimitStrategy.defer =>
        NotificationDeliveryDecisionType.deferUntil,
      _ => NotificationDeliveryDecisionType.suppressRateLimit,
    };
    return NotificationDeliveryDecision(
      type: type,
      reasonCode: type == NotificationDeliveryDecisionType.includeInDailySummary
          ? NotificationDeliveryReason.summarySelected
          : NotificationDeliveryReason.rateLimit,
      category: category,
      scheduledAt: type == NotificationDeliveryDecisionType.deferUntil
          ? signal.validFrom.add(const Duration(hours: 1))
          : null,
      replacementKey: signal.replacementKey,
      policyRevision: policy.policyRevision,
      priority: settings.priority,
      isCriticalProductAlert: false,
      dailyCount: dailyCount,
      windowCount: windowCount,
      revalidationRequired: true,
    );
  }

  bool _isCritical({
    required ProactiveNotificationPolicy policy,
    required AlertCategorySettings settings,
    required ProactiveDetectionSignal signal,
    required List<NotificationDeliveryRecord> history,
    required DateTime now,
  }) {
    if (!policy.criticalProductAlertPolicy.enabled ||
        !settings.criticalEligibility ||
        signal.reasonCode == ProactiveDetectionReason.potentialOmission ||
        signal.coverageState != DetectionCoverageKind.complete ||
        signal.confidenceLevel == DetectionConfidenceLevel.insufficient ||
        signal.evidenceLevel == DetectionEvidenceLevel.insufficient ||
        signal.technicalSeverity != DetectionTechnicalSeverity.important ||
        signal.validFrom.difference(now) >
            policy.criticalProductAlertPolicy.horizon) {
      return false;
    }
    if (signal.reasonCode == ProactiveDetectionReason.deadlineApproaching &&
        !signal.evidence.any(
          (item) =>
              item.sourceType ==
                  DetectionEvidenceSource.consequenceRelationR2 ||
              item.sourceType == DetectionEvidenceSource.dependencyRelationR2,
        )) {
      return false;
    }
    final todayCritical =
        _daily(history, now).where((item) => item.critical).length;
    return todayCritical < policy.criticalProductAlertPolicy.maximumPerDay;
  }

  static bool _confidenceMeets(
    DetectionConfidenceLevel actual,
    DetectionConfidenceLevel minimum,
  ) =>
      _confidenceRank(actual) >= _confidenceRank(minimum);

  static int _confidenceRank(DetectionConfidenceLevel level) => switch (level) {
        DetectionConfidenceLevel.insufficient => 0,
        DetectionConfidenceLevel.strong => 1,
        DetectionConfidenceLevel.certain => 2,
      };

  static bool _evidenceMeets(
    DetectionEvidenceLevel actual,
    DetectionEvidenceLevel minimum,
  ) =>
      _evidenceRank(actual) >= _evidenceRank(minimum);

  static int _evidenceRank(DetectionEvidenceLevel level) => switch (level) {
        DetectionEvidenceLevel.insufficient => 0,
        DetectionEvidenceLevel.explicit => 1,
        DetectionEvidenceLevel.confirmedStructured => 2,
      };

  static List<NotificationDeliveryRecord> _daily(
    List<NotificationDeliveryRecord> history,
    DateTime now,
  ) =>
      history
          .where(
            (item) =>
                now.difference(item.decidedAt.toUtc()) <
                const Duration(days: 1),
          )
          .toList();

  static List<NotificationDeliveryRecord> _window(
    List<NotificationDeliveryRecord> history,
    DateTime now,
    NotificationRateLimitPolicy policy,
  ) =>
      history
          .where(
            (item) => now.difference(item.decidedAt.toUtc()) < policy.window,
          )
          .toList();

  static DateTime? _quietHoursEnd(
    NotificationQuietHours? quiet,
    DateTime now,
  ) {
    if (quiet == null || !quiet.enabled) return null;
    final location = tz.getLocation(quiet.timezoneId);
    final local = tz.TZDateTime.from(now, location);
    final minute = local.hour * 60 + local.minute;
    final inside = quiet.crossesMidnight
        ? minute >= quiet.startMinute || minute < quiet.endMinute
        : minute >= quiet.startMinute && minute < quiet.endMinute;
    if (!inside) return null;
    final startWeekday = quiet.crossesMidnight && minute < quiet.endMinute
        ? local.subtract(const Duration(days: 1)).weekday
        : local.weekday;
    if (!quiet.weekdays.contains(startWeekday)) return null;
    var end = tz.TZDateTime(
      location,
      local.year,
      local.month,
      local.day,
      quiet.endMinute ~/ 60,
      quiet.endMinute % 60,
    );
    if (!end.isAfter(local)) end = end.add(const Duration(days: 1));
    return end.toUtc();
  }

  static ProactiveAlertCategory categoryForSignal(
    ProactiveDetectionSignal signal,
  ) =>
      switch (signal.reasonCode) {
        ProactiveDetectionReason.deadlineApproaching =>
          ProactiveAlertCategory.deadlineApproaching,
        ProactiveDetectionReason.deadlinePassed =>
          ProactiveAlertCategory.deadlinePassed,
        ProactiveDetectionReason.objectivelyDelayed =>
          ProactiveAlertCategory.objectivelyDelayed,
        ProactiveDetectionReason.structuredConflict =>
          ProactiveAlertCategory.structuredConflict,
        ProactiveDetectionReason.potentialOmission =>
          ProactiveAlertCategory.potentialOmission,
      };
}
