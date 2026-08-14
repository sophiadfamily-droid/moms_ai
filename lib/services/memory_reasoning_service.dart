import 'dart:collection';

import 'recurring_memory_schedule_service.dart';
import '../models/life_context/life_context_domains.dart';
import '../models/life_context/life_context_health_snapshot.dart';
import '../models/life_context/memory_context.dart';
import 'life_context/life_context_production.dart';
import 'app_diagnostics.dart';
import 'life_context/life_context_memory_projection.dart';
import 'life_context/life_context_memory_serializer.dart';
import 'memory_consumption_policy.dart';

final class MemoryReasoningContext {
  MemoryReasoningContext({
    required List<MemoryContextItem> memories,
    required this.sourceGeneration,
    required this.sourceRevision,
    required this.freshness,
    required List<String> warningCodes,
  })  : memories = UnmodifiableListView(memories),
        warningCodes = UnmodifiableListView(warningCodes);

  final List<MemoryContextItem> memories;
  final int sourceGeneration;
  final int? sourceRevision;
  final LifeContextFreshness freshness;
  final List<String> warningCodes;
}

final class MemoryReasoningContextException implements Exception {
  const MemoryReasoningContextException(this.code, this.compatibility);

  final String code;
  final LifeContextCapabilityCompatibility compatibility;
}

class MemoryReasoningService {
  static Future<MemoryReasoningContext> loadFromProduction({
    required LifeContextProduction production,
    DateTime? referenceDate,
    Set<LifeContextDomain> additionalRequiredDomains = const {},
  }) async {
    final snapshot = await production.refreshIfNeeded();
    final compatibility = production.compatibility(
      LifeContextCapability.memoryReasoning,
      additionalRequiredDomains: additionalRequiredDomains,
    );
    if (!compatibility.isUsable) {
      AppDiagnostics.record(
        component: 'life_context_consumer',
        domain: 'memory_reasoning',
        operation: 'resolve_capability',
        step: 'resolve_capability',
        code: AppErrorCode.dependencyUnavailable,
        technicalStatus: 'memory-section-unavailable',
        metadata: {
          'sessionGeneration': compatibility.sourceGeneration,
          'count': compatibility.blockingDomains.length,
        },
      );
      throw MemoryReasoningContextException(
        'memory_reasoning_context_incompatible',
        compatibility,
      );
    }
    return contextFromLifeContext(
      section: snapshot.memoryDomain!,
      sourceGeneration: compatibility.sourceGeneration,
      referenceDate: referenceDate ?? snapshot.generatedAt,
    );
  }

  static MemoryReasoningContext contextFromLifeContext({
    required MemoryDomainSection section,
    required int sourceGeneration,
    required DateTime referenceDate,
  }) {
    final memories = section.memories.where((memory) {
      if (memory.confirmation != 'confirmed' ||
          !const {'confirmed', 'active'}.contains(memory.status) ||
          memory.isExplicitHealth) {
        return false;
      }
      final validUntil = memory.validUntil;
      return validUntil == null ||
          referenceDate.toUtc().isBefore(validUntil.toUtc());
    }).toList()
      ..sort((first, second) {
        final importance = second.importance.compareTo(first.importance);
        return importance != 0 ? importance : first.id.compareTo(second.id);
      });
    return MemoryReasoningContext(
      memories: memories,
      sourceGeneration: sourceGeneration,
      sourceRevision: section.metadata.sourceRevision,
      freshness: section.metadata.freshness,
      warningCodes: section.metadata.warningCodes,
    );
  }

  static List<Map<String, dynamic>> buildReasoningFromLifeContext(
    MemoryReasoningContext context, {
    required DateTime referenceDate,
    bool recurringRoutinesOnly = false,
    bool includeScheduleConstraints = true,
  }) =>
      _buildReasoningFromMaps(
        context.memories.map(
          (memory) => {
            'text': memory.text,
            'category': memory.category,
            'importance': memory.importance,
            'semanticType': memory.semanticType,
            if (memory.semanticIdentityKey != null)
              'semanticIdentityKey': memory.semanticIdentityKey,
            if (memory.semanticValue != null)
              'semanticValue': memory.semanticValue,
            if (memory.createdAt != null)
              'createdAtIso': memory.createdAt!.toIso8601String(),
          },
        ),
        recurringRoutinesOnly: recurringRoutinesOnly,
        includeScheduleConstraints: includeScheduleConstraints,
      );

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
    return _buildReasoningFromMaps(
      MemoryConsumptionPolicy.consumable(
        context.memories,
        referenceDate: referenceDate,
      ).map(LifeContextMemorySerializer.toPlanningMap),
    );
  }

  static List<Map<String, dynamic>> _buildReasoningFromMaps(
    Iterable<Map<String, dynamic>> memories, {
    bool recurringRoutinesOnly = false,
    bool includeScheduleConstraints = true,
  }) {
    final reasoning = <Map<String, dynamic>>[];

    for (final memory in memories) {
      final text = memory["text"]?.toString().trim() ?? "";
      final lower = text.toLowerCase();

      if (text.isEmpty) continue;

      if (!recurringRoutinesOnly &&
          includeScheduleConstraints &&
          _containsAny(lower, [
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
      } else if (!recurringRoutinesOnly &&
          includeScheduleConstraints &&
          _containsAny(lower, [
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

      final preferredAppointmentPeriod = recurringRoutinesOnly
          ? null
          : _preferredAppointmentPeriod(memory, lower);
      if (preferredAppointmentPeriod != null) {
        reasoning.add({
          "type": "schedule_preference",
          "preferredPeriod": preferredAppointmentPeriod,
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
        if (memory['semanticType'] != null &&
            memory['semanticType'] != 'routine') {
          continue;
        }
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

  static String? _preferredAppointmentPeriod(
    Map<String, dynamic> memory,
    String normalizedText,
  ) {
    final semanticType =
        memory['semanticType']?.toString().trim().toLowerCase() ?? '';
    if (semanticType != LifeMemorySemanticType.preference.name) return null;

    final identityKey =
        memory['semanticIdentityKey']?.toString().trim().toLowerCase() ?? '';
    final hasClosedAppointmentIdentity =
        identityKey.contains('|preferred_appointment_period|');
    final isExplicitAppointmentPreference = _containsAny(normalizedText, const [
          'rendez-vous',
          'rendez vous',
          'rdv',
        ]) &&
        _containsAny(normalizedText, const [
          'je préfère',
          'je prefere',
        ]);
    if (!hasClosedAppointmentIdentity && !isExplicitAppointmentPreference) {
      return null;
    }

    final semanticValue =
        memory['semanticValue']?.toString().trim().toLowerCase() ?? '';
    final structured = _canonicalPreferredPeriod(semanticValue);
    if (structured != null) return structured;
    return _preferredPeriodFromText(normalizedText);
  }

  static String? _canonicalPreferredPeriod(String value) {
    return switch (value) {
      'morning' || 'matin' => 'morning',
      'afternoon' || 'après-midi' || 'apres-midi' => 'afternoon',
      'evening' || 'soir' || 'soirée' || 'soiree' => 'evening',
      _ => null,
    };
  }

  static String? _preferredPeriodFromText(String text) {
    if (_containsAny(text, const ['matin', 'matinée', 'matinee'])) {
      return 'morning';
    }
    if (_containsAny(text, const [
      'après-midi',
      'apres-midi',
      'après midi',
      'apres midi',
    ])) {
      return 'afternoon';
    }
    if (_containsAny(text, const ['soir', 'soirée', 'soiree'])) {
      return 'evening';
    }
    return null;
  }
}
