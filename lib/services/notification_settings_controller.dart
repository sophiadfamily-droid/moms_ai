import 'package:flutter/foundation.dart';

import '../models/local_notification_models.dart';
import 'local_notification_scheduler.dart';
import 'notification_permission_service.dart';
import 'notification_settings_service.dart';

typedef NotificationTestSender = Future<NotificationScheduleResult> Function();

final class NotificationSettingsController extends ChangeNotifier {
  NotificationSettingsController({
    required this.settingsService,
    required this.permissionService,
    required this.sendTest,
  });

  final NotificationSettingsService settingsService;
  final NotificationPermissionService permissionService;
  final NotificationTestSender sendTest;

  NotificationSettings? settings;
  NotificationPermissionState? permission;
  bool loading = false;
  bool saving = false;
  String? message;

  Future<void> load() async {
    loading = true;
    message = null;
    notifyListeners();
    settings = await settingsService.load();
    permission = await permissionService.readCurrent();
    loading = false;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    final current = settings;
    if (current == null) return;
    if (value && !current.permissionPromptExplained) {
      message = 'Lis l’explication puis utilise le bouton d’autorisation.';
      notifyListeners();
      return;
    }
    await _save(enabled: value);
  }

  Future<void> requestPermissionExplicitly() async {
    final current = settings;
    if (current == null) return;
    saving = true;
    notifyListeners();
    permission = await permissionService.requestAfterExplicitExplanation(
      userInitiated: true,
      explanationShown: true,
    );
    settings = await settingsService.save(
      enabled: permission!.notificationsEnabled,
      permissionPromptExplained: true,
      soundEnabled: current.soundEnabled,
      vibrationEnabled: current.vibrationEnabled,
      badgeEnabled: current.badgeEnabled,
    );
    saving = false;
    message = permission!.notificationsEnabled
        ? 'Notifications autorisées.'
        : 'Les notifications restent désactivées.';
    notifyListeners();
  }

  Future<void> updateOptions({
    bool? sound,
    bool? vibration,
    bool? badge,
  }) async {
    final current = settings;
    if (current == null) return;
    saving = true;
    notifyListeners();
    settings = await settingsService.save(
      enabled: current.enabled,
      permissionPromptExplained: current.permissionPromptExplained,
      soundEnabled: sound ?? current.soundEnabled,
      vibrationEnabled: vibration ?? current.vibrationEnabled,
      badgeEnabled: badge ?? current.badgeEnabled,
    );
    saving = false;
    notifyListeners();
  }

  Future<void> sendTestNotification() async {
    final result = await sendTest();
    message = switch (result.type) {
      NotificationScheduleResultType.delivered =>
        'La notification de test a été envoyée.',
      NotificationScheduleResultType.permissionRequired =>
        'Autorise les notifications pour effectuer ce test.',
      NotificationScheduleResultType.channelDisabled =>
        'Le canal de notifications est désactivé dans le téléphone.',
      NotificationScheduleResultType.disabled =>
        'Active les notifications avant le test.',
      _ => 'La notification de test n’a pas pu être envoyée.',
    };
    notifyListeners();
  }

  Future<void> openSystemSettings() async {
    await permissionService.openSystemSettings(userInitiated: true);
    permission = await permissionService.readCurrent();
    notifyListeners();
  }

  Future<void> _save({required bool enabled}) async {
    final current = settings!;
    saving = true;
    notifyListeners();
    settings = await settingsService.save(
      enabled: enabled,
      permissionPromptExplained: current.permissionPromptExplained,
      soundEnabled: current.soundEnabled,
      vibrationEnabled: current.vibrationEnabled,
      badgeEnabled: current.badgeEnabled,
    );
    saving = false;
    notifyListeners();
  }
}
