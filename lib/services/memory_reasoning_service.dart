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
        "je travaille le soir",
        "travail le soir",
      ])) {
        reasoning.add({
          "type": "schedule_constraint",
          "avoidMorning": true,
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
      ])) {
        reasoning.add({
          "type": "routine",
          "category": memory["category"]?.toString() ?? "personal",
          "source": text,
        });
      }
    }

    return reasoning;
  }

  static bool _containsAny(String text, List<String> values) {
    return values.any(text.contains);
  }
}
