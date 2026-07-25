import 'recurring_memory_schedule_service.dart';
import '../models/life_context/memory_context.dart';
import 'life_context/life_context_memory_projection.dart';
import 'life_context/life_context_memory_serializer.dart';
import 'memory_consumption_policy.dart';

class MemoryReasoningService {
  static List<Map<String, dynamic>> buildReasoning(
    List<Map<String, dynamic>> memories, {
    required DateTime referenceDate,
  }) {
    final context = const HistoricalMemoryContextProjection().project(memories);
    return buildReasoningFromContext(
      context,
      referenceDate: referenceDate,
    );
  }

  static List<Map<String, dynamic>> buildReasoningFromContext(
    MemoryContext context, {
    required DateTime referenceDate,
  }) {
    final reasoning = <Map<String, dynamic>>[];

    for (final fact in MemoryConsumptionPolicy.consumable(
      context.memories,
      referenceDate: referenceDate,
    )) {
      final memory = LifeContextMemorySerializer.toPlanningMap(fact);
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
        "une semaine sur deux",
        "toutes les deux semaines",
        "tous les quinze jours",
        "tous les 15 jours",
        "un lundi sur deux",
        "un mardi sur deux",
        "un mercredi sur deux",
        "un jeudi sur deux",
        "un vendredi sur deux",
        "un samedi sur deux",
        "un dimanche sur deux",
      ])) {
        final category = memory["category"]?.toString().trim() ?? "personal";
        final referenceDate = _readReferenceDate(
          memory["createdAt"] ?? memory["createdAtIso"],
        );

        reasoning.add({
          "type": "routine",
          "category": category.isEmpty ? "personal" : category,
          "source": text,
        });

        final blockedPeriod = RecurringMemoryScheduleService.buildBlockedPeriod(
          text: text,
          category: category,
          referenceDate: referenceDate,
        );

        if (blockedPeriod != null) {
          reasoning.add(blockedPeriod);
        }
      }
    }

    return reasoning;
  }

  static DateTime? _readReferenceDate(dynamic value) {
    if (value is DateTime) {
      return value;
    }

    if (value is String) {
      return DateTime.tryParse(value);
    }

    if (value == null) {
      return null;
    }

    try {
      final converted = value.toDate();

      if (converted is DateTime) {
        return converted;
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  static bool _containsAny(String text, List<String> values) {
    return values.any(text.contains);
  }
}
