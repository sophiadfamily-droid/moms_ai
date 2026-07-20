import 'entity_identity.dart';

final class EntityMatcher<T> {
  final String? Function(T entity) _idOf;
  final bool Function(T first, T second) _legacyEquals;

  const EntityMatcher({
    required String? Function(T entity) idOf,
    required bool Function(T first, T second) legacyEquals,
  })  : _idOf = idOf,
        _legacyEquals = legacyEquals;

  bool matches(T first, T second) {
    final firstId = _idOf(first);
    final secondId = _idOf(second);

    if (EntityIdentity.isValid(firstId) && EntityIdentity.isValid(secondId)) {
      return firstId == secondId;
    }

    return _legacyEquals(first, second);
  }
}
