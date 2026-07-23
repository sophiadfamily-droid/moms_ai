import '../../models/life_context/life_context_projection.dart';
import '../../models/life_context/memory_context.dart';

/// The single M.1 boundary serializer for backend memory maps.
abstract final class MemoryProjectionBackendSerializer {
  static List<Map<String, dynamic>> serializeProjection(
    LifeContextProjectionSection section,
  ) {
    if (section.type != LifeContextProjectionSectionType.memory) {
      throw const LifeContextProjectionException(
        'memory_projection_section_required',
      );
    }
    return section.items.map((item) {
      final facts = {
        for (final fact in item.facts) fact.key: fact.value,
      };
      return <String, dynamic>{
        'text': facts[LifeContextProjectionFactKeys.title]!,
        'category': facts[LifeContextProjectionFactKeys.category] ?? 'personal',
        'importance': 0,
        'confirmationStatus': item.confirmation.name,
        'source': 'lifeContextProjection',
      };
    }).toList(growable: false);
  }

  /// Compatibility input for an already-filtered historical selection.
  ///
  /// It deliberately accepts neither a repository nor a complete context.
  static List<Map<String, dynamic>> serializeLegacySelection(
    Iterable<LifeMemoryFact> memories,
  ) =>
      memories
          .map(
            (memory) => <String, dynamic>{
              'text': memory.text,
              'category':
                  memory.category.isEmpty ? 'personal' : memory.category,
              'importance': memory.importance,
              if (memory.createdAt != null)
                'createdAtIso': memory.createdAt!.toIso8601String(),
            },
          )
          .toList(growable: false);
}
