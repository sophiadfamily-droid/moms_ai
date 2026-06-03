import 'priority_rules_service.dart';
import 'time_priority_service.dart';

class PriorityEngineService {
  static String detectCategory(String text) {
    final lower = text.trim().toLowerCase();

    if (_containsAny(lower, PriorityRulesService.healthKeywords)) {
      return "health";
    }

    if (_containsAny(lower, PriorityRulesService.familyKeywords)) {
      return "family";
    }

    if (_containsAny(lower, PriorityRulesService.workKeywords)) {
      return "work";
    }

    if (_containsAny(lower, PriorityRulesService.financeKeywords)) {
      return "finance";
    }

    if (_containsAny(lower, PriorityRulesService.administrativeKeywords)) {
      return "administrative";
    }

    if (_containsAny(lower, [
      "courses",
      "acheter",
      "supermarché",
      "supermarche",
    ])) {
      return "shopping";
    }

    return "personal";
  }

  static int calculateScore(String text) {
    final lower = text.trim().toLowerCase();

    var score = 1;

    score += TimePriorityService.urgencyScore(text);

    if (_containsAny(lower, PriorityRulesService.healthKeywords)) {
      score += 3;
    }

    if (_containsAny(lower, PriorityRulesService.financeKeywords)) {
      score += 3;
    }

    if (_containsAny(lower, PriorityRulesService.familyKeywords)) {
      score += 2;
    }

    if (_containsAny(lower, PriorityRulesService.workKeywords)) {
      score += 2;
    }

    if (_containsAny(lower, PriorityRulesService.administrativeKeywords)) {
      score += 2;
    }

    return score.clamp(1, 10);
  }

  static String priorityLevel(int score) {
    if (score >= 9) return "critical";
    if (score >= 7) return "high";
    if (score >= 4) return "medium";
    return "low";
  }

  static Map<String, dynamic> analyze(String text) {
    final score = calculateScore(text);

    return {
      "category": detectCategory(text),
      "score": score,
      "priority": priorityLevel(score),
      "urgencyScore": TimePriorityService.urgencyScore(text),
    };
  }

  static bool _containsAny(String text, List<String> values) {
    return values.any(text.contains);
  }
}
