import 'package:flutter/material.dart';

import '../models/proactive_notification_policy.dart';
import '../models/agenda_focus.dart';
import '../services/daily_summary_view_service.dart';
import '../services/notification_service.dart';
import '../services/auth_service.dart';
import '../services/proactive_detection_lifecycle.dart';
import 'calendar_screen.dart';
import 'tasks_screen.dart';

final class DailySummaryScreen extends StatelessWidget {
  const DailySummaryScreen({
    super.key,
    this.loader,
    this.onOpenAgenda,
    this.onOpenTasks,
    this.onOpenTask,
  });

  final Future<DailySummaryViewData?> Function()? loader;
  final ValueChanged<AgendaFocus>? onOpenAgenda;
  final VoidCallback? onOpenTasks;
  final ValueChanged<String>? onOpenTask;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Résumé quotidien')),
        body: SafeArea(
          child: FutureBuilder<DailySummaryViewData?>(
            future: _loadCurrentSummary(),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final data = snapshot.data;
              if (snapshot.hasError || data == null) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Tu n’as rien à vérifier pour le moment.',
                    ),
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    _heading(data.localDate),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  if (data.hasStaleInformation)
                    const Text(
                      'Certaines informations ne sont pas disponibles ou '
                      'doivent être actualisées.',
                    ),
                  for (final conflict in data.conflicts)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_busy_outlined),
                      title: Text(
                        'Attention : ${conflict.eventTitle} et '
                        '${conflict.routineTitle} sont prévus en même temps.',
                      ),
                      subtitle: Text(
                        '${_when(conflict.targetDate)} • Voir dans l’Agenda',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _openAgenda(
                        context,
                        AgendaFocus(
                          date: conflict.targetDate,
                          eventId: conflict.eventId,
                          routineId: conflict.routineId,
                          eventTitle: conflict.eventTitle,
                          routineTitle: conflict.routineTitle,
                        ),
                      ),
                    ),
                  for (final task in data.tasks)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.task_alt_rounded),
                      title: Text(_taskLabel(task)),
                      subtitle: Text(
                        task.targetDate == null
                            ? 'Voir dans les Tâches'
                            : 'Échéance : ${_when(task.targetDate)} • '
                                'Voir dans les Tâches',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _openTask(context, task.taskId),
                    ),
                  for (final entry in data.categoryCounts.entries.where(
                    (entry) =>
                        (entry.key !=
                                ProactiveAlertCategory.structuredConflict ||
                            data.conflicts.isEmpty) &&
                        (!_taskCategory(entry.key) || data.tasks.isEmpty),
                  ))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.notifications_outlined),
                      title: Text(_label(entry.key, entry.value)),
                      subtitle: Text(_destinationLabel(entry.key)),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _openCategory(
                        context,
                        entry.key,
                        data.categoryTargetDates[entry.key],
                      ),
                    ),
                  if (data.omittedCount > 0)
                    Text(
                      '${data.omittedCount} élément(s) supplémentaire(s) '
                      'à vérifier ne sont pas affichés ici.',
                    ),
                  const SizedBox(height: 16),
                  const Text(
                    'Ouvre l’Agenda ou les Tâches pour voir les détails. '
                    'Zelia ne change rien sans ton accord.',
                  ),
                ],
              );
            },
          ),
        ),
      );

  Future<DailySummaryViewData?> _loadCurrentSummary() async {
    final injectedLoader = loader;
    if (injectedLoader != null) return injectedLoader();
    try {
      await NotificationService.evaluateDetections(
        DetectionEvaluationTrigger.explicitInternalRefresh,
      );
    } on Object {
      // The center can still show the last proven alerts when a live refresh
      // is temporarily unavailable.
    }
    return NotificationService.loadDailySummary();
  }

  static String _heading(String date) {
    final parsed = DateTime.tryParse(date);
    final today = DateTime.now();
    if (parsed != null &&
        parsed.year == today.year &&
        parsed.month == today.month &&
        parsed.day == today.day) {
      return 'Ce qui demande ton attention aujourd’hui';
    }
    if (parsed == null) return 'Ce qui demande ton attention';
    return 'Ce qui demande ton attention le '
        '${parsed.day.toString().padLeft(2, '0')}/'
        '${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
  }

  static String _label(ProactiveAlertCategory category, int count) =>
      switch (category) {
        ProactiveAlertCategory.deadlineApproaching => count == 1
            ? 'Une chose est à faire bientôt'
            : '$count choses sont à faire bientôt',
        ProactiveAlertCategory.deadlinePassed => count == 1
            ? 'Une chose est en retard'
            : '$count choses sont en retard',
        ProactiveAlertCategory.objectivelyDelayed => count == 1
            ? 'Une chose prend du retard'
            : '$count choses prennent du retard',
        ProactiveAlertCategory.structuredConflict => count == 1
            ? 'Deux choses sont prévues en même temps'
            : '$count moments où plusieurs choses se chevauchent',
        ProactiveAlertCategory.potentialOmission =>
          count == 1 ? 'Une chose est à vérifier' : '$count choses à vérifier',
        ProactiveAlertCategory.explicitReminder =>
          count == 1 ? 'Un rappel' : '$count rappels',
        ProactiveAlertCategory.pendingActionAttention => count == 1
            ? 'Une action attend ta réponse'
            : '$count actions attendent ta réponse',
        ProactiveAlertCategory.systemInformation =>
          count == 1 ? 'Une information utile' : '$count informations utiles',
        ProactiveAlertCategory.dailySummary => 'Ton résumé de la journée',
      };

  static bool _taskCategory(ProactiveAlertCategory category) => {
        ProactiveAlertCategory.deadlineApproaching,
        ProactiveAlertCategory.deadlinePassed,
        ProactiveAlertCategory.objectivelyDelayed,
      }.contains(category);

  static String _taskLabel(TaskAttentionViewData task) =>
      switch (task.category) {
        ProactiveAlertCategory.deadlinePassed =>
          'La tâche « ${task.taskTitle} » est en retard.',
        ProactiveAlertCategory.objectivelyDelayed =>
          'La tâche « ${task.taskTitle} » prend du retard.',
        _ => 'La tâche « ${task.taskTitle} » est à faire bientôt.',
      };

  static String _when(DateTime? value) {
    if (value == null) return 'Horaire à vérifier';
    final local = value.toLocal();
    const weekdays = [
      'lundi',
      'mardi',
      'mercredi',
      'jeudi',
      'vendredi',
      'samedi',
      'dimanche',
    ];
    const months = [
      'janvier',
      'février',
      'mars',
      'avril',
      'mai',
      'juin',
      'juillet',
      'août',
      'septembre',
      'octobre',
      'novembre',
      'décembre',
    ];
    final minutes =
        local.minute == 0 ? '' : ' ${local.minute.toString().padLeft(2, '0')}';
    return '${weekdays[local.weekday - 1]} ${local.day} '
        '${months[local.month - 1]} à ${local.hour} h$minutes';
  }

  static String _destinationLabel(ProactiveAlertCategory category) =>
      category == ProactiveAlertCategory.structuredConflict
          ? 'Voir dans l’Agenda'
          : 'Voir dans les Tâches';

  void _openCategory(
    BuildContext context,
    ProactiveAlertCategory category,
    DateTime? targetDate,
  ) {
    if (category == ProactiveAlertCategory.structuredConflict) {
      _openAgenda(context, AgendaFocus(date: targetDate));
      return;
    }
    _openTasks(context);
  }

  void _openTasks(BuildContext context) {
    if (onOpenTasks != null) {
      onOpenTasks!();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const TasksScreen()),
    );
  }

  void _openTask(BuildContext context, String taskId) {
    if (onOpenTask != null) {
      onOpenTask!(taskId);
      return;
    }
    _openTasks(context);
  }

  void _openAgenda(BuildContext context, AgendaFocus focus) {
    if (onOpenAgenda != null) {
      onOpenAgenda!(focus);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CalendarScreen(
          accountScopeToken: AuthService.currentUserId ?? 'guest',
          initialDate: focus.date,
          highlightedEventId: focus.eventId,
          highlightedRoutineId: focus.routineId,
        ),
      ),
    );
  }
}
