import 'dart:convert';

import '../models/local_notification_models.dart';

enum NotificationSystemVisibility { private, secret }

final class SanitizedNotificationContent {
  const SanitizedNotificationContent({
    required this.title,
    required this.body,
    required this.systemCategory,
    required this.payload,
    required this.visibility,
    required this.redactionCount,
  });

  final String title;
  final String body;
  final String systemCategory;
  final String payload;
  final NotificationSystemVisibility visibility;
  final int redactionCount;
}

final class NotificationPrivacySanitizer {
  const NotificationPrivacySanitizer({
    this.policy = const NotificationPrivacyPolicy(),
  });

  final NotificationPrivacyPolicy policy;

  SanitizedNotificationContent sanitize({
    required LocalNotificationRequest request,
    required NotificationPrivacyMode privacyMode,
    required String interactionToken,
  }) {
    request.validate();
    if (!policy.allows(privacyMode, request.privacyLevel) ||
        interactionToken.trim().isEmpty ||
        interactionToken.length > 120) {
      throw const FormatException('notification_privacy_rejected');
    }
    final body = switch (request.category) {
      LocalNotificationCategory.pendingActionAttention =>
        'Une action demande ton attention dans Zélia.',
      _ => 'Tu as une information à consulter dans l’application.',
    };
    final payload = jsonEncode({
      'schemaVersion': 1,
      'notificationId': request.logicalNotificationId,
      'destinationType': request.destinationType.name,
      'interactionToken': interactionToken,
    });
    return SanitizedNotificationContent(
      title: 'Zélia',
      body: privacyMode == NotificationPrivacyMode.hiddenContent ? '' : body,
      systemCategory: switch (request.category) {
        LocalNotificationCategory.explicitReminder => 'zelia_reminders_v1',
        LocalNotificationCategory.pendingActionAttention =>
          'zelia_action_attention_v1',
        _ => 'zelia_general_v1',
      },
      payload: payload,
      visibility: privacyMode == NotificationPrivacyMode.hiddenContent
          ? NotificationSystemVisibility.secret
          : NotificationSystemVisibility.private,
      redactionCount: 1,
    );
  }
}
