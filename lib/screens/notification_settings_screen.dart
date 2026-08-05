import 'package:flutter/material.dart';

import '../models/local_notification_models.dart';
import '../models/proactive_notification_policy.dart';
import '../services/notification_service.dart';
import '../services/notification_settings_controller.dart';
import '../services/proactive_detection_lifecycle.dart';
import '../services/proactive_notification_settings_controller.dart';
import 'daily_summary_screen.dart';

final class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({
    super.key,
    this.controller,
    this.proactiveController,
  });

  final NotificationSettingsController? controller;
  final ProactiveNotificationSettingsController? proactiveController;

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

final class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  late final NotificationSettingsController controller;
  late final bool ownsController;
  ProactiveNotificationSettingsController? proactiveController;
  late final bool ownsProactiveController;

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
    ownsProactiveController =
        widget.proactiveController == null && widget.controller == null;
    proactiveController = widget.proactiveController ??
        (ownsProactiveController
            ? ProactiveNotificationSettingsController(
                service: NotificationService.proactivePolicyService,
                onPolicyChanged: () => NotificationService.evaluateDetections(
                  DetectionEvaluationTrigger.explicitInternalRefresh,
                ),
              )
            : null);
    controller.addListener(_changed);
    proactiveController?.addListener(_changed);
    controller.load();
    proactiveController?.load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(_changed);
    proactiveController?.removeListener(_changed);
    if (ownsController) controller.dispose();
    if (ownsProactiveController) proactiveController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = controller.settings;
    final permission = controller.permission;
    final proactive = proactiveController?.policy;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: SafeArea(
        child: controller.loading ||
                (proactiveController?.loading ?? false) ||
                settings == null ||
                (proactiveController != null && proactive == null)
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
                  if (proactive != null) ...[
                    const Divider(),
                    const Text(
                      'Alertes automatiques',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Zélia peut regrouper les informations importantes dans '
                      'un résumé quotidien pour éviter trop de notifications.',
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Alertes automatiques activées'),
                      value: proactive.enabled,
                      onChanged: proactiveController!.saving
                          ? null
                          : proactiveController!.setEnabled,
                    ),
                    _categorySwitch(
                      proactive,
                      ProactiveAlertCategory.deadlineApproaching,
                      'Ce qui est à faire bientôt',
                    ),
                    _categorySwitch(
                      proactive,
                      ProactiveAlertCategory.deadlinePassed,
                      'Ce qui est en retard',
                    ),
                    _categorySwitch(
                      proactive,
                      ProactiveAlertCategory.objectivelyDelayed,
                      'Ce qui prend du retard',
                    ),
                    _categorySwitch(
                      proactive,
                      ProactiveAlertCategory.structuredConflict,
                      'Plusieurs choses prévues en même temps',
                    ),
                    _categorySwitch(
                      proactive,
                      ProactiveAlertCategory.potentialOmission,
                      'Ce qui semble avoir été oublié',
                    ),
                    _categorySwitch(
                      proactive,
                      ProactiveAlertCategory.explicitReminder,
                      'Rappels demandés',
                    ),
                    _categorySwitch(
                      proactive,
                      ProactiveAlertCategory.pendingActionAttention,
                      'Actions à consulter',
                    ),
                    _categorySwitch(
                      proactive,
                      ProactiveAlertCategory.systemInformation,
                      'Informations système',
                    ),
                    const Divider(),
                    const Text(
                      'Pause et fréquence',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      proactive.pause.state == ProactivePauseState.inactive
                          ? 'Les alertes ne sont pas en pause.'
                          : 'Les alertes automatiques sont en pause.',
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: proactiveController!.saving
                              ? null
                              : () => proactiveController!
                                  .pauseFor(const Duration(hours: 1)),
                          child: const Text('Pause 1 h'),
                        ),
                        OutlinedButton(
                          onPressed: proactiveController!.saving
                              ? null
                              : proactiveController!.pauseIndefinitely,
                          child: const Text('Pause indéfinie'),
                        ),
                        if (proactive.pause.state !=
                            ProactivePauseState.inactive)
                          FilledButton(
                            onPressed: proactiveController!.saving
                                ? null
                                : proactiveController!.resume,
                            child: const Text('Réactiver'),
                          ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Heures calmes'),
                      subtitle: const Text('22 h à 7 h, heure locale'),
                      value: proactive.quietHours?.enabled == true,
                      onChanged: proactiveController!.saving
                          ? null
                          : proactiveController!.setQuietHoursEnabled,
                    ),
                    if (proactive.quietHours?.enabled == true)
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue:
                                  proactive.quietHours!.startMinute ~/ 60,
                              decoration:
                                  const InputDecoration(labelText: 'Début'),
                              items: const [20, 21, 22, 23]
                                  .map(
                                    (hour) => DropdownMenuItem(
                                      value: hour,
                                      child: Text('$hour h'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: proactiveController!.saving
                                  ? null
                                  : (hour) {
                                      if (hour != null) {
                                        proactiveController!.setQuietHoursRange(
                                          startHour: hour,
                                        );
                                      }
                                    },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue:
                                  proactive.quietHours!.endMinute ~/ 60,
                              decoration:
                                  const InputDecoration(labelText: 'Fin'),
                              items: const [6, 7, 8, 9]
                                  .map(
                                    (hour) => DropdownMenuItem(
                                      value: hour,
                                      child: Text('$hour h'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: proactiveController!.saving
                                  ? null
                                  : (hour) {
                                      if (hour != null) {
                                        proactiveController!.setQuietHoursRange(
                                          endHour: hour,
                                        );
                                      }
                                    },
                            ),
                          ),
                        ],
                      ),
                    DropdownButtonFormField<int>(
                      initialValue:
                          proactive.rateLimitPolicy.maximumTotalPerDay,
                      decoration: const InputDecoration(
                        labelText: 'Maximum de notifications par jour',
                      ),
                      items: const [2, 4, 6, 8]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text('$value'),
                            ),
                          )
                          .toList(),
                      onChanged: proactiveController!.saving
                          ? null
                          : (value) {
                              if (value != null) {
                                proactiveController!.setDailyMaximum(value);
                              }
                            },
                    ),
                    const Divider(),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Résumé quotidien'),
                      value: proactive.dailySummarySettings.enabled,
                      onChanged: proactiveController!.saving
                          ? null
                          : proactiveController!.setDailySummaryEnabled,
                    ),
                    DropdownButtonFormField<int>(
                      initialValue:
                          proactive.dailySummarySettings.localMinute ~/ 60,
                      decoration:
                          const InputDecoration(labelText: 'Heure du résumé'),
                      items: const [7, 8, 9, 12, 18, 20]
                          .map(
                            (hour) => DropdownMenuItem(
                              value: hour,
                              child:
                                  Text('${hour.toString().padLeft(2, '0')} h'),
                            ),
                          )
                          .toList(),
                      onChanged: proactive.dailySummarySettings.enabled &&
                              !proactiveController!.saving
                          ? (hour) {
                              if (hour != null) {
                                proactiveController!.setSummaryHour(hour);
                              }
                            }
                          : null,
                    ),
                    const SizedBox(height: 8),
                    const Text('Jours du résumé'),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final entry in const {
                          1: 'L',
                          2: 'M',
                          3: 'M',
                          4: 'J',
                          5: 'V',
                          6: 'S',
                          7: 'D',
                        }.entries)
                          FilterChip(
                            label: Text(entry.value),
                            selected: proactive.dailySummarySettings.weekdays
                                .contains(entry.key),
                            onSelected: proactiveController!.saving
                                ? null
                                : (selected) =>
                                    proactiveController!.toggleSummaryWeekday(
                                      entry.key,
                                      selected,
                                    ),
                          ),
                      ],
                    ),
                    const Text('Inclure dans le résumé'),
                    for (final category in const [
                      ProactiveAlertCategory.deadlineApproaching,
                      ProactiveAlertCategory.deadlinePassed,
                      ProactiveAlertCategory.objectivelyDelayed,
                      ProactiveAlertCategory.structuredConflict,
                      ProactiveAlertCategory.potentialOmission,
                    ])
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(_categoryLabel(category)),
                        value: proactive.dailySummarySettings.includedCategories
                            .contains(category),
                        onChanged: proactiveController!.saving
                            ? null
                            : (value) => proactiveController!
                                    .setCategorySummaryInclusion(
                                  category,
                                  value ?? false,
                                ),
                      ),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const DailySummaryScreen(),
                        ),
                      ),
                      child: const Text('Voir le résumé actuel'),
                    ),
                    const Divider(),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Alertes importantes'),
                      subtitle: const Text(
                        'Elles restent discrètes et ne contournent pas les '
                        'réglages de ton téléphone.',
                      ),
                      value: proactive.criticalProductAlertPolicy.enabled,
                      onChanged: proactiveController!.saving
                          ? null
                          : proactiveController!.setImportantAlerts,
                    ),
                    const Text(
                      'Mettre les alertes en pause ne supprime aucune donnée et '
                      'ne change pas le mode d’action de Zélia. Les rappels '
                      'explicitement demandés restent distincts.',
                    ),
                    if (proactiveController!.saving)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: LinearProgressIndicator(),
                      ),
                    if (proactiveController!.message != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(proactiveController!.message!),
                      ),
                    const SizedBox(height: 12),
                  ],
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

  Widget _categorySwitch(
    ProactiveNotificationPolicy policy,
    ProactiveAlertCategory category,
    String label,
  ) =>
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: policy.categorySettings[category]!.enabled,
        onChanged: proactiveController!.saving
            ? null
            : (value) =>
                proactiveController!.setCategoryEnabled(category, value),
      );

  static String _categoryLabel(ProactiveAlertCategory category) =>
      switch (category) {
        ProactiveAlertCategory.deadlineApproaching => 'À faire bientôt',
        ProactiveAlertCategory.deadlinePassed => 'En retard',
        ProactiveAlertCategory.objectivelyDelayed => 'Prend du retard',
        ProactiveAlertCategory.structuredConflict =>
          'Plusieurs choses en même temps',
        ProactiveAlertCategory.potentialOmission => 'Peut-être oublié',
        ProactiveAlertCategory.explicitReminder => 'Rappels demandés',
        ProactiveAlertCategory.pendingActionAttention => 'Actions à consulter',
        ProactiveAlertCategory.systemInformation => 'Informations utiles',
        ProactiveAlertCategory.dailySummary => 'Résumé de la journée',
      };

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
