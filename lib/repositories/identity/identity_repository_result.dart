import 'dart:collection';

import '../../core/identity/life_entity.dart';
import 'identity_read_repository.dart';

final class IdentityRepositoryQueryResult {
  final List<LifeEntity> _entities;
  final bool limitReached;
  final int requestedLimit;

  IdentityRepositoryQueryResult({
    required List<LifeEntity> entities,
    required this.limitReached,
    required this.requestedLimit,
  }) : _entities = List.unmodifiable(entities) {
    if (requestedLimit < 1 ||
        requestedLimit > 20 ||
        _entities.length > requestedLimit) {
      throw const IdentityRepositoryException('invalid_query_result');
    }
    final ids = _entities.map((entity) => entity.id).toSet();
    if (ids.length != _entities.length) {
      throw const IdentityRepositoryException('duplicate_entity_id');
    }
  }

  List<LifeEntity> get entities => UnmodifiableListView(_entities);
}
