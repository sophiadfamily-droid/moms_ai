import '../../models/life_context/memory_context.dart';

final class LifeContextMemorySerializer {
  const LifeContextMemorySerializer._();

  static Map<String, dynamic> toPlanningMap(LifeMemoryFact memory) => {
        'text': memory.text,
        'category': memory.category.isEmpty ? 'personal' : memory.category,
        'importance': memory.importance,
        if (memory.createdAt != null)
          'createdAtIso': memory.createdAt!.toIso8601String(),
      };

  static Map<String, dynamic> toBackendMap(LifeMemoryFact memory) => {
        'text': memory.text,
        'category': memory.category.isEmpty ? 'personal' : memory.category,
        'importance': memory.importance,
        if (memory.createdAt != null)
          'createdAtIso': memory.createdAt!.toIso8601String(),
      };

  static MemoryContext selectForPlanning(
    MemoryContext context, {
    int limit = 12,
  }) {
    if (limit <= 0 || context.isEmpty) return MemoryContext.empty;
    final indexed = context.memories.indexed.toList()
      ..sort((first, second) {
        final importance = second.$2.importance.compareTo(first.$2.importance);
        return importance != 0 ? importance : first.$1.compareTo(second.$1);
      });
    return MemoryContext(
      memories: indexed.take(limit).map((entry) => entry.$2).toList(),
    );
  }
}
