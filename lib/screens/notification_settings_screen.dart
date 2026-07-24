import 'package:flutter/material.dart';

import '../models/local_notification_models.dart';
import '../services/notification_service.dart';
import '../services/notification_settings_controller.dart';

final class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({
    super.key,
    this.controller,
  });

  final NotificationSettingsController? controller;

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

final class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  late final NotificationSettingsController controller;
  late final bool ownsController;

  @override
  void initState() {
    super.initState();
    ownsController = widget.controller == null;
    controller = widget.controller ??
        NotificationSettingsController(
          settingsService: NotificationService.settingsService,
          permissionService: NotificationService.permissionService,
          sendTest: NotificationService.sendExplicitTest,
        );
    controller.addListener(_changed);
    controller.load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(_changed);
    if (ownsController) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = controller.settings;
    final permission = controller.permission;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: SafeArea(
        child: controller.loading || settings == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text(
                    'Les notifications de Zélia restent discrètes : leur '
                    'contenu ne révèle pas tes informations personnelles sur '
                    'l’écran verrouillé.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Un clic ouvre seulement l’application. Les alertes '
                    'automatiques utilisent uniquement les informations '
                    'structurées disponibles dans Zélia.',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Elles peuvent être limitées lorsque certaines données '
                    'ne sont pas disponibles.',
                  ),
                  const SizedBox(height: 20),
                  Text('Permission : ${_permissionLabel(permission?.state)}'),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Notifications activées'),
                    subtitle: const Text(
                      'Les désactiver ne supprime aucune donnée.',
                    ),
                    value: settings.enabled,
                    onChanged: controller.saving
                        ? null
                        : (value) => controller.setEnabled(value),
                  ),
                  if (permission?.canRequest == true ||
                      settings.permissionPromptExplained == false)
                    FilledButton(
                      onPressed: controller.saving
                          ? null
                          : controller.requestPermissionExplicitly,
                      child: const Text('Autoriser les notifications'),
                    ),
                  if (permission?.canOpenSettings == true)
                    OutlinedButton(
                      onPressed: controller.openSystemSettings,
                      child: const Text('Ouvrir les réglages du téléphone'),
                    ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Son'),
                    value: settings.soundEnabled,
                    onChanged: (value) =>
                        controller.updateOptions(sound: value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Vibration'),
                    value: settings.vibrationEnabled,
                    onChanged: (value) =>
                        controller.updateOptions(vibration: value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Badge'),
                    value: settings.badgeEnabled,
                    onChanged: (value) =>
                        controller.updateOptions(badge: value),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: controller.sendTestNotification,
                    icon: const Icon(Icons.notifications_outlined),
                    label: const Text('Envoyer une notification de test'),
                  ),
                  if (controller.saving)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: LinearProgressIndicator(),
                    ),
                  if (controller.message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(controller.message!),
                    ),
                  const SizedBox(height: 16),
                  const Text(
                    'L’autorisation peut être retirée à tout moment dans les '
                    'réglages du téléphone.',
                  ),
                ],
              ),
      ),
    );
  }

  static String _permissionLabel(NotificationPermissionStatus? state) =>
      switch (state) {
        NotificationPermissionStatus.authorized => 'autorisée',
        NotificationPermissionStatus.provisional => 'provisoire',
        NotificationPermissionStatus.denied ||
        NotificationPermissionStatus.permanentlyDenied =>
          'refusée',
        NotificationPermissionStatus.restricted => 'restreinte',
        NotificationPermissionStatus.unavailable => 'indisponible',
        _ => 'non demandée',
      };
}
