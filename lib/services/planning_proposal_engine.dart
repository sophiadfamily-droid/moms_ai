import '../models/event_model.dart';
import 'event_service.dart';
import 'planning_score_service.dart';
import 'planning_window_service.dart';
import 'smart_planning_service.dart';

class PlanningProposalOption {
  final DateTime start;
  final DateTime end;
  final int score;
  final String dateIso;
  final String startTime;
  final String endTime;
  final String label;

  const PlanningProposalOption({
    required this.start,
    required this.end,
    required this.score,
    required this.dateIso,
    required this.startTime,
    required this.endTime,
    required this.label,
  });

  Map<String, dynamic> toJson() {
    return {
      "dateIso": dateIso,
      "startTime": startTime,
      "endTime": endTime,
      "score": score,
      "label": label,
      "start": start.toIso8601String(),
      "end": end.toIso8601String(),
    };
  }
}

class PlanningProposalEngineResult {
  final bool hasOptions;
  final List<PlanningProposalOption> options;
  final String explanation;

  const PlanningProposalEngineResult({
    required this.hasOptions,
    required this.options,
    required this.explanation,
  });
}

class PlanningProposalEngine {
  static Future<PlanningProposalEngineResult> findBestOptions({
    required DateTime startDate,
    required int totalMinutes,
    required List<Map<String, dynamic>> reasoning,
    int searchDays = 21,
    int maxOptions = 3,
  }) async {
    final events = await EventService.getEvents();

    return findBestOptionsFromEvents(
      startDate: startDate,
      totalMinutes: totalMinutes,
      events: events,
      reasoning: reasoning,
      searchDays: searchDays,
      maxOptions: maxOptions,
    );
  }

  static PlanningProposalEngineResult findBestOptionsFromEvents({
    required DateTime startDate,
    required int totalMinutes,
    required List<EventModel> events,
    required List<Map<String, dynamic>> reasoning,
    int searchDays = 21,
    int maxOptions = 3,
  }) {
    if (totalMinutes <= 0) {
      return const PlanningProposalEngineResult(
        hasOptions: false,
        options: [],
        explanation: "La durée totale est invalide.",
      );
    }

    final allOptions = <PlanningProposalOption>[];

    for (var dayOffset = 0; dayOffset < searchDays; dayOffset++) {
      final targetDate = DateTime(
        startDate.year,
        startDate.month,
        startDate.day,
      ).add(Duration(days: dayOffset));

      allOptions.addAll(
        _findOptionsForDay(
          targetDate: targetDate,
          totalMinutes: totalMinutes,
          events: events,
          reasoning: reasoning,
        ),
      );
    }

    final uniqueOptions = _deduplicate(allOptions);
    final diversifiedOptions = _diversifyByDay(uniqueOptions, maxOptions);

    if (diversifiedOptions.isEmpty) {
      return PlanningProposalEngineResult(
        hasOptions: false,
        options: const [],
        explanation:
            "Je n’ai pas trouvé de créneau réaliste sur les $searchDays prochains jours.",
      );
    }

    return PlanningProposalEngineResult(
      hasOptions: true,
      options: diversifiedOptions,
      explanation: _buildExplanation(diversifiedOptions),
    );
  }

  static List<PlanningProposalOption> _findOptionsForDay({
    required DateTime targetDate,
    required int totalMinutes,
    required List<EventModel> events,
    required List<Map<String, dynamic>> reasoning,
  }) {
    final planningWindow = PlanningWindowService.build(reasoning: reasoning);

    final start = DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
      planningWindow.startHour,
    );

    final endLimit = DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
      planningWindow.endHour,
    );

    final options = <PlanningProposalOption>[];
    var cursor = start;

    while (!cursor.add(Duration(minutes: totalMinutes)).isAfter(endLimit)) {
      final slotEnd = cursor.add(Duration(minutes: totalMinutes));

      final hasEventConflict = SmartPlanningService.overlapsExistingEvent(
        start: cursor,
        end: slotEnd,
        events: events,
      );

      final hasFamilyConflict = SmartPlanningService.isBusyBecauseFamilyRoutine(
        cursor,
        slotEnd,
      );

      final hasReasoningConflict =
          SmartPlanningService.overlapsBlockedReasoning(
        start: cursor,
        end: slotEnd,
        reasoning: reasoning,
      );

      if (!hasEventConflict && !hasFamilyConflict && !hasReasoningConflict) {
        final score = PlanningScoreService.scoreSlot(
          start: cursor,
          end: slotEnd,
          events: events,
          reasoning: reasoning,
          preferredStartHour: planningWindow.preferredStartHour,
          preferredEndHour: planningWindow.preferredEndHour,
        );

        options.add(
          PlanningProposalOption(
            start: cursor,
            end: slotEnd,
            score: score,
            dateIso: SmartPlanningService.formatIsoDate(cursor),
            startTime: SmartPlanningService.formatIsoTime(cursor),
            endTime: SmartPlanningService.formatIsoTime(slotEnd),
            label: _humanOptionLabel(cursor, slotEnd),
          ),
        );
      }

      cursor = cursor.add(const Duration(minutes: 15));
    }

    options.sort((a, b) {
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) return scoreCompare;
      return a.start.compareTo(b.start);
    });

    return options.take(12).toList();
  }

  static List<PlanningProposalOption> _deduplicate(
    List<PlanningProposalOption> options,
  ) {
    final seen = <String>{};
    final result = <PlanningProposalOption>[];

    for (final option in options) {
      final key = "${option.dateIso}-${option.startTime}-${option.endTime}";
      if (seen.contains(key)) continue;

      seen.add(key);
      result.add(option);
    }

    result.sort((a, b) {
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) return scoreCompare;
      return a.start.compareTo(b.start);
    });

    return result;
  }

  static List<PlanningProposalOption> _diversifyByDay(
    List<PlanningProposalOption> options,
    int maxOptions,
  ) {
    final result = <PlanningProposalOption>[];
    final usedDays = <String>{};

    for (final option in options) {
      if (usedDays.contains(option.dateIso)) continue;

      result.add(option);
      usedDays.add(option.dateIso);

      if (result.length >= maxOptions) return result;
    }

    for (final option in options) {
      final alreadySelected = result.any((selected) {
        return selected.dateIso == option.dateIso &&
            selected.startTime == option.startTime &&
            selected.endTime == option.endTime;
      });

      if (alreadySelected) continue;

      result.add(option);

      if (result.length >= maxOptions) return result;
    }

    return result;
  }

  static String _buildExplanation(List<PlanningProposalOption> options) {
    final lines = <String>[
      "J’ai trouvé ${options.length} créneau(x) possible(s) :",
    ];

    for (var index = 0; index < options.length; index++) {
      final option = options[index];
      lines.add("${index + 1}. ${option.label}");
    }

    return lines.join("\n");
  }

  static String _humanOptionLabel(DateTime start, DateTime end) {
    final dateLabel = SmartPlanningService.humanDateLabel(start);
    final startTime = SmartPlanningService.formatIsoTime(start);
    final endTime = SmartPlanningService.formatIsoTime(end);

    return "$dateLabel de $startTime à $endTime";
  }
}
