import 'dart:collection';

import 'entity_types.dart';
import 'life_entity.dart';

final class EntityRelationSignal {
  final String relationKey;
  final bool isVerified;
  final EntitySource source;

  EntityRelationSignal({
    required this.relationKey,
    required this.isVerified,
    required this.source,
  }) {
    if (relationKey.trim().isEmpty) {
      throw const EntityDomainException('empty_relation_key');
    }
  }
}

final class EntityCandidate {
  final LifeEntity entity;
  final List<EntityRelationSignal> _relationSignals;
  final bool isExplicitConversationTarget;

  EntityCandidate({
    required this.entity,
    List<EntityRelationSignal> relationSignals = const [],
    this.isExplicitConversationTarget = false,
  }) : _relationSignals = List.unmodifiable(relationSignals);

  List<EntityRelationSignal> get relationSignals =>
      UnmodifiableListView(_relationSignals);
}
