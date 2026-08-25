import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Smart Planning cannot rebuild a decision from a separate Agenda read',
      () {
    final smartPlanning =
        File('lib/services/smart_planning_service.dart').readAsStringSync();
    final proposal =
        File('lib/services/planning_proposal_service.dart').readAsStringSync();
    final proposalEngine =
        File('lib/services/planning_proposal_engine.dart').readAsStringSync();
    final production = File(
      'lib/services/smart_planning_continuation_coordinator.dart',
    ).readAsStringSync();

    expect(smartPlanning, isNot(contains('await EventService.getEvents()')));
    expect(smartPlanning, isNot(contains('TaskService.')));
    expect(proposalEngine, isNot(contains('EventService.getEvents()')));
    expect(
      smartPlanning,
      contains('required List<EventModel> contextEvents'),
    );
    expect(proposal, contains('required List<EventModel> contextEvents'));
    expect(production, contains('final input = await _planningInput()'));
    expect(production, contains('contextEvents: input.events'));
    expect(production, contains('allTasks: input.tasks'));
  });

  test('cross-domain suggestion engines use canonical Life Context production',
      () {
    final priority = File(
      'lib/services/priority/proactive_priority_production.dart',
    ).readAsStringSync();
    final anticipation = File(
      'lib/services/mental_load_anticipation_production.dart',
    ).readAsStringSync();

    expect(priority, contains('LifeContextProductionFactory.production'));
    expect(priority, contains('getCurrentProjection'));
    expect(anticipation, contains('LifeContextProductionFactory.production'));
    expect(anticipation, contains('production.refreshIfNeeded()'));
    expect(priority, isNot(contains('TaskService.')));
    expect(priority, isNot(contains('EventService.')));
    expect(anticipation, isNot(contains('TaskService.')));
    expect(anticipation, isNot(contains('EventService.')));
  });

  test('proactive Event conflicts use the same canonical snapshot', () {
    final production = File('lib/services/proactive_detection_production.dart')
        .readAsStringSync();
    final engine = File(
      'lib/services/life_context/event_life_context_conflict_engine.dart',
    ).readAsStringSync();

    expect(production, contains('snapshot: snapshot'));
    expect(production, contains('snapshot.eventDomain!'));
    expect(production, isNot(contains('EventService.')));
    expect(engine, contains('eventSection.events'));
    expect(engine, isNot(contains('EventService.')));
    expect(engine, isNot(contains('getEvents')));
  });
}
