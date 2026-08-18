import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'life_context_production_factory.dart';
import 'life_context/life_context_relation_engine.dart';
import 'mental_load_anticipation_engine.dart';
import 'mental_load_anticipation_suggestion_service.dart';
import 'proactive_detection_life_context_adapter.dart';

abstract final class MentalLoadAnticipationProduction {
  static Future<List<MentalLoadAnticipationSuggestion>> load(
    String accountScopeId,
  ) async {
    final production = await LifeContextProductionFactory.production();
    production.handleAccountScopeChanged(accountScopeId);
    final snapshot = await production.refreshIfNeeded();
    final graph = production.currentGraph ??
        const LifeContextRelationEngine().build(snapshot);
    final input = const ProactiveDetectionLifeContextAdapter().adapt(
      snapshot: snapshot,
      graph: graph,
      confirmedConflicts: [],
      existingSignals: [],
      timezoneId: await _timezoneId(),
    );
    final anticipations = const MentalLoadAnticipationEngine().evaluate(
      input: input,
      policy: const MentalLoadAnticipationPolicy(),
      now: DateTime.now(),
    );
    final tasks = {
      for (final task in snapshot.taskDomain!.tasks) task.id: task.title,
    };
    final events = {
      for (final event in snapshot.eventDomain!.events) event.id: event.title,
    };
    return anticipations
        .where(
          (item) =>
              tasks[item.preparationSourceId]?.trim().isNotEmpty == true &&
              events[item.eventSourceId]?.trim().isNotEmpty == true,
        )
        .map(
          (item) => MentalLoadAnticipationSuggestion(
            anticipation: item,
            preparationLabel: tasks[item.preparationSourceId]!,
            eventLabel: events[item.eventSourceId]!,
          ),
        )
        .toList(growable: false);
  }

  static Future<String> _timezoneId() async {
    try {
      final identifier = (await FlutterTimezone.getLocalTimezone()).identifier;
      tz_data.initializeTimeZones();
      tz.getLocation(identifier);
      return identifier;
    } on Object {
      return 'Etc/UTC';
    }
  }
}
