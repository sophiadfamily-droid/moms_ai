import '../../models/life_context/memory_context.dart';
import '../memory_consumption_policy.dart';

final class LifeContextMemorySerializer {
  const LifeContextMemorySerializer._();

  static Map<String, dynamic> toPlanningMap(LifeMemoryFact memory) => {
        'text': memory.text,
        'category': memory.category.isEmpty ? 'personal' : memory.category,
        'importance': memory.importance,
        if (memory.createdAt != null)
          'createdAtIso': memory.createdAt!.toIso8601String(),
      };

  static MemoryContext selectForPlanning(
    MemoryContext context, {
    required DateTime referenceDate,
    int limit = 12,
  }) {
    if (limit <= 0 || context.isEmpty) return MemoryContext.empty;
    // Compatibility-only bridge: existing structured recurring memories keep
    // their planning behavior until Routine owns their migrated records.
    // Free preferences, facts and constraints never enter Planning from M.1.
    final indexed = MemoryConsumptionPolicy.consumable(
      context.memories,
      referenceDate: referenceDate,
    )
        .where(
          (memory) =>
              memory.semanticType == LifeMemorySemanticType.routine &&
              !memory.isExplicitHealth,
        )
        .indexed
        .toList()
      ..sort((first, second) {
        final importance = second.$2.importance.compareTo(first.$2.importance);
        return importance != 0 ? importance : first.$1.compareTo(second.$1);
      });
    return MemoryContext(
      memories: indexed.take(limit).map((entry) => entry.$2).toList(),
    );
  }
}
