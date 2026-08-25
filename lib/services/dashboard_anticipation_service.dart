import '../models/agenda_focus.dart';
import '../models/life_context/life_context_projection.dart';
import 'daily_summary_view_service.dart';
import 'dashboard_anticipation_engine.dart';
import 'life_context_production_factory.dart';
import 'mental_load_anticipation_suggestion_service.dart';

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
    this.preparedChatMessage,
  });

  final String title;
  final String message;
  final DashboardAnticipationDestination destination;
  final String? sourceId;
  final AgendaFocus? agendaFocus;
  final String? preparedChatMessage;
}

typedef DashboardMentalLoadLoader
    = Future<List<MentalLoadAnticipationSuggestion>> Function();
typedef DashboardLifeContextLoader = Future<LifeContextProjection> Function();

/// Read-only home projection of Zelia's proven cross-domain anticipations.
///
/// This service does not create a second priority formula. Confirmed conflicts
/// come from the daily-summary detection registry and preparation thoughts come
/// from the existing mental-load engine. A standalone Task, Event or Shopping
/// item stays on its own screen instead of taking over the home suggestion.
final class DashboardAnticipationService {
  const DashboardAnticipationService({
    required DashboardMentalLoadLoader loadMentalLoadAnticipations,
    DashboardLifeContextLoader? loadLifeContext,
    DashboardAnticipationEngine engine = const DashboardAnticipationEngine(),
  })  : _loadMentalLoadAnticipations = loadMentalLoadAnticipations,
        _loadLifeContext = loadLifeContext,
        _engine = engine;

  final DashboardMentalLoadLoader _loadMentalLoadAnticipations;
  final DashboardLifeContextLoader? _loadLifeContext;
  final DashboardAnticipationEngine _engine;

  Future<DashboardAnticipation> evaluate({
    required String accountScopeId,
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

    try {
      final anticipations = await _loadMentalLoadAnticipations();
      final anticipation = anticipations
          .where(
            (item) =>
                accountScopeId.trim().isNotEmpty &&
                item.anticipation.accountScopeId == accountScopeId.trim(),
          )
          .firstOrNull;
      if (anticipation != null) {
        final presentation = anticipation.presentation;
        return DashboardAnticipation(
          title: presentation.title,
          message: presentation.message,
          destination: DashboardAnticipationDestination.task,
          sourceId: anticipation.anticipation.preparationSourceId,
        );
      }
    } on Object {
      // The home remains useful when cross-domain context is unavailable.
    }

    try {
      final loader = _loadLifeContext ??
          () async {
            final production = await LifeContextProductionFactory.production();
            return production.getCurrentProjection(
              LifeContextConsumerPurpose.dashboardAnticipation,
            );
          };
      final projection = await loader();
      if (projection.accountScopeId == accountScopeId.trim()) {
        final insight = _engine.evaluate(projection);
        return DashboardAnticipation(
          title: insight.title,
          message: insight.message,
          destination: DashboardAnticipationDestination.chat,
          sourceId: insight.sourceId,
          preparedChatMessage: insight.preparedChatMessage,
        );
      }
    } on Object {
      // A partial/offline profile must not make the Dashboard unusable.
    }

    return const DashboardAnticipation(
      title: 'Tu peux souffler',
      message: 'Rien ne presse pour le moment.',
      destination: DashboardAnticipationDestination.chat,
    );
  }
}
