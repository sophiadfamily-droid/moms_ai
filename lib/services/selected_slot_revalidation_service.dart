import '../models/event_model.dart';
import 'planning_proposal_engine.dart';
import 'smart_planning_service.dart';

typedef SelectedSlotConflictChecker = Future<EventModel?> Function({
  required EventModel candidate,
});

typedef SelectedSlotAlternativeFinder = Future<PlanningProposalEngineResult>
    Function({
  required DateTime startDate,
  required int totalMinutes,
  required List<Map<String, dynamic>> reasoning,
  int searchDays,
  int maxOptions,
});

class SelectedSlotRevalidationResult {
  final bool isAvailable;
  final EventModel? conflictEvent;
  final PlanningProposalEngineResult alternatives;

  const SelectedSlotRevalidationResult({
    required this.isAvailable,
    required this.conflictEvent,
    required this.alternatives,
  });
}

class SelectedSlotRevalidationService {
  static Future<SelectedSlotRevalidationResult> revalidate({
    required EventModel candidate,
    required DateTime protectedStart,
    required int totalMinutes,
    required List<Map<String, dynamic>> reasoning,
    required SelectedSlotConflictChecker conflictChecker,
    required SelectedSlotAlternativeFinder alternativeFinder,
    int searchDays = 21,
    int maxOptions = 3,
  }) async {
    final conflictEvent = await conflictChecker(candidate: candidate);

    final reasoningConflict = SmartPlanningService.overlapsBlockedReasoning(
      start: protectedStart,
      end: protectedStart.add(Duration(minutes: totalMinutes)),
      reasoning: reasoning,
    );

    if (conflictEvent == null && !reasoningConflict) {
      return const SelectedSlotRevalidationResult(
        isAvailable: true,
        conflictEvent: null,
        alternatives: PlanningProposalEngineResult(
          hasOptions: false,
          options: [],
          explanation: '',
        ),
      );
    }

    if (totalMinutes <= 0) {
      return SelectedSlotRevalidationResult(
        isAvailable: false,
        conflictEvent: conflictEvent,
        alternatives: const PlanningProposalEngineResult(
          hasOptions: false,
          options: [],
          explanation: 'La durée totale est invalide.',
        ),
      );
    }

    final alternatives = await alternativeFinder(
      startDate: protectedStart,
      totalMinutes: totalMinutes,
      reasoning: reasoning,
      searchDays: searchDays,
      maxOptions: maxOptions,
    );

    return SelectedSlotRevalidationResult(
      isAvailable: false,
      conflictEvent: conflictEvent,
      alternatives: alternatives,
    );
  }
}
