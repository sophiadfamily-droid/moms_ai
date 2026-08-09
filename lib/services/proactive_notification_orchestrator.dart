import 'package:timezone/timezone.dart' as tz;

import '../models/local_notification_models.dart';
import '../models/proactive_detection.dart';
import '../models/proactive_notification_policy.dart';
import 'daily_summary_builder.dart';
import 'app_diagnostics.dart';
import 'detection_notification_coordinator.dart';
import 'local_notification_scheduler.dart';
import 'notification_permission_service.dart';
import 'notification_settings_service.dart';
import 'proactive_detection_registry.dart';
import 'proactive_notification_delivery_registry.dart';
import 'proactive_notification_policy_engine.dart';
import 'proactive_notification_policy_service.dart';

/// Canonical N.3 application boundary. N.2 detects, this class decides, and
/// N.1 alone talks to the platform.
final class ProactiveNotificationOrchestrator
    implements DetectionDeliveryCoordinator {
  const ProactiveNotificationOrchestrator({
    required this.scheduler,
    required this.signalRegistry,
    required this.deliveryRegistry,
    required this.policyService,
    required this.permissionService,
    required this.notificationSettingsService,
    required this.currentAccountScopeId,
    this.policyEngine = const ProactiveNotificationPolicyEngine(),
    this.summaryBuilder = const DailySummaryBuilder(),
    this.now = DateTime.now,
  });

  final LocalNotificationScheduler scheduler;
  final ProactiveDetectionRegistry signalRegistry;
  final ProactiveNotificationDeliveryRegistry deliveryRegistry;
  final ProactiveNotificationPolicyService policyService;
  final NotificationPermissionService permissionService;
  final NotificationSettingsService notificationSettingsService;
  final String? Function() currentAccountScopeId;
  final ProactiveNotificationPolicyEngine policyEngine;
  final DailySummaryBuilder summaryBuilder;
  final DateTime Function() now;

  @override
  Future<DetectionNotificationResult> apply(
    ProactiveDetectionResult result, {
    required String timezoneId,
  }) async {
    final scope = currentAccountScopeId();
    if (scope == null || scope.trim().isEmpty) {
      throw const FormatException('proactive_policy_auth_required');
    }
    if (result.activeSignals.any((item) => item.accountScopeId != scope) ||
        result.resolvedSignals.any((item) => item.accountScopeId != scope)) {
      throw const FormatException('proactive_policy_account_mismatch');
    }
    final current = now().toUtc();
    final policy = await policyService.load();
    final permission = await permissionService.readCurrent();
    final notificationSettings = await notificationSettingsService.load();
    var deliveryState = await deliveryRegistry.load(scope);
    var signalState = await signalRegistry.load(scope);
    var scheduled = 0;
    var cancelled = 0;
    var failed = 0;
    final signalUpdates = <ProactiveDetectionSignal>[];

    for (final resolved in result.resolvedSignals) {
      if (resolved.notificationLogicalId != null) {
        final outcome = await scheduler.cancel(resolved.notificationLogicalId!);
        if (outcome.type == NotificationScheduleResultType.cancelled ||
            outcome.type == NotificationScheduleResultType.idempotent) {
          cancelled++;
        } else {
          failed++;
        }
      }
      signalUpdates.add(resolved);
    }

    final ordered = result.activeSignals.toList()
      ..sort((a, b) {
        final categoryA =
            ProactiveNotificationPolicyEngine.categoryForSignal(a);
        final categoryB =
            ProactiveNotificationPolicyEngine.categoryForSignal(b);
        final priority = policy.categorySettings[categoryB]!.priority
            .compareTo(policy.categorySettings[categoryA]!.priority);
        return priority != 0
            ? priority
            : a.incidentFingerprint.compareTo(b.incidentFingerprint);
      });
    final summaryCandidates = <ProactiveDetectionSignal>[];
    for (final signal in ordered.take(policy.rateLimitPolicy.maximumActive)) {
      final decision = policyEngine.decideSignal(
        policy: policy,
        signal: signal,
        history: deliveryState.records,
        permission: permission,
        notificationSettings: notificationSettings,
        now: current,
      );
      AppDiagnostics.record(
        component: 'proactive_notification',
        domain: 'notification',
        operation: 'decide',
        step: 'policy_${decision.type.name}',
        code: decision.type == NotificationDeliveryDecisionType.schedule ||
                decision.type == NotificationDeliveryDecisionType.deliverNow
            ? AppErrorCode.proactiveShow
            : AppErrorCode.proactiveNoShow,
        severity: AppErrorSeverity.info,
        metadata: {
          'decision': decision.type.name,
          'reasonCodes': decision.reasonCode.name,
          'count': decision.dailyCount,
          'candidateCount': decision.windowCount,
        },
      );
      if (decision.type ==
          NotificationDeliveryDecisionType.includeInDailySummary) {
        summaryCandidates.add(signal);
        signalUpdates.add(signal.copyWith(
          state: ProactiveDetectionState.eligible,
          clearNotificationLogicalId: true,
        ));
        continue;
      }
      if (decision.type != NotificationDeliveryDecisionType.schedule &&
          decision.type != NotificationDeliveryDecisionType.deliverNow &&
          decision.type != NotificationDeliveryDecisionType.deferUntil &&
          decision.type != NotificationDeliveryDecisionType.replaceExisting) {
        if (_requiresCancellation(decision.type) &&
            signal.notificationLogicalId != null) {
          final cancellation =
              await scheduler.cancel(signal.notificationLogicalId!);
          if (cancellation.type == NotificationScheduleResultType.cancelled ||
              cancellation.type == NotificationScheduleResultType.idempotent) {
            cancelled++;
            signalUpdates.add(signal.copyWith(
              state: ProactiveDetectionState.eligible,
              clearNotificationLogicalId: true,
            ));
          } else {
            failed++;
          }
        } else {
          // Delivery policy controls OS notifications, not the in-app
          // attention center. A currently proven signal must remain visible
          // even when a duplicate notification is intentionally suppressed.
          signalUpdates.add(signal.copyWith(
            state: ProactiveDetectionState.eligible,
            clearNotificationLogicalId: true,
          ));
        }
        continue;
      }
      final logicalId = 'n3-${signal.detectionId}';
      final instant =
          decision.scheduledAt ?? current.add(const Duration(minutes: 1));
      if (!instant.isBefore(signal.validUntil)) {
        signalUpdates.add(signal.copyWith(
          state: ProactiveDetectionState.expired,
          suppressionReason: DetectionSuppressionReason.technicalLimit,
        ));
        continue;
      }
      final schedule = await scheduler.reschedule(
        _signalRequest(
          signal: signal,
          scope: scope,
          timezoneId: timezoneId,
          logicalId: logicalId,
          scheduledAt: instant,
          policyRevision: policy.policyRevision,
        ),
      );
      if (_scheduled(schedule)) {
        scheduled++;
        signalUpdates.add(signal.copyWith(
          state: ProactiveDetectionState.scheduled,
          notificationLogicalId: logicalId,
        ));
        deliveryState = deliveryState.add(
          NotificationDeliveryRecord(
            incidentFingerprint: signal.incidentFingerprint,
            category: decision.category,
            decidedAt: current,
            decision: decision.type,
            replacementCount: decision.type ==
                    NotificationDeliveryDecisionType.replaceExisting
                ? 1
                : 0,
            deferralCount:
                decision.type == NotificationDeliveryDecisionType.deferUntil
                    ? 1
                    : 0,
            critical: decision.isCriticalProductAlert,
          ),
          now: current,
        );
      } else {
        failed++;
      }
    }

    final summaryAllowed = policy.enabled &&
        policy.dailySummarySettings.enabled &&
        policy.categorySettings[ProactiveAlertCategory.dailySummary]!.enabled &&
        !policy.pause.isActiveAt(
          current,
          ProactiveAlertCategory.dailySummary,
        );
    if (summaryAllowed) {
      final build = summaryBuilder.build(
        accountScopeId: scope,
        signals: [...summaryCandidates, ...ordered],
        coverage: result.coverage,
        policy: policy,
        now: current,
      );
      final snapshot = build.snapshot;
      if (snapshot == null) {
        final cancellation = await scheduler.cancel('n3-summary-$scope');
        if (cancellation.type == NotificationScheduleResultType.cancelled) {
          cancelled++;
        }
      } else {
        final instant = _nextSummaryInstant(
          policy.dailySummarySettings,
          current,
          policy.quietHours,
        );
        final schedule = await scheduler.reschedule(
          _summaryRequest(
            snapshot: snapshot,
            scope: scope,
            scheduledAt: instant,
            policyRevision: policy.policyRevision,
          ),
        );
        if (_scheduled(schedule)) {
          scheduled++;
        } else {
          failed++;
        }
      }
    } else {
      final cancellation = await scheduler.cancel('n3-summary-$scope');
      if (cancellation.type == NotificationScheduleResultType.cancelled) {
        cancelled++;
      }
    }

    signalState = signalState.merge(updates: signalUpdates, now: current);
    await signalRegistry.save(signalState);
    await deliveryRegistry.save(deliveryState);
    return DetectionNotificationResult(
      type: failed == 0
          ? policy.enabled
              ? DetectionNotificationResultType.applied
              : DetectionNotificationResultType.disabled
          : scheduled == 0 && cancelled == 0
              ? DetectionNotificationResultType.failed
              : DetectionNotificationResultType.partial,
      numberScheduled: scheduled,
      numberCancelled: cancelled,
      numberFailed: failed,
      code:
          failed == 0 ? 'proactive_policy_applied' : 'proactive_policy_partial',
    );
  }

  LocalNotificationRequest _signalRequest({
    required ProactiveDetectionSignal signal,
    required String scope,
    required String timezoneId,
    required String logicalId,
    required DateTime scheduledAt,
    required int policyRevision,
  }) =>
      LocalNotificationRequest(
        logicalNotificationId: logicalId,
        accountScopeId: scope,
        category: _localCategory(signal.detectorType),
        createdAt: now().toUtc(),
        scheduledAt: scheduledAt,
        expiresAt: signal.validUntil,
        timezoneId: timezoneId,
        scheduleMeaning: NotificationScheduleMeaning.absoluteInstant,
        privacyLevel: NotificationPrivacyLevel.generic,
        interactionType: NotificationInteractionType.openSafeDestination,
        destinationType: signal.interactionDestination,
        destinationReference: 'attention',
        replacementKey: signal.replacementKey,
        source: LocalNotificationSource.proactivePolicy,
        status: LocalNotificationStatus.registered,
        platformNotificationId: _platformId(logicalId),
        correlationId: signal.detectionId,
        policyVersionObserved: policyRevision,
      );

  LocalNotificationRequest _summaryRequest({
    required DailySummarySnapshot snapshot,
    required String scope,
    required DateTime scheduledAt,
    required int policyRevision,
  }) {
    final logicalId = 'n3-summary-$scope';
    return LocalNotificationRequest(
      logicalNotificationId: logicalId,
      accountScopeId: scope,
      category: LocalNotificationCategory.dailySummary,
      createdAt: now().toUtc(),
      scheduledAt: scheduledAt,
      expiresAt: scheduledAt.add(const Duration(days: 1)),
      timezoneId: snapshot.timezoneId,
      scheduleMeaning: NotificationScheduleMeaning.absoluteInstant,
      privacyLevel: NotificationPrivacyLevel.generic,
      interactionType: NotificationInteractionType.openSafeDestination,
      destinationType: NotificationDestinationType.dailySummary,
      destinationReference: 'daily-summary',
      replacementKey: snapshot.replacementKey,
      source: LocalNotificationSource.dailySummary,
      status: LocalNotificationStatus.registered,
      platformNotificationId: _platformId(logicalId),
      correlationId: snapshot.summaryId,
      policyVersionObserved: policyRevision,
    );
  }

  static DateTime _nextSummaryInstant(
    DailySummarySettings settings,
    DateTime now,
    NotificationQuietHours? quiet,
  ) {
    final location = tz.getLocation(settings.timezoneId);
    final local = tz.TZDateTime.from(now, location);
    for (var offset = 0; offset < 8; offset++) {
      final date = local.add(Duration(days: offset));
      if (!settings.weekdays.contains(date.weekday)) continue;
      var candidate = tz.TZDateTime(
        location,
        date.year,
        date.month,
        date.day,
        settings.localMinute ~/ 60,
        settings.localMinute % 60,
      );
      if (!candidate.toUtc().isAfter(now)) continue;
      if (quiet != null &&
          quiet.enabled &&
          settings.deferAfterQuietHours &&
          quiet.weekdays.contains(candidate.weekday)) {
        final minute = candidate.hour * 60 + candidate.minute;
        final inside = quiet.crossesMidnight
            ? minute >= quiet.startMinute || minute < quiet.endMinute
            : minute >= quiet.startMinute && minute < quiet.endMinute;
        if (inside) {
          candidate = tz.TZDateTime(
            location,
            candidate.year,
            candidate.month,
            candidate.day,
            quiet.endMinute ~/ 60,
            quiet.endMinute % 60,
          );
          if (!candidate.toUtc().isAfter(now)) {
            candidate = candidate.add(const Duration(days: 1));
          }
        }
      }
      return candidate.toUtc();
    }
    throw const FormatException('daily_summary_schedule_unavailable');
  }

  static bool _scheduled(NotificationScheduleResult result) =>
      result.type == NotificationScheduleResultType.scheduled ||
      result.type == NotificationScheduleResultType.replaced ||
      result.type == NotificationScheduleResultType.idempotent;

  static bool _requiresCancellation(
    NotificationDeliveryDecisionType type,
  ) =>
      type == NotificationDeliveryDecisionType.suppressDisabled ||
      type == NotificationDeliveryDecisionType.suppressPaused ||
      type == NotificationDeliveryDecisionType.suppressQuietHours ||
      type == NotificationDeliveryDecisionType.suppressPermission ||
      type == NotificationDeliveryDecisionType.suppressStale ||
      type == NotificationDeliveryDecisionType.cancelExisting;

  static LocalNotificationCategory _localCategory(
    ProactiveDetectorType type,
  ) =>
      switch (type) {
        ProactiveDetectorType.deadline =>
          LocalNotificationCategory.deadlineDetection,
        ProactiveDetectorType.delay => LocalNotificationCategory.delayDetection,
        ProactiveDetectorType.conflict =>
          LocalNotificationCategory.conflictDetection,
        ProactiveDetectorType.potentialOmission =>
          LocalNotificationCategory.forgottenItemDetection,
      };

  static int _platformId(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }
}
