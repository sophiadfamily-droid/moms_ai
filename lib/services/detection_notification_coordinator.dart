import '../models/local_notification_models.dart';
import '../models/proactive_detection.dart';
import 'local_notification_scheduler.dart';
import 'proactive_detection_engine.dart';
import 'proactive_detection_registry.dart';

enum DetectionNotificationResultType {
  applied,
  partial,
  disabled,
  permissionMissing,
  failed,
}

final class DetectionNotificationResult {
  const DetectionNotificationResult({
    required this.type,
    required this.numberScheduled,
    required this.numberCancelled,
    required this.numberFailed,
    required this.code,
  });

  final DetectionNotificationResultType type;
  final int numberScheduled;
  final int numberCancelled;
  final int numberFailed;
  final String code;
}

/// Application boundary between the pure N.2 engine and the N.1 scheduler.
/// It never reads a business domain and never executes an action.
final class DetectionNotificationCoordinator {
  const DetectionNotificationCoordinator({
    required this.scheduler,
    required this.registry,
    required this.currentAccountScopeId,
    this.policy = const ProactiveDetectionPolicy(),
    this.now = DateTime.now,
  });

  final LocalNotificationScheduler scheduler;
  final ProactiveDetectionRegistry registry;
  final String? Function() currentAccountScopeId;
  final ProactiveDetectionPolicy policy;
  final DateTime Function() now;

  Future<DetectionNotificationResult> apply(
    ProactiveDetectionResult result, {
    required String timezoneId,
  }) async {
    final scope = currentAccountScopeId();
    if (scope == null || scope.trim().isEmpty) {
      throw const FormatException('detection_auth_required');
    }
    if (result.activeSignals.any((item) => item.accountScopeId != scope) ||
        result.resolvedSignals.any((item) => item.accountScopeId != scope)) {
      throw const FormatException('detection_account_mismatch');
    }
    final current = now().toUtc();
    var state = await registry.load(scope);
    var scheduled = 0;
    var cancelled = 0;
    var failed = 0;
    final updates = <ProactiveDetectionSignal>[];
    for (final resolved in result.resolvedSignals) {
      if (resolved.notificationLogicalId != null) {
        final cancel = await scheduler.cancel(resolved.notificationLogicalId!);
        if (cancel.type == NotificationScheduleResultType.cancelled ||
            cancel.type == NotificationScheduleResultType.idempotent) {
          cancelled++;
        } else {
          failed++;
        }
      }
      updates.add(resolved);
    }
    for (final signal in result.activeSignals.take(
      policy.maxNotificationsPerPass,
    )) {
      if (!signal.isNotifiable) continue;
      final logicalId = 'n2-${signal.detectionId}';
      final earliest = current.add(policy.minimumScheduleLead);
      final request = LocalNotificationRequest(
        logicalNotificationId: logicalId,
        accountScopeId: scope,
        category: _category(signal.detectorType),
        createdAt: current,
        scheduledAt: earliest,
        expiresAt: signal.validUntil,
        timezoneId: timezoneId,
        scheduleMeaning: NotificationScheduleMeaning.absoluteInstant,
        privacyLevel: NotificationPrivacyLevel.generic,
        interactionType: NotificationInteractionType.openSafeDestination,
        destinationType: signal.interactionDestination,
        destinationReference: 'attention',
        replacementKey: signal.replacementKey,
        source: LocalNotificationSource.deterministicDetection,
        status: LocalNotificationStatus.registered,
        platformNotificationId: _platformId(logicalId),
        correlationId: signal.detectionId,
        policyVersionObserved: signal.policyVersion,
      );
      NotificationScheduleResult schedule;
      try {
        schedule = await scheduler.reschedule(request);
      } on Object {
        failed++;
        updates.add(signal.copyWith(
          state: ProactiveDetectionState.suppressed,
          suppressionReason: DetectionSuppressionReason.technicalLimit,
        ));
        continue;
      }
      if (schedule.type == NotificationScheduleResultType.scheduled ||
          schedule.type == NotificationScheduleResultType.replaced ||
          schedule.type == NotificationScheduleResultType.idempotent) {
        scheduled++;
        updates.add(signal.copyWith(
          state: ProactiveDetectionState.scheduled,
          notificationLogicalId: logicalId,
        ));
      } else {
        failed++;
        updates.add(signal.copyWith(
          state: ProactiveDetectionState.suppressed,
          suppressionReason: switch (schedule.type) {
            NotificationScheduleResultType.disabled =>
              DetectionSuppressionReason.notificationDisabled,
            NotificationScheduleResultType.permissionRequired ||
            NotificationScheduleResultType.channelDisabled =>
              DetectionSuppressionReason.permissionMissing,
            _ => DetectionSuppressionReason.technicalLimit,
          },
        ));
      }
    }
    state = state.merge(updates: updates, now: current);
    await registry.save(state);
    return DetectionNotificationResult(
      type: failed == 0
          ? DetectionNotificationResultType.applied
          : scheduled == 0 && cancelled == 0
              ? DetectionNotificationResultType.failed
              : DetectionNotificationResultType.partial,
      numberScheduled: scheduled,
      numberCancelled: cancelled,
      numberFailed: failed,
      code: failed == 0
          ? 'detection_notifications_applied'
          : 'detection_notifications_partial',
    );
  }

  static LocalNotificationCategory _category(ProactiveDetectorType type) =>
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
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }
}
