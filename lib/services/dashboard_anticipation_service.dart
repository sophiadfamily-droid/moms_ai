import '../models/agenda_focus.dart';
import '../models/event_model.dart';
import '../models/life_context/life_context_projection.dart';
import '../models/priority/priority_models.dart';
import '../models/priority/priority_suggestion_models.dart';
import '../models/proactive_notification_policy.dart';
import '../models/shopping_item_model.dart';
import '../models/task_model.dart';
import 'daily_summary_view_service.dart';
import 'priority/priority_candidate_adapter.dart';
import 'priority/priority_engine.dart';
import 'priority/priority_suggestion_builder.dart';

enum DashboardAnticipationDestination {
  none,
  agenda,
  task,
  shopping,
  attentionCenter,
  chat,
}

final class DashboardAnticipation {
  const DashboardAnticipation({
    required this.title,
    required this.message,
    required this.destination,
    this.sourceId,
    this.agendaFocus,
  });

  final String title;
  final String message;
  final DashboardAnticipationDestination destination;
  final String? sourceId;
  final AgendaFocus? agendaFocus;
}

typedef DashboardPriorityProjectionLoader = Future<LifeContextProjection>
    Function();

/// Read-only home projection of Zelia's existing canonical engines.
///
/// This service does not create a second priority formula. Confirmed attention
/// comes from the daily-summary detection registry and all remaining ranking
/// comes from the shared Priority engine. Raw domain objects are used only to
/// resolve human-readable labels and navigation targets.
final class DashboardAnticipationService {
  const DashboardAnticipationService({
    required DashboardPriorityProjectionLoader loadProjection,
    DateTime Function()? clock,
  })  : _loadProjection = loadProjection,
        _clock = clock;

  final DashboardPriorityProjectionLoader _loadProjection;
  final DateTime Function()? _clock;

  Future<DashboardAnticipation> evaluate({
    required String accountScopeId,
    required List<EventModel> events,
    required List<TaskModel> tasks,
    required List<ShoppingItemModel> shoppingItems,
    DailySummaryViewData? dailySummary,
  }) async {
    final conflict = dailySummary?.conflicts.firstOrNull;
    if (conflict != null) {
      return DashboardAnticipation(
        title: 'À regarder',
        message: '« ${conflict.eventTitle} » et '
            '« ${conflict.routineTitle} » sont prévus en même temps.',
        destination: DashboardAnticipationDestination.agenda,
        agendaFocus: AgendaFocus(
          date: conflict.targetDate,
          eventId: conflict.eventId,
          routineId: conflict.routineId,
          eventTitle: conflict.eventTitle,
          routineTitle: conflict.routineTitle,
        ),
      );
    }

    final taskAttention = _strongestTaskAttention(dailySummary?.tasks ?? []);
    if (taskAttention != null) {
      return DashboardAnticipation(
        title: 'À ne pas oublier',
        message: '« ${taskAttention.taskTitle} » demande ton attention.',
        destination: DashboardAnticipationDestination.task,
        sourceId: taskAttention.taskId,
      );
    }

    try {
      final projection = await _loadProjection();
      if (accountScopeId.trim().isNotEmpty &&
          projection.accountScopeId == accountScopeId.trim()) {
        final anticipation = _fromPriority(
          projection: projection,
          events: events,
          tasks: tasks,
        );
        if (anticipation != null) return anticipation;
      }
    } on Object {
      // The home remains useful when the shared context is temporarily absent.
    }

    return const DashboardAnticipation(
      title: 'Tu peux souffler',
      message: 'Rien ne presse pour le moment.',
      destination: DashboardAnticipationDestination.chat,
    );
  }

  TaskAttentionViewData? _strongestTaskAttention(
    List<TaskAttentionViewData> tasks,
  ) {
    if (tasks.isEmpty) return null;
    final ordered = [...tasks]..sort((left, right) {
        final category = _attentionWeight(right.category)
            .compareTo(_attentionWeight(left.category));
        if (category != 0) return category;
        final leftDate = left.targetDate;
        final rightDate = right.targetDate;
        if (leftDate == null && rightDate == null) {
          return left.taskId.compareTo(right.taskId);
        }
        if (leftDate == null) return 1;
        if (rightDate == null) return -1;
        return leftDate.compareTo(rightDate);
      });
    return ordered.first;
  }

  int _attentionWeight(ProactiveAlertCategory category) => switch (category) {
        ProactiveAlertCategory.objectivelyDelayed => 3,
        ProactiveAlertCategory.deadlinePassed => 2,
        ProactiveAlertCategory.deadlineApproaching => 1,
        _ => 0,
      };

  DashboardAnticipation? _fromPriority({
    required LifeContextProjection projection,
    required List<EventModel> events,
    required List<TaskModel> tasks,
  }) {
    final now = (_clock ?? DateTime.now)().toUtc();
    final candidates = const PriorityCandidateAdapter().fromProjection(
      projection,
      evaluatedAt: now,
    );
    final ranking = PriorityEngine().rank(
      candidates,
      evaluatedAt: now,
      expectedAccountScopeId: projection.accountScopeId,
    );
    final result = const PrioritySuggestionBuilder().build(
      ranking: ranking,
      accountScopeId: projection.accountScopeId,
      referenceDate: now,
      limit: PrioritySuggestionLimits.proactiveEvaluation,
    );
    if (result.suggestions.isEmpty) return null;
    final suggestion = result.suggestions.first;
    final ranked = ranking.items
        .where(
          (item) => item.candidate.id == suggestion.primaryCandidateId,
        )
        .firstOrNull;
    if (ranked == null) return null;
    final candidate = ranked.candidate;
    final sourceId = candidate.sourceId;

    if (candidate.sourceDomain == PrioritySourceDomain.task) {
      final task = tasks.where((item) => item.id == sourceId).firstOrNull;
      if (task == null || task.title.trim().isEmpty) return null;
      return DashboardAnticipation(
        title: _taskTitle(suggestion),
        message: _taskMessage(suggestion, task.title.trim()),
        destination: DashboardAnticipationDestination.task,
        sourceId: sourceId,
      );
    }

    if (candidate.sourceDomain == PrioritySourceDomain.event) {
      final event = events.where((item) => item.id == sourceId).firstOrNull;
      if (event == null || event.title.trim().isEmpty) return null;
      return DashboardAnticipation(
        title: 'À venir',
        message: '« ${event.title.trim()} » approche. '
            'Pense à vérifier que tout est prêt.',
        destination: DashboardAnticipationDestination.agenda,
        sourceId: sourceId,
        agendaFocus: AgendaFocus(
          date: DateTime.tryParse(event.startDateTimeIso),
          eventId: event.id,
          eventTitle: event.title,
        ),
      );
    }
    return null;
  }

  String _taskTitle(PrioritySuggestion suggestion) {
    if (suggestion.reasonCodes.contains(
      PrioritySuggestionReason.missingDeadlineBlocksAssessment,
    )) {
      return 'Pour ne pas l’oublier';
    }
    if (suggestion.reasonCodes.contains(
      PrioritySuggestionReason.missingDurationBlocksAssessment,
    )) {
      return 'Un détail à préciser';
    }
    if (suggestion.reasonCodes.contains(PrioritySuggestionReason.overdue) ||
        suggestion.reasonCodes.contains(
          PrioritySuggestionReason.staleOpenTask,
        )) {
      return 'Toujours à faire ?';
    }
    return 'À garder en tête';
  }

  String _taskMessage(PrioritySuggestion suggestion, String label) {
    if (suggestion.reasonCodes.contains(
      PrioritySuggestionReason.missingDeadlineBlocksAssessment,
    )) {
      return 'Tu dois faire « $label » avant quand ?';
    }
    if (suggestion.reasonCodes.contains(
      PrioritySuggestionReason.missingDurationBlocksAssessment,
    )) {
      return 'Combien de temps faut-il prévoir pour « $label » ?';
    }
    if (suggestion.reasonCodes.contains(PrioritySuggestionReason.overdue)) {
      return '« $label » a une ancienne date. C’est toujours à faire ?';
    }
    if (suggestion.reasonCodes.contains(
      PrioritySuggestionReason.staleOpenTask,
    )) {
      return '« $label » est dans ta liste depuis un moment.';
    }
    return 'Pense à « $label » dans les prochains jours.';
  }
}
