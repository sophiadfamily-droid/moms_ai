import 'package:flutter/material.dart';

import '../models/proactive_notification_policy.dart';
import '../services/daily_summary_view_service.dart';
import '../services/notification_service.dart';

final class DailySummaryScreen extends StatelessWidget {
  const DailySummaryScreen({
    super.key,
    this.loader,
  });

  final Future<DailySummaryViewData?> Function()? loader;

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
                      'Aucune information structurée n’est disponible pour ce '
                      'résumé.',
                    ),
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    'Résumé du ${data.localDate}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  if (data.hasStaleInformation)
                    const Text(
                      'Certaines informations ne sont pas disponibles ou '
                      'doivent être actualisées.',
                    ),
                  for (final entry in data.categoryCounts.entries)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.notifications_outlined),
                      title: Text(_label(entry.key)),
                      trailing: Text('${entry.value}'),
                    ),
                  if (data.omittedCount > 0)
                    Text(
                      '${data.omittedCount} élément(s) supplémentaire(s) '
                      'n’ont pas été affiché(s) pour garder le résumé court.',
                    ),
                  const SizedBox(height: 16),
                  const Text(
                    'Ouvre Agenda ou Tâches pour consulter les informations '
                    'actuelles. Le résumé ne modifie rien.',
                  ),
                ],
              );
            },
          ),
        ),
      );

  static String _label(ProactiveAlertCategory category) => switch (category) {
        ProactiveAlertCategory.deadlineApproaching => 'Échéances proches',
        ProactiveAlertCategory.deadlinePassed => 'Échéances dépassées',
        ProactiveAlertCategory.objectivelyDelayed => 'Retards à vérifier',
        ProactiveAlertCategory.structuredConflict => 'Conflits structurés',
        ProactiveAlertCategory.potentialOmission =>
          'Éléments pouvant nécessiter ton attention',
        ProactiveAlertCategory.explicitReminder => 'Rappels demandés',
        ProactiveAlertCategory.pendingActionAttention => 'Actions à consulter',
        ProactiveAlertCategory.systemInformation => 'Informations système',
        ProactiveAlertCategory.dailySummary => 'Résumé quotidien',
      };
}
