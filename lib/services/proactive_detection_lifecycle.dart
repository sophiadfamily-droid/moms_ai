import '../models/proactive_detection.dart';
import 'detection_notification_coordinator.dart';
import 'proactive_detection_engine.dart';
import 'proactive_detection_registry.dart';

enum DetectionEvaluationTrigger {
  authenticatedBootstrap,
  foreground,
  eventChanged,
  taskChanged,
  routineChanged,
  dependencyChanged,
  timezoneChanged,
  sourceResolved,
  explicitInternalRefresh,
  networkRestored,
}

abstract interface class ProactiveDetectionInputProvider {
  Future<ProactiveDetectionInput> load({
    required String accountScopeId,
    required List<ProactiveDetectionSignal> existingSignals,
    required DetectionEvaluationTrigger trigger,
  });
}

final class ProactiveDetectionLifecycleResult {
  const ProactiveDetectionLifecycleResult({
    required this.detection,
    required this.notifications,
  });

  final ProactiveDetectionResult detection;
  final DetectionNotificationResult notifications;
}

/// Event-driven and bounded. This boundary owns no timer, isolate, background
/// worker, retry loop, or domain mutation.
final class ProactiveDetectionLifecycle {
  const ProactiveDetectionLifecycle({
    required this.engine,
    required this.inputProvider,
    required this.registry,
    required this.notificationCoordinator,
    required this.currentAccountScopeId,
    required this.timezoneId,
    this.policy = const ProactiveDetectionPolicy(),
    this.now = DateTime.now,
  });

  final ProactiveDetectionEngine engine;
  final ProactiveDetectionInputProvider inputProvider;
  final ProactiveDetectionRegistry registry;
  final DetectionNotificationCoordinator notificationCoordinator;
  final String? Function() currentAccountScopeId;
  final String Function() timezoneId;
  final ProactiveDetectionPolicy policy;
  final DateTime Function() now;

  Future<ProactiveDetectionLifecycleResult> evaluate(
    DetectionEvaluationTrigger trigger,
  ) async {
    final scope = currentAccountScopeId();
    if (scope == null || scope.trim().isEmpty) {
      throw const FormatException('detection_auth_required');
    }
    final registryState = await registry.load(scope);
    final input = await inputProvider.load(
      accountScopeId: scope,
      existingSignals: registryState.signals,
      trigger: trigger,
    );
    if (input.accountScopeId != scope) {
      throw const FormatException('detection_account_mismatch');
    }
    final result = engine.evaluate(
      input: input,
      policy: policy,
      now: now(),
    );
    final notifications = await notificationCoordinator.apply(
      result,
      timezoneId: timezoneId(),
    );
    return ProactiveDetectionLifecycleResult(
      detection: result,
      notifications: notifications,
    );
  }
}
