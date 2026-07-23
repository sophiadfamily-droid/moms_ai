import '../models/user_profile.dart';
import 'life_context/life_context_engine.dart';
import 'life_context/life_context_memory_serializer.dart';
import 'memory_reasoning_service.dart';
import 'memory_service.dart';
import 'profile_reasoning_service.dart';

typedef LegacyMemoryLoader = Future<List<Map<String, dynamic>>> Function();

/// Transitional boundary for the legacy planning reasoning contract.
///
/// Free-form memories are excluded by [LifeContextMemorySerializer]. Only
/// legacy recurring routines remain until their structured Routine migration.
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
    );

    return [
      ...ProfileReasoningService.buildReasoningFromSnapshot(snapshot),
      ...MemoryReasoningService.buildReasoningFromContext(planningMemory),
    ];
  }
}
