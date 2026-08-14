import '../models/user_profile.dart';
import 'life_context/life_context_engine.dart';
import 'life_context/life_context_memory_serializer.dart';
import 'memory_reasoning_service.dart';
import 'memory_service.dart';
import 'profile_reasoning_service.dart';
import 'life_context/life_context_production.dart';

typedef LegacyMemoryLoader = Future<List<Map<String, dynamic>>> Function();

/// Transitional boundary for the legacy planning reasoning contract.
///
/// Free-form memories never become arbitrary Planning instructions. Confirmed
/// appointment preferences may provide a soft ranking signal, while legacy
/// recurring routines remain until their structured Routine migration.
final class MemoryPlanningCompatibilityService {
  const MemoryPlanningCompatibilityService._();

  static Future<List<Map<String, dynamic>>> build({
    required UserProfile profile,
    LegacyMemoryLoader? loadMemories,
    DateTime? generatedAt,
  }) async {
    final memories = await (loadMemories ?? MemoryService.getMemories).call();
    final snapshot = LifeContextEngine().buildSnapshot(
      profile: profile,
      generatedAt: generatedAt ?? DateTime.now(),
      memories: memories,
    );
    final planningMemory = LifeContextMemorySerializer.selectForPlanning(
      snapshot.memory,
      referenceDate: snapshot.generatedAt,
    );

    return [
      ...ProfileReasoningService.buildReasoningFromSnapshot(snapshot),
      ...MemoryReasoningService.buildReasoningFromContext(
        planningMemory,
        referenceDate: snapshot.generatedAt,
      ),
    ];
  }

  static Future<List<Map<String, dynamic>>> buildFromLifeContext({
    required LifeContextProduction production,
    DateTime? referenceDate,
  }) async {
    final snapshot = await production.refreshIfNeeded();
    final MemoryReasoningContext context;
    try {
      context = await MemoryReasoningService.loadFromProduction(
        production: production,
        referenceDate: referenceDate ?? snapshot.generatedAt,
      );
    } on MemoryReasoningContextException {
      // Memory is optional for Planning. A blocked Memory capability cannot
      // become an empty fact source for Memory reasoning, but it must not
      // prevent Event + Routine availability from being evaluated.
      return const [];
    }
    return MemoryReasoningService.buildReasoningFromLifeContext(
      context,
      referenceDate: referenceDate ?? snapshot.generatedAt,
      recurringRoutinesOnly: false,
      // Planning already receives structured Human constraints. Do not revive
      // broad free-text work constraints through this compatibility bridge.
      includeScheduleConstraints: false,
    );
  }
}
