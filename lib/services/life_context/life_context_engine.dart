import '../../models/life_context/life_context_snapshot.dart';
import '../../models/user_profile.dart';
import 'life_context_memory_projection.dart';
import 'user_profile_life_context_mapper.dart';

typedef LifeContextProfileProjection = LifeContextSnapshot Function({
  required UserProfile profile,
  required DateTime generatedAt,
});

/// Read-only Life Context entry point.
///
/// Composes profile facts and normalized historical memories without owning
/// either source or persisting the resulting snapshot.
final class LifeContextEngine {
  final LifeContextProfileProjection _profileProjection;
  final LifeContextMemoryProjection _memoryProjection;

  LifeContextEngine({
    LifeContextProfileProjection? profileProjection,
    LifeContextMemoryProjection? memoryProjection,
  })  : _memoryProjection =
            memoryProjection ?? const HistoricalMemoryContextProjection(),
        _profileProjection =
            profileProjection ?? const UserProfileLifeContextMapper().map;

  LifeContextSnapshot buildSnapshot({
    required UserProfile profile,
    required DateTime generatedAt,
    Iterable<Map<String, dynamic>> memories = const [],
  }) {
    final profileSnapshot =
        _profileProjection(profile: profile, generatedAt: generatedAt);
    if (memories.isEmpty) return profileSnapshot;
    return profileSnapshot.withMemory(_memoryProjection.project(memories));
  }
}
