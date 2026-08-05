import 'package:flutter/material.dart';

import '../models/proactive_notification_policy.dart';
import '../services/daily_summary_view_service.dart';
import '../services/notification_service.dart';
import '../services/auth_service.dart';
import 'calendar_screen.dart';
import 'tasks_screen.dart';

final class DailySummaryScreen extends StatelessWidget {
  const DailySummaryScreen({
    super.key,
    this.loader,
    this.onOpenAgenda,
    this.onOpenTasks,
  });

  final Future<DailySummaryViewData?> Function()? loader;
  final ValueChanged<DateTime?>? onOpenAgenda;
  final VoidCallback? onOpenTasks;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Résumé quotidien')),
        body: SafeArea(
          child: FutureBuilder<DailySummaryViewData?>(
            future: (loader ?? NotificationService.loadDailySummary)(),
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
                      subtitle: const Text('Voir dans l’Agenda'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _openCategory(
                        context,
                        ProactiveAlertCategory.structuredConflict,
                        conflict.targetDate,
                      ),
                    ),
                  for (final entry in data.categoryCounts.entries.where(
                    (entry) =>
                        entry.key !=
                            ProactiveAlertCategory.structuredConflict ||
                        data.conflicts.isEmpty,
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
      if (onOpenAgenda != null) {
        onOpenAgenda!(targetDate);
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CalendarScreen(
            accountScopeToken: AuthService.currentUserId ?? 'guest',
            initialDate: targetDate,
          ),
        ),
      );
      return;
    }
    if (onOpenTasks != null) {
      onOpenTasks!();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const TasksScreen()),
    );
  }
}
