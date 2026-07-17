import 'recurring_memory_schedule_service.dart';

class MemoryReasoningService {
  static List<Map<String, dynamic>> buildReasoning(
    List<Map<String, dynamic>> memories,
  ) {
    final reasoning = <Map<String, dynamic>>[];

    for (final memory in memories) {
      final text = memory["text"]?.toString().trim() ?? "";
      final lower = text.toLowerCase();

      if (text.isEmpty) continue;

      if (_containsAny(lower, [
        "je travaille de nuit",
        "travail de nuit",
        "horaires de nuit",
        "poste de nuit",
      ])) {
        reasoning.add({
          "type": "schedule_constraint",
          "scheduleMode": "night",
          "avoidMorning": true,
          "source": text,
        });
      } else if (_containsAny(lower, [
        "je travaille le soir",
        "travail le soir",
        "horaires du soir",
        "poste du soir",
        "je termine tard",
        "horaires tardifs",
      ])) {
        reasoning.add({
          "type": "schedule_constraint",
          "scheduleMode": "late",
          "avoidMorning": false,
          "source": text,
        });
      }

      if (_containsAny(lower, [
        "je préfère l'après-midi",
        "je prefere l'apres-midi",
        "je préfère les rendez-vous l'après-midi",
        "je prefere les rendez-vous l'apres-midi",
      ])) {
        reasoning.add({
          "type": "schedule_preference",
          "preferredPeriod": "afternoon",
          "source": text,
        });
      }

      if (_containsAny(lower, [
        "tous les lundis",
        "tous les mardis",
        "tous les mercredis",
        "tous les jeudis",
        "tous les vendredis",
        "tous les samedis",
        "tous les dimanches",
        "chaque semaine",
        "tous les jours ouvrés",
        "tous les jours ouvres",
        "tous les jours ouvrables",
        "chaque jour ouvré",
        "chaque jour ouvre",
        "chaque jour ouvrable",
        "du lundi au vendredi",
        "les jours de semaine",
      ])) {
        final category = memory["category"]?.toString().trim() ?? "personal";

        reasoning.add({
          "type": "routine",
          "category": category.isEmpty ? "personal" : category,
          "source": text,
        });

        final blockedPeriod = RecurringMemoryScheduleService.buildBlockedPeriod(
          text: text,
          category: category,
        );

        if (blockedPeriod != null) {
          reasoning.add(blockedPeriod);
        }
      }
    }

    return reasoning;
  }

  static bool _containsAny(String text, List<String> values) {
    return values.any(text.contains);
  }
}
