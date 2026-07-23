import 'dart:collection';

import 'life_context_domains.dart';

enum LifeContextNodeType {
  person,
  identity,
  household,
  residence,
  responsibility,
  event,
  eventSeries,
  task,
  routine,
  membership,
  relationship,
}

enum LifeContextNodeStatus { active, historical, future, uncertain }

enum LifeContextConfirmation {
  confirmed,
  proposed,
  inferred,
  needsConfirmation,
  rejected,
  historical,
}

enum LifeContextRelationType {
  humanRelation,
  identityLink,
  householdMembership,
  householdResidence,
  personResidence,
  responsibilityFor,
  eventParticipant,
  routineAssociation,
  seriesMembership,
}

enum LifeContextRelationNature { direct, derived }

enum LifeContextDependencyType {
  requires,
  blocks,
  follows,
  belongsTo,
  scheduledBy,
  generatedFrom,
  explicitUserDependency,
  custom,
}

enum LifeContextImpactType {
  revalidateTemporalContext,
  revalidateAssociation,
  revalidateResponsibility,
  revalidateMembership,
  revalidateIdentityLink,
  refreshProjection,
}

abstract final class LifeContextRegisteredRuleIds {
  static const humanRelationship = 'human.relationship.explicit';
  static const householdMembership = 'human.householdMembership.explicit';
  static const householdResidence = 'human.householdResidence.explicit';
  static const personResidence = 'human.personResidence.explicit';
  static const responsibility = 'human.responsibility.explicit';
  static const identityLink = 'identity.humanLink.explicit';
  static const eventParticipant = 'event.participantIdentity.explicit';
  static const routineAssociation = 'routine.humanPerson.explicit';
  static const seriesMembership = 'event.seriesMembership.explicit';
  static const explicitDependency = 'dependency.explicitUser.v1';

  static const all = {
    humanRelationship,
    householdMembership,
    householdResidence,
    personResidence,
    responsibility,
    identityLink,
    eventParticipant,
    routineAssociation,
    seriesMembership,
    explicitDependency,
  };
}

final class LifeContextGraphException implements Exception {
  const LifeContextGraphException(this.code);

  final String code;

  @override
  String toString() => 'LifeContextGraphException($code)';
}

final class LifeContextTemporalRange {
  const LifeContextTemporalRange({this.validFrom, this.validUntil});

  final DateTime? validFrom;
  final DateTime? validUntil;

  void validate() {
    if (validFrom != null &&
        validUntil != null &&
        validUntil!.isBefore(validFrom!)) {
      throw const LifeContextGraphException('invalid_graph_period');
    }
  }

  bool isActiveAt(DateTime at) {
    validate();
    if (validFrom != null && at.isBefore(validFrom!)) return false;
    if (validUntil != null && at.isAfter(validUntil!)) return false;
    return true;
  }

  bool isHistoricalAt(DateTime at) =>
      validUntil != null && at.isAfter(validUntil!);

  bool isFutureAt(DateTime at) => validFrom != null && at.isBefore(validFrom!);

  Map<String, Object?> toJson() => {
        if (validFrom != null)
          'validFrom': validFrom!.toUtc().toIso8601String(),
        if (validUntil != null)
          'validUntil': validUntil!.toUtc().toIso8601String(),
      };
}

final class LifeContextGraphNode {
  LifeContextGraphNode({
    required this.domain,
    required this.sourceId,
    required this.resourceType,
    required this.accountScopeId,
    this.validity = const LifeContextTemporalRange(),
    this.status = LifeContextNodeStatus.active,
    this.confirmation = LifeContextConfirmation.confirmed,
    this.sourceRevision,
  }) : id = deterministicId(domain, resourceType, sourceId) {
    if (sourceId.trim().isEmpty || accountScopeId.trim().isEmpty) {
      throw const LifeContextGraphException('invalid_graph_node');
    }
    validity.validate();
  }

  static String deterministicId(
    LifeContextDomain domain,
    LifeContextNodeType type,
    String sourceId,
  ) =>
      '${domain.name}:${type.name}:$sourceId';

  final String id;
  final LifeContextDomain domain;
  final String sourceId;
  final LifeContextNodeType resourceType;
  final String accountScopeId;
  final LifeContextTemporalRange validity;
  final LifeContextNodeStatus status;
  final LifeContextConfirmation confirmation;
  final int? sourceRevision;

  bool isActiveAt(DateTime at, {bool includeUncertain = true}) =>
      status != LifeContextNodeStatus.historical &&
      confirmation != LifeContextConfirmation.rejected &&
      (includeUncertain || confirmation == LifeContextConfirmation.confirmed) &&
      validity.isActiveAt(at);

  Map<String, Object?> toJson() => {
        'id': id,
        'domain': domain.name,
        'sourceId': sourceId,
        'resourceType': resourceType.name,
        'validity': validity.toJson(),
        'status': status.name,
        'confirmation': confirmation.name,
        if (sourceRevision != null) 'sourceRevision': sourceRevision,
      };
}

final class LifeContextRelationProvenance {
  LifeContextRelationProvenance({
    required this.sourceDomain,
    required this.sourceRecordId,
    required this.evidenceType,
    required this.confirmation,
    required this.ruleId,
    required this.ruleVersion,
    required this.readAt,
    required this.snapshotId,
    required this.sectionSource,
    required this.nature,
  }) {
    if (sourceRecordId.trim().isEmpty ||
        evidenceType.trim().isEmpty ||
        ruleId.trim().isEmpty ||
        ruleVersion < 1 ||
        snapshotId.trim().isEmpty) {
      throw const LifeContextGraphException('invalid_graph_provenance');
    }
  }

  final LifeContextDomain sourceDomain;
  final String sourceRecordId;
  final String evidenceType;
  final LifeContextConfirmation confirmation;
  final String ruleId;
  final int ruleVersion;
  final DateTime readAt;
  final String snapshotId;
  final LifeContextSourceKind sectionSource;
  final LifeContextRelationNature nature;

  Map<String, Object?> toJson() => {
        'sourceDomain': sourceDomain.name,
        'sourceRecordId': sourceRecordId,
        'evidenceType': evidenceType,
        'confirmation': confirmation.name,
        'ruleId': ruleId,
        'ruleVersion': ruleVersion,
        'readAt': readAt.toUtc().toIso8601String(),
        'snapshotId': snapshotId,
        'sectionSource': sectionSource.name,
        'nature': nature.name,
      };
}

final class LifeContextGraphRelation {
  LifeContextGraphRelation({
    required this.sourceNodeId,
    required this.targetNodeId,
    required this.type,
    required this.provenance,
    required this.freshness,
    this.validity = const LifeContextTemporalRange(),
    this.status = LifeContextNodeStatus.active,
  }) : id = deterministicId(
          provenance.ruleId,
          provenance.sourceRecordId,
          sourceNodeId,
          targetNodeId,
          type.name,
        ) {
    if (sourceNodeId.trim().isEmpty ||
        targetNodeId.trim().isEmpty ||
        sourceNodeId == targetNodeId) {
      throw const LifeContextGraphException('invalid_graph_relation');
    }
    validity.validate();
  }

  static String deterministicId(
    String ruleId,
    String recordId,
    String source,
    String target,
    String type,
  ) =>
      '$ruleId:$recordId:$type:$source>$target';

  final String id;
  final String sourceNodeId;
  final String targetNodeId;
  final LifeContextRelationType type;
  final LifeContextRelationProvenance provenance;
  final LifeContextFreshness freshness;
  final LifeContextTemporalRange validity;
  final LifeContextNodeStatus status;

  LifeContextConfirmation get confirmation => provenance.confirmation;

  bool isActiveAt(DateTime at, {bool includeUncertain = true}) =>
      status != LifeContextNodeStatus.historical &&
      confirmation != LifeContextConfirmation.rejected &&
      (includeUncertain || confirmation == LifeContextConfirmation.confirmed) &&
      validity.isActiveAt(at);

  Map<String, Object?> toJson() => {
        'id': id,
        'sourceNodeId': sourceNodeId,
        'targetNodeId': targetNodeId,
        'type': type.name,
        'provenance': provenance.toJson(),
        'freshness': freshness.name,
        'validity': validity.toJson(),
        'status': status.name,
      };
}

final class LifeContextDependency {
  LifeContextDependency({
    required this.prerequisiteNodeId,
    required this.dependentNodeId,
    required this.type,
    required this.provenance,
    this.validity = const LifeContextTemporalRange(),
  }) : id = LifeContextGraphRelation.deterministicId(
          provenance.ruleId,
          provenance.sourceRecordId,
          prerequisiteNodeId,
          dependentNodeId,
          type.name,
        ) {
    if (prerequisiteNodeId.trim().isEmpty ||
        dependentNodeId.trim().isEmpty ||
        prerequisiteNodeId == dependentNodeId) {
      throw const LifeContextGraphException('invalid_graph_dependency');
    }
    validity.validate();
  }

  final String id;
  final String prerequisiteNodeId;
  final String dependentNodeId;
  final LifeContextDependencyType type;
  final LifeContextRelationProvenance provenance;
  final LifeContextTemporalRange validity;

  Map<String, Object?> toJson() => {
        'id': id,
        'prerequisiteNodeId': prerequisiteNodeId,
        'dependentNodeId': dependentNodeId,
        'type': type.name,
        'provenance': provenance.toJson(),
        'validity': validity.toJson(),
      };
}

final class LifeContextDependencyPath {
  LifeContextDependencyPath({
    required List<String> nodeIds,
    required List<String> dependencyIds,
    required this.truncated,
  })  : nodeIds = UnmodifiableListView(nodeIds),
        dependencyIds = UnmodifiableListView(dependencyIds);

  final List<String> nodeIds;
  final List<String> dependencyIds;
  final bool truncated;
}

final class LifeContextDependencyCycle {
  LifeContextDependencyCycle({
    required List<String> nodeIds,
    required List<String> dependencyIds,
  })  : nodeIds = UnmodifiableListView(nodeIds),
        dependencyIds = UnmodifiableListView(dependencyIds);

  final List<String> nodeIds;
  final List<String> dependencyIds;
}

final class LifeContextTechnicalConsequence {
  LifeContextTechnicalConsequence({
    required this.triggerNodeId,
    required this.affectedNodeId,
    required List<String> relationPath,
    required this.impactType,
    required this.ruleId,
    required this.depth,
    required this.containsCycle,
    required this.confirmation,
  }) : relationPath = UnmodifiableListView(relationPath);

  final String triggerNodeId;
  final String affectedNodeId;
  final List<String> relationPath;
  final LifeContextImpactType impactType;
  final String ruleId;
  final int depth;
  final bool containsCycle;
  final LifeContextConfirmation confirmation;
}

final class LifeContextGraph {
  static const int currentSchemaVersion = 1;

  LifeContextGraph({
    this.schemaVersion = currentSchemaVersion,
    required this.accountScopeId,
    required this.snapshotId,
    required List<LifeContextGraphNode> nodes,
    required List<LifeContextGraphRelation> relations,
    List<LifeContextDependency> dependencies = const [],
  })  : nodes = UnmodifiableListView(
          List<LifeContextGraphNode>.of(nodes)
            ..sort((a, b) => a.id.compareTo(b.id)),
        ),
        relations = UnmodifiableListView(
          List<LifeContextGraphRelation>.of(relations)
            ..sort((a, b) => a.id.compareTo(b.id)),
        ),
        dependencies = UnmodifiableListView(
          List<LifeContextDependency>.of(dependencies)
            ..sort((a, b) => a.id.compareTo(b.id)),
        ) {
    validate();
  }

  final int schemaVersion;
  final String accountScopeId;
  final String snapshotId;
  final List<LifeContextGraphNode> nodes;
  final List<LifeContextGraphRelation> relations;
  final List<LifeContextDependency> dependencies;

  void validate() {
    if (schemaVersion != currentSchemaVersion) {
      throw const LifeContextGraphException('unsupported_graph_version');
    }
    if (accountScopeId.trim().isEmpty || snapshotId.trim().isEmpty) {
      throw const LifeContextGraphException('invalid_graph_identity');
    }
    final nodeIds = nodes.map((node) => node.id).toSet();
    if (nodeIds.length != nodes.length ||
        nodes.any((node) => node.accountScopeId != accountScopeId)) {
      throw const LifeContextGraphException('invalid_graph_nodes');
    }
    final edgeIds = <String>{};
    for (final relation in relations) {
      if (!nodeIds.contains(relation.sourceNodeId) ||
          !nodeIds.contains(relation.targetNodeId) ||
          !LifeContextRegisteredRuleIds.all
              .contains(relation.provenance.ruleId) ||
          !edgeIds.add(relation.id)) {
        throw const LifeContextGraphException('invalid_graph_relations');
      }
    }
    for (final dependency in dependencies) {
      if (!nodeIds.contains(dependency.prerequisiteNodeId) ||
          !nodeIds.contains(dependency.dependentNodeId) ||
          !LifeContextRegisteredRuleIds.all
              .contains(dependency.provenance.ruleId) ||
          !edgeIds.add(dependency.id)) {
        throw const LifeContextGraphException('invalid_graph_dependencies');
      }
    }
  }

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'snapshotId': snapshotId,
        'nodes': nodes.map((node) => node.toJson()).toList(),
        'relations': relations.map((relation) => relation.toJson()).toList(),
        'dependencies':
            dependencies.map((dependency) => dependency.toJson()).toList(),
      };
}
