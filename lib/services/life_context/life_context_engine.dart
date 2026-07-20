import '../../models/life_context/life_context_snapshot.dart';
import '../../models/user_profile.dart';
import 'user_profile_life_context_mapper.dart';

typedef LifeContextProfileProjection = LifeContextSnapshot Function({
  required UserProfile profile,
  required DateTime generatedAt,
});

/// Read-only Life Context entry point.
///
/// V1 projects profile facts only. Memory, planning, and conversation
/// projections belong at this aggregation boundary once each source has a
/// concrete typed contract; they are intentionally not represented by unused
/// dependencies before then.
final class LifeContextEngine {
  final LifeContextProfileProjection _profileProjection;

  LifeContextEngine({LifeContextProfileProjection? profileProjection})
      : _profileProjection =
            profileProjection ?? const UserProfileLifeContextMapper().map;

  LifeContextSnapshot buildSnapshot({
    required UserProfile profile,
    required DateTime generatedAt,
  }) {
    return _profileProjection(profile: profile, generatedAt: generatedAt);
  }
}
