import '../models/local_notification_models.dart';

abstract interface class NotificationPermissionGateway {
  Future<NotificationPermissionState> read();
  Future<NotificationPermissionState> request();
  Future<bool> openSettings();
}

final class NotificationPermissionService {
  const NotificationPermissionService(this.gateway);

  final NotificationPermissionGateway gateway;

  Future<NotificationPermissionState> readCurrent() => gateway.read();

  Future<NotificationPermissionState> requestAfterExplicitExplanation({
    required bool userInitiated,
    required bool explanationShown,
  }) {
    if (!userInitiated || !explanationShown) {
      throw const FormatException('notification_permission_not_explicit');
    }
    return gateway.request();
  }

  Future<bool> openSystemSettings({required bool userInitiated}) {
    if (!userInitiated) {
      throw const FormatException('notification_settings_not_explicit');
    }
    return gateway.openSettings();
  }
}
