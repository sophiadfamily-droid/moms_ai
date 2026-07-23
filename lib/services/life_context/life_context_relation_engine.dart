import 'dart:collection';

import '../../models/life_context/life_context_domains.dart';
import '../../models/life_context/life_context_graph.dart';
import '../../models/life_context/life_context_snapshot.dart';

final class LifeContextDerivationRule {
  const LifeContextDerivationRule({
    required this.id,
    required this.version,
    required this.inputDomain,
    required this.outputType,
    required this.description,
  });

  final String id;
  final int version;
  final LifeContextDomain inputDomain;
  final LifeContextRelationType outputType;
  final String description;
}

abstract final class LifeContextDerivationRules {
  static const humanRelationship = LifeContextDerivationRule(
    id: LifeContextRegisteredRuleIds.humanRelationship,
    version: 1,
    inputDomain: LifeContextDomain.human,
    outputType: LifeContextRelationType.humanRelation,
    description: 'Projects one explicit directional HumanRelationship.',
  );
  static const householdMembership = LifeContextDerivationRule(
    id: LifeContextRegisteredRuleIds.householdMembership,
    version: 1,
    inputDomain: LifeContextDomain.human,
    outputType: LifeContextRelationType.householdMembership,
    description: 'Projects one explicit person to household membership.',
  );
  static const householdResidence = LifeContextDerivationRule(
    id: LifeContextRegisteredRuleIds.householdResidence,
    version: 1,
    inputDomain: LifeContextDomain.human,
    outputType: LifeContextRelationType.householdResidence,
    description: 'Projects an explicit household to residence association.',
  );
  static const personResidence = LifeContextDerivationRule(
    id: LifeContextRegisteredRuleIds.personResidence,
    version: 1,
    inputDomain: LifeContextDomain.human,
    outputType: LifeContextRelationType.personResidence,
    description: 'Projects an explicit person to residence association.',
  );
  static const responsibility = LifeContextDerivationRule(
    id: LifeContextRegisteredRuleIds.responsibility,
    version: 1,
    inputDomain: LifeContextDomain.human,
    outputType: LifeContextRelationType.responsibilityFor,
    description: 'Projects responsible person to subject person.',
  );
  static const identityLink = LifeContextDerivationRule(
    id: LifeContextRegisteredRuleIds.identityLink,
    version: 1,
    inputDomain: LifeContextDomain.identity,
    outputType: LifeContextRelationType.identityLink,
    description: 'Projects an explicit HumanPerson to Identity link.',
  );
  static const eventParticipant = LifeContextDerivationRule(
    id: LifeContextRegisteredRuleIds.eventParticipant,
    version: 1,
    inputDomain: LifeContextDomain.event,
    outputType: LifeContextRelationType.eventParticipant,
    description: 'Projects only a structured participant Identity to Event.',
  );
  static const routineAssociation = LifeContextDerivationRule(
    id: LifeContextRegisteredRuleIds.routineAssociation,
    version: 1,
    inputDomain: LifeContextDomain.routine,
    outputType: LifeContextRelationType.routineAssociation,
    description: 'Projects only a structured HumanPerson to Routine link.',
  );
  static const seriesMembership = LifeContextDerivationRule(
    id: LifeContextRegisteredRuleIds.seriesMembership,
    version: 1,
    inputDomain: LifeContextDomain.event,
    outputType: LifeContextRelationType.seriesMembership,
    description: 'Projects an explicit parent recurring series identifier.',
  );

  static const List<LifeContextDerivationRule> registered = [
    humanRelationship,
    householdMembership,
    householdResidence,
    personResidence,
    responsibility,
    identityLink,
    eventParticipant,
    routineAssociation,
    seriesMembership,
  ];

  static LifeContextDerivationRule require(String id) =>
      registered.where((rule) => rule.id == id).singleOrNull ??
      (throw const LifeContextGraphException(
        'unregistered_derivation_rule',
      ));
}

/// Pure, read-only LC.2 boundary. It consumes one validated LC.1 snapshot and
/// never reaches repositories, persistence, UI, diagnostics, or model APIs.
final class LifeContextRelationEngine {
  const LifeContextRelationEngine();

  LifeContextGraph build(LifeContextSnapshot snapshot) {
    snapshot.validateCanonical();
    if (snapshot.schemaVersion != LifeContextSnapshot.currentSchemaVersion) {
      throw const LifeContextGraphException('unsupported_snapshot_version');
    }
    final scope = snapshot.accountScopeId!;
    final snapshotId = snapshot.snapshotId!;
    final nodes = <String, LifeContextGraphNode>{};
    final relations = <LifeContextGraphRelation>[];

    void addNode(LifeContextGraphNode node) {
      final previous = nodes[node.id];
      if (previous != null &&
          (previous.domain != node.domain ||
              previous.sourceId != node.sourceId ||
              previous.resourceType != node.resourceType)) {
        throw const LifeContextGraphException('duplicate_graph_node');
      }
      nodes[node.id] = previous ?? node;
    }

    final human = snapshot.human!;
    for (final person in human.persons) {
      addNode(
        _node(
          scope,
          LifeContextDomain.human,
          LifeContextNodeType.person,
          person.id,
          status: _personStatus(person.status),
          confirmation: _confirmation(person.confirmation),
          revision: human.metadata.revision,
        ),
      );
    }
    for (final record in human.relationships) {
      addNode(
        _recordNode(
          scope,
          record,
          LifeContextNodeType.relationship,
          snapshot.generatedAt,
        ),
      );
      relations.add(
        _relationFromRecord(
          snapshot,
          record,
          LifeContextDerivationRules.humanRelationship,
          _personId(record.sourceReferenceId),
          _personId(record.targetReferenceId),
          human.metadata,
        ),
      );
    }
    for (final record in human.households) {
      addNode(
        _recordNode(
          scope,
          record,
          LifeContextNodeType.household,
          snapshot.generatedAt,
        ),
      );
    }
    for (final record in human.residences) {
      addNode(
        _recordNode(
          scope,
          record,
          LifeContextNodeType.residence,
          snapshot.generatedAt,
        ),
      );
    }
    for (final record in human.memberships) {
      addNode(
        _recordNode(
          scope,
          record,
          LifeContextNodeType.membership,
          snapshot.generatedAt,
        ),
      );
      relations.add(
        _relationFromRecord(
          snapshot,
          record,
          LifeContextDerivationRules.householdMembership,
          _personId(record.sourceReferenceId),
          _householdId(record.targetReferenceId),
          human.metadata,
        ),
      );
    }
    for (final record in human.responsibilities) {
      addNode(
        _recordNode(
          scope,
          record,
          LifeContextNodeType.responsibility,
          snapshot.generatedAt,
        ),
      );
      relations.add(
        _relationFromRecord(
          snapshot,
          record,
          LifeContextDerivationRules.responsibility,
          _personId(record.sourceReferenceId),
          _personId(record.targetReferenceId),
          human.metadata,
        ),
      );
    }
    for (final residence in human.residences) {
      for (final householdId in residence.householdIds) {
        relations.add(
          _relationFromRecord(
            snapshot,
            residence,
            LifeContextDerivationRules.householdResidence,
            _householdId(householdId),
            _residenceId(residence.id),
            human.metadata,
          ),
        );
      }
      for (final personId in residence.personIds) {
        relations.add(
          _relationFromRecord(
            snapshot,
            residence,
            LifeContextDerivationRules.personResidence,
            _personId(personId),
            _residenceId(residence.id),
            human.metadata,
          ),
        );
      }
    }

    final identity = snapshot.identityDomain!;
    for (final link in identity.links) {
      final identityId = _identityId(link.entityId);
      addNode(
        _node(
          scope,
          LifeContextDomain.identity,
          LifeContextNodeType.identity,
          link.entityId,
          confirmation: link.confirmed
              ? LifeContextConfirmation.confirmed
              : LifeContextConfirmation.needsConfirmation,
          revision: identity.metadata.revision,
        ),
      );
      relations.add(
        _directRelation(
          snapshot,
          LifeContextDerivationRules.identityLink,
          link.humanPersonId,
          _personId(link.humanPersonId),
          identityId,
          identity.metadata,
          confirmation: link.confirmed
              ? LifeContextConfirmation.confirmed
              : LifeContextConfirmation.needsConfirmation,
          evidenceType: 'persistedIdentityLink',
        ),
      );
    }

    final events = snapshot.eventDomain!;
    for (final event in events.events) {
      final eventId = _eventId(event.id);
      addNode(
        _node(
          scope,
          LifeContextDomain.event,
          LifeContextNodeType.event,
          event.id,
          revision: event.revision,
        ),
      );
      final participantId = event.participantEntityId;
      if (participantId != null) {
        addNode(
          _node(
            scope,
            LifeContextDomain.identity,
            LifeContextNodeType.identity,
            participantId,
          ),
        );
        relations.add(
          _directRelation(
            snapshot,
            LifeContextDerivationRules.eventParticipant,
            event.id,
            _identityId(participantId),
            eventId,
            events.metadata,
            evidenceType: 'structuredEventParticipant',
          ),
        );
      }
      final seriesId = event.parentRecurringId;
      if (seriesId != null) {
        addNode(
          _node(
            scope,
            LifeContextDomain.event,
            LifeContextNodeType.eventSeries,
            seriesId,
          ),
        );
        relations.add(
          _directRelation(
            snapshot,
            LifeContextDerivationRules.seriesMembership,
            event.id,
            eventId,
            _seriesId(seriesId),
            events.metadata,
            evidenceType: 'parentRecurringId',
          ),
        );
      }
    }

    final tasks = snapshot.taskDomain!;
    for (final task in tasks.tasks) {
      addNode(
        _node(
          scope,
          LifeContextDomain.task,
          LifeContextNodeType.task,
          task.id,
          status: task.isCompleted
              ? LifeContextNodeStatus.historical
              : LifeContextNodeStatus.active,
        ),
      );
    }

    final routines = snapshot.routineDomain!;
    for (final routine in routines.routines) {
      final routineId = _routineId(routine.id);
      addNode(
        _node(
          scope,
          LifeContextDomain.routine,
          LifeContextNodeType.routine,
          routine.id,
        ),
      );
      if (routine.humanPersonId != null) {
        relations.add(
          _directRelation(
            snapshot,
            LifeContextDerivationRules.routineAssociation,
            routine.id,
            _personId(routine.humanPersonId!),
            routineId,
            routines.metadata,
            evidenceType: 'structuredRoutinePerson',
          ),
        );
      }
    }

    final graph = LifeContextGraph(
      accountScopeId: scope,
      snapshotId: snapshotId,
      nodes: nodes.values.toList(),
      relations: relations,
    );
    return graph;
  }

  LifeContextGraphNode _recordNode(
    String scope,
    HumanContextRecord record,
    LifeContextNodeType type,
    DateTime evaluatedAt,
  ) =>
      _node(
        scope,
        LifeContextDomain.human,
        type,
        record.id,
        validity: _validity(record),
        status: _recordStatus(record, evaluatedAt),
        confirmation: _confirmation(record.confirmation),
      );

  LifeContextGraphNode _node(
    String scope,
    LifeContextDomain domain,
    LifeContextNodeType type,
    String sourceId, {
    LifeContextTemporalRange validity = const LifeContextTemporalRange(),
    LifeContextNodeStatus status = LifeContextNodeStatus.active,
    LifeContextConfirmation confirmation = LifeContextConfirmation.confirmed,
    int? revision,
  }) =>
      LifeContextGraphNode(
        domain: domain,
        sourceId: sourceId,
        resourceType: type,
        accountScopeId: scope,
        validity: validity,
        status: status,
        confirmation: confirmation,
        sourceRevision: revision,
      );

  LifeContextGraphRelation _relationFromRecord(
    LifeContextSnapshot snapshot,
    HumanContextRecord record,
    LifeContextDerivationRule rule,
    String sourceNodeId,
    String targetNodeId,
    LifeContextSourceMetadata metadata,
  ) =>
      _directRelation(
        snapshot,
        rule,
        record.id,
        sourceNodeId,
        targetNodeId,
        metadata,
        validity: _validity(record),
        status: _recordStatus(record, snapshot.generatedAt),
        confirmation: _confirmation(record.confirmation),
        evidenceType: record.evidenceSource ?? 'unknown',
      );

  LifeContextGraphRelation _directRelation(
    LifeContextSnapshot snapshot,
    LifeContextDerivationRule rule,
    String sourceRecordId,
    String sourceNodeId,
    String targetNodeId,
    LifeContextSourceMetadata metadata, {
    LifeContextTemporalRange validity = const LifeContextTemporalRange(),
    LifeContextNodeStatus status = LifeContextNodeStatus.active,
    LifeContextConfirmation confirmation = LifeContextConfirmation.confirmed,
    required String evidenceType,
  }) {
    LifeContextDerivationRules.require(rule.id);
    return LifeContextGraphRelation(
      sourceNodeId: sourceNodeId,
      targetNodeId: targetNodeId,
      type: rule.outputType,
      provenance: LifeContextRelationProvenance(
        sourceDomain: rule.inputDomain,
        sourceRecordId: sourceRecordId,
        evidenceType: evidenceType,
        confirmation: confirmation,
        ruleId: rule.id,
        ruleVersion: rule.version,
        readAt: metadata.readAt,
        snapshotId: snapshot.snapshotId!,
        sectionSource: metadata.source,
        nature: LifeContextRelationNature.direct,
      ),
      freshness: metadata.freshness,
      validity: validity,
      status: status,
    );
  }

  String _personId(String? id) {
    if (id == null || id.trim().isEmpty) {
      throw const LifeContextGraphException('missing_person_reference');
    }
    return LifeContextGraphNode.deterministicId(
      LifeContextDomain.human,
      LifeContextNodeType.person,
      id,
    );
  }

  String _householdId(String? id) {
    if (id == null || id.trim().isEmpty) {
      throw const LifeContextGraphException('missing_household_reference');
    }
    return LifeContextGraphNode.deterministicId(
      LifeContextDomain.human,
      LifeContextNodeType.household,
      id,
    );
  }

  String _residenceId(String id) => LifeContextGraphNode.deterministicId(
        LifeContextDomain.human,
        LifeContextNodeType.residence,
        id,
      );
  String _identityId(String id) => LifeContextGraphNode.deterministicId(
        LifeContextDomain.identity,
        LifeContextNodeType.identity,
        id,
      );
  String _eventId(String id) => LifeContextGraphNode.deterministicId(
        LifeContextDomain.event,
        LifeContextNodeType.event,
        id,
      );
  String _seriesId(String id) => LifeContextGraphNode.deterministicId(
        LifeContextDomain.event,
        LifeContextNodeType.eventSeries,
        id,
      );
  String _routineId(String id) => LifeContextGraphNode.deterministicId(
        LifeContextDomain.routine,
        LifeContextNodeType.routine,
        id,
      );

  LifeContextTemporalRange _validity(HumanContextRecord record) =>
      LifeContextTemporalRange(
        validFrom: record.validFrom,
        validUntil: record.validUntil,
      );

  LifeContextConfirmation _confirmation(String value) =>
      LifeContextConfirmation.values.firstWhere(
        (item) => item.name == value,
        orElse: () => LifeContextConfirmation.needsConfirmation,
      );

  LifeContextNodeStatus _personStatus(String value) => switch (value) {
        'historical' ||
        'absent' ||
        'deceased' =>
          LifeContextNodeStatus.historical,
        _ => LifeContextNodeStatus.active,
      };

  LifeContextNodeStatus _recordStatus(
    HumanContextRecord record,
    DateTime evaluatedAt,
  ) {
    if (record.status == 'historical' || record.status == 'ended') {
      return LifeContextNodeStatus.historical;
    }
    if (record.validFrom != null && evaluatedAt.isBefore(record.validFrom!)) {
      return LifeContextNodeStatus.future;
    }
    if (record.confirmation == 'needsConfirmation' ||
        record.confirmation == 'proposed' ||
        record.confirmation == 'inferred') {
      return LifeContextNodeStatus.uncertain;
    }
    return LifeContextNodeStatus.active;
  }
}

final class LifeContextGraphQuery {
  LifeContextGraphQuery(this.graph)
      : _nodes = {for (final node in graph.nodes) node.id: node},
        _relationsById = {
          for (final relation in graph.relations) relation.id: relation,
        };

  final LifeContextGraph graph;
  final Map<String, LifeContextGraphNode> _nodes;
  final Map<String, LifeContextGraphRelation> _relationsById;

  LifeContextGraphNode? node(String id) => _nodes[id];

  List<LifeContextGraphRelation> outgoing(
    String nodeId, {
    bool confirmedOnly = false,
    bool includeUncertain = true,
    bool includeHistorical = true,
  }) =>
      _filter(
        graph.relations.where((edge) => edge.sourceNodeId == nodeId),
        confirmedOnly: confirmedOnly,
        includeUncertain: includeUncertain,
        includeHistorical: includeHistorical,
      );

  List<LifeContextGraphRelation> incoming(
    String nodeId, {
    bool confirmedOnly = false,
    bool includeUncertain = true,
    bool includeHistorical = true,
  }) =>
      _filter(
        graph.relations.where((edge) => edge.targetNodeId == nodeId),
        confirmedOnly: confirmedOnly,
        includeUncertain: includeUncertain,
        includeHistorical: includeHistorical,
      );

  List<LifeContextGraphRelation> ofType(LifeContextRelationType type) =>
      _sorted(graph.relations.where((edge) => edge.type == type));

  List<LifeContextGraphRelation> activeRelationsAt(
    DateTime at, {
    bool confirmedOnly = false,
    bool includeUncertain = true,
  }) =>
      _sorted(
        graph.relations.where(
          (edge) =>
              edge.isActiveAt(at, includeUncertain: includeUncertain) &&
              (!confirmedOnly ||
                  edge.confirmation == LifeContextConfirmation.confirmed) &&
              (_nodes[edge.sourceNodeId]?.isActiveAt(
                    at,
                    includeUncertain: includeUncertain,
                  ) ??
                  false) &&
              (_nodes[edge.targetNodeId]?.isActiveAt(
                    at,
                    includeUncertain: includeUncertain,
                  ) ??
                  false),
        ),
      );

  List<LifeContextGraphRelation> historicalRelations(DateTime at) => _sorted(
        graph.relations.where(
          (edge) =>
              edge.status == LifeContextNodeStatus.historical ||
              edge.validity.isHistoricalAt(at) ||
              edge.confirmation == LifeContextConfirmation.historical,
        ),
      );

  List<LifeContextGraphRelation> futureRelations(DateTime at) => _sorted(
        graph.relations.where(
          (edge) =>
              edge.status == LifeContextNodeStatus.future ||
              edge.validity.isFutureAt(at),
        ),
      );

  List<LifeContextGraphNode> personsOfHousehold(String householdNodeId) =>
      _targetedNodes(
        incoming(householdNodeId),
        LifeContextRelationType.householdMembership,
        useSource: true,
      );

  List<LifeContextGraphNode> householdsOfPerson(String personNodeId) =>
      _targetedNodes(
        outgoing(personNodeId),
        LifeContextRelationType.householdMembership,
      );

  List<LifeContextGraphNode> residencesOf(String nodeId) => _targetedNodes(
        outgoing(nodeId),
        null,
        allowedTypes: const {
          LifeContextRelationType.householdResidence,
          LifeContextRelationType.personResidence,
        },
      );

  List<LifeContextGraphNode> activeResponsiblePeople(
    String personNodeId,
    DateTime at,
  ) =>
      _nodesFromRelations(
        activeRelationsAt(at).where(
          (edge) =>
              edge.type == LifeContextRelationType.responsibilityFor &&
              edge.targetNodeId == personNodeId,
        ),
        useSource: true,
      );

  List<LifeContextGraphNode> peopleUnderResponsibility(
    String responsibleNodeId,
    DateTime at,
  ) =>
      _nodesFromRelations(
        activeRelationsAt(at).where(
          (edge) =>
              edge.type == LifeContextRelationType.responsibilityFor &&
              edge.sourceNodeId == responsibleNodeId,
        ),
      );

  List<LifeContextGraphNode> eventsForPerson(String personNodeId) {
    final identityIds = outgoing(personNodeId)
        .where((edge) => edge.type == LifeContextRelationType.identityLink)
        .map((edge) => edge.targetNodeId)
        .toSet();
    final eventIds = graph.relations
        .where(
          (edge) =>
              edge.type == LifeContextRelationType.eventParticipant &&
              identityIds.contains(edge.sourceNodeId),
        )
        .map((edge) => edge.targetNodeId)
        .toSet();
    return _sortedNodes(eventIds.map((id) => _nodes[id]!).toList());
  }

  LifeContextRelationProvenance explainRelation(String relationId) {
    final relation = _relationsById[relationId];
    if (relation == null) {
      throw const LifeContextGraphException('relation_not_found');
    }
    return relation.provenance;
  }

  List<LifeContextDependency> directDependencies(String prerequisiteNodeId) =>
      List.unmodifiable(
        graph.dependencies
            .where(
              (dependency) =>
                  dependency.prerequisiteNodeId == prerequisiteNodeId,
            )
            .toList()
          ..sort((a, b) => a.id.compareTo(b.id)),
      );

  List<LifeContextDependency> dependents(String dependentNodeId) =>
      List.unmodifiable(
        graph.dependencies
            .where(
              (dependency) => dependency.dependentNodeId == dependentNodeId,
            )
            .toList()
          ..sort((a, b) => a.id.compareTo(b.id)),
      );

  LifeContextDependencyPath transitiveDependencies(
    String prerequisiteNodeId, {
    required int maxDepth,
    int maxVisitedNodes = 100,
  }) {
    if (maxDepth < 1 || maxVisitedNodes < 1) {
      throw const LifeContextGraphException('invalid_traversal_limit');
    }
    final visited = <String>{prerequisiteNodeId};
    final nodeIds = <String>[];
    final dependencyIds = <String>[];
    var frontier = <String>[prerequisiteNodeId];
    var truncated = false;
    for (var depth = 0; depth < maxDepth && frontier.isNotEmpty; depth++) {
      final next = <String>[];
      for (final current in frontier..sort()) {
        for (final dependency in directDependencies(current)) {
          if (visited.length >= maxVisitedNodes) {
            truncated = true;
            break;
          }
          dependencyIds.add(dependency.id);
          if (visited.add(dependency.dependentNodeId)) {
            nodeIds.add(dependency.dependentNodeId);
            next.add(dependency.dependentNodeId);
          }
        }
      }
      frontier = next;
      if (depth == maxDepth - 1 &&
          frontier.any((node) => directDependencies(node).isNotEmpty)) {
        truncated = true;
      }
    }
    return LifeContextDependencyPath(
      nodeIds: nodeIds,
      dependencyIds: dependencyIds..sort(),
      truncated: truncated,
    );
  }

  List<LifeContextDependencyCycle> dependencyCycles({
    int maxVisitedNodes = 1000,
  }) {
    if (maxVisitedNodes < 1) {
      throw const LifeContextGraphException('invalid_traversal_limit');
    }
    final adjacency = <String, List<LifeContextDependency>>{};
    for (final edge in graph.dependencies) {
      adjacency.putIfAbsent(edge.prerequisiteNodeId, () => []).add(edge);
    }
    for (final edges in adjacency.values) {
      edges.sort((a, b) => a.id.compareTo(b.id));
    }
    final cycles = <String, LifeContextDependencyCycle>{};
    final pathNodes = <String>[];
    final pathEdges = <LifeContextDependency>[];
    var visitedCount = 0;

    void visit(String nodeId) {
      if (visitedCount >= maxVisitedNodes) return;
      visitedCount++;
      final existingIndex = pathNodes.indexOf(nodeId);
      if (existingIndex >= 0) {
        final cycleNodes = pathNodes.sublist(existingIndex)..add(nodeId);
        final cycleEdges = pathEdges.sublist(existingIndex);
        final normalized = _normalizeCycle(cycleNodes, cycleEdges);
        cycles[normalized.nodeIds.join('>')] = normalized;
        return;
      }
      pathNodes.add(nodeId);
      for (final edge in adjacency[nodeId] ?? const []) {
        pathEdges.add(edge);
        visit(edge.dependentNodeId);
        pathEdges.removeLast();
      }
      pathNodes.removeLast();
    }

    for (final nodeId in adjacency.keys.toList()..sort()) {
      visit(nodeId);
    }
    return List.unmodifiable(cycles.values.toList()
      ..sort((a, b) => a.nodeIds.join('>').compareTo(b.nodeIds.join('>'))));
  }

  List<LifeContextTechnicalConsequence> consequencesOf(
    String triggerNodeId, {
    int maxDepth = 3,
    int maxVisitedNodes = 100,
  }) {
    if (!_nodes.containsKey(triggerNodeId)) {
      throw const LifeContextGraphException('node_not_found');
    }
    if (maxDepth < 1 || maxVisitedNodes < 1) {
      throw const LifeContextGraphException('invalid_traversal_limit');
    }
    final results = <LifeContextTechnicalConsequence>[];
    final visited = <String>{triggerNodeId};
    var frontier = <({String nodeId, List<String> path})>[
      (nodeId: triggerNodeId, path: const []),
    ];
    for (var depth = 1; depth <= maxDepth && frontier.isNotEmpty; depth++) {
      final next = <({String nodeId, List<String> path})>[];
      for (final current in frontier) {
        final edges = [
          ...outgoing(current.nodeId),
          ...incoming(current.nodeId),
        ]..sort((a, b) => a.id.compareTo(b.id));
        for (final edge in edges) {
          if (results.length >= maxVisitedNodes) {
            return List.unmodifiable(results);
          }
          final affected = edge.sourceNodeId == current.nodeId
              ? edge.targetNodeId
              : edge.sourceNodeId;
          final path = [...current.path, edge.id];
          final cycle = visited.contains(affected);
          results.add(
            LifeContextTechnicalConsequence(
              triggerNodeId: triggerNodeId,
              affectedNodeId: affected,
              relationPath: path,
              impactType: _impact(edge.type),
              ruleId: edge.provenance.ruleId,
              depth: depth,
              containsCycle: cycle,
              confirmation: edge.confirmation,
            ),
          );
          if (!cycle && visited.add(affected)) {
            next.add((nodeId: affected, path: path));
          }
        }
      }
      frontier = next;
    }
    results.sort((a, b) {
      final depth = a.depth.compareTo(b.depth);
      return depth != 0 ? depth : a.affectedNodeId.compareTo(b.affectedNodeId);
    });
    return List.unmodifiable(results);
  }

  List<LifeContextGraphRelation> _filter(
    Iterable<LifeContextGraphRelation> source, {
    required bool confirmedOnly,
    required bool includeUncertain,
    required bool includeHistorical,
  }) =>
      _sorted(
        source.where(
          (edge) =>
              (!confirmedOnly ||
                  edge.confirmation == LifeContextConfirmation.confirmed) &&
              (includeUncertain ||
                  edge.confirmation == LifeContextConfirmation.confirmed) &&
              (includeHistorical ||
                  edge.status != LifeContextNodeStatus.historical),
        ),
      );

  List<LifeContextGraphRelation> _sorted(
    Iterable<LifeContextGraphRelation> source,
  ) =>
      List.unmodifiable(source.toList()..sort((a, b) => a.id.compareTo(b.id)));

  List<LifeContextGraphNode> _targetedNodes(
    Iterable<LifeContextGraphRelation> relations,
    LifeContextRelationType? type, {
    bool useSource = false,
    Set<LifeContextRelationType>? allowedTypes,
  }) =>
      _nodesFromRelations(
        relations.where(
          (edge) => type == null
              ? (allowedTypes?.contains(edge.type) ?? true)
              : edge.type == type,
        ),
        useSource: useSource,
      );

  List<LifeContextGraphNode> _nodesFromRelations(
    Iterable<LifeContextGraphRelation> relations, {
    bool useSource = false,
  }) =>
      _sortedNodes(
        relations
            .map(
              (edge) =>
                  _nodes[useSource ? edge.sourceNodeId : edge.targetNodeId]!,
            )
            .toSet()
            .toList(),
      );

  List<LifeContextGraphNode> _sortedNodes(
    List<LifeContextGraphNode> source,
  ) =>
      List.unmodifiable(source..sort((a, b) => a.id.compareTo(b.id)));

  LifeContextDependencyCycle _normalizeCycle(
    List<String> nodes,
    List<LifeContextDependency> edges,
  ) {
    final uniqueNodes = nodes.sublist(0, nodes.length - 1);
    var best = 0;
    for (var index = 1; index < uniqueNodes.length; index++) {
      if (uniqueNodes[index].compareTo(uniqueNodes[best]) < 0) best = index;
    }
    final rotatedNodes = [
      ...uniqueNodes.sublist(best),
      ...uniqueNodes.sublist(0, best),
    ];
    rotatedNodes.add(rotatedNodes.first);
    final rotatedEdges = [
      ...edges.sublist(best),
      ...edges.sublist(0, best),
    ];
    return LifeContextDependencyCycle(
      nodeIds: rotatedNodes,
      dependencyIds: rotatedEdges.map((edge) => edge.id).toList(),
    );
  }

  LifeContextImpactType _impact(LifeContextRelationType type) => switch (type) {
        LifeContextRelationType.householdMembership =>
          LifeContextImpactType.revalidateMembership,
        LifeContextRelationType.responsibilityFor =>
          LifeContextImpactType.revalidateResponsibility,
        LifeContextRelationType.identityLink =>
          LifeContextImpactType.revalidateIdentityLink,
        LifeContextRelationType.eventParticipant ||
        LifeContextRelationType.seriesMembership =>
          LifeContextImpactType.revalidateTemporalContext,
        _ => LifeContextImpactType.revalidateAssociation,
      };
}
