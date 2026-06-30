import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/services/planning_proposal_engine.dart';

void main() {
  group('PlanningProposalEngine', () {
    test('returns diversified planning options across multiple days', () {
      final startDate = DateTime(2026, 7, 1);

      final result = PlanningProposalEngine.findBestOptionsFromEvents(
        startDate: startDate,
        totalMinutes: 60,
        events: <EventModel>[],
        reasoning: const [],
        searchDays: 7,
        maxOptions: 3,
      );

      expect(result.hasOptions, true);
      expect(result.options.length, 3);

      final uniqueDays = result.options.map((option) => option.dateIso).toSet();
      expect(uniqueDays.length, greaterThan(1));
    });

    test('returns no options for invalid duration', () {
      final result = PlanningProposalEngine.findBestOptionsFromEvents(
        startDate: DateTime(2026, 7, 1),
        totalMinutes: 0,
        events: <EventModel>[],
        reasoning: const [],
      );

      expect(result.hasOptions, false);
      expect(result.options, isEmpty);
    });
  });
}
