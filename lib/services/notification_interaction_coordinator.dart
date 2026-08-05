import '../models/local_notification_models.dart';
import 'local_notification_registry.dart';
import 'local_notification_scheduler.dart';

enum NotificationNavigationIntentType {
  home,
  actionHistory,
  notificationsSettings,
  dailySummary,
  neutral,
}

final class NotificationNavigationIntent {
  const NotificationNavigationIntent(this.type, this.reasonCode);
  final NotificationNavigationIntentType type;
  final String reasonCode;
}

final class NotificationInteractionCoordinator {
  const NotificationInteractionCoordinator({
    required this.registry,
    required this.currentAccountScopeId,
    this.now = DateTime.now,
  });

  final LocalNotificationRegistry registry;
  final String? Function() currentAccountScopeId;
  final DateTime Function() now;

  Future<NotificationNavigationIntent> resolve(String rawPayload) async {
    NotificationInteractionPayload payload;
    try {
      payload = NotificationInteractionPayload.parse(rawPayload);
    } on Object {
      return const NotificationNavigationIntent(
        NotificationNavigationIntentType.neutral,
        'notification_payload_invalid',
      );
    }
    final scope = currentAccountScopeId();
    if (scope == null || scope.trim().isEmpty) {
      return const NotificationNavigationIntent(
        NotificationNavigationIntentType.neutral,
        'notification_account_unavailable',
      );
    }
    final state = await registry.load(scope);
    final matches = state.entries.where(
      (item) => item.logicalNotificationId == payload.notificationId,
    );
    if (matches.isEmpty) {
      return const NotificationNavigationIntent(
        NotificationNavigationIntentType.neutral,
        'notification_unknown',
      );
    }
    final request = matches.first;
    if (request.correlationId != payload.interactionToken ||
        request.destinationType != payload.destinationType ||
        request.expiresAt?.toUtc().isBefore(now().toUtc()) == true ||
        request.status == LocalNotificationStatus.cancelled ||
        request.status == LocalNotificationStatus.expired) {
      return const NotificationNavigationIntent(
        NotificationNavigationIntentType.neutral,
        'notification_reference_stale',
      );
    }
    return NotificationNavigationIntent(
      request.destinationReference == 'attention'
          ? NotificationNavigationIntentType.dailySummary
          : switch (request.destinationType) {
              NotificationDestinationType.home =>
                NotificationNavigationIntentType.home,
              NotificationDestinationType.actionHistory =>
                NotificationNavigationIntentType.actionHistory,
              NotificationDestinationType.notificationsSettings =>
                NotificationNavigationIntentType.notificationsSettings,
              NotificationDestinationType.dailySummary =>
                NotificationNavigationIntentType.dailySummary,
            },
      'notification_navigation_safe',
    );
  }
}
