import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/life_context/identity_context.dart';
import 'package:moms_ai/models/life_context/intent_context.dart';
import 'package:moms_ai/models/life_context/life_context_domains.dart';
import 'package:moms_ai/models/life_context/life_context_graph.dart';
import 'package:moms_ai/models/life_context/life_context_provenance.dart';
import 'package:moms_ai/models/life_context/life_context_snapshot.dart';
import 'package:moms_ai/models/life_context/notes_context.dart';
import 'package:moms_ai/models/life_context/schedule_context.dart';
import 'package:moms_ai/services/life_context/life_context_relation_engine.dart';

void main() {
  final at = DateTime.utc(2026, 7, 23, 12);

  group('construction canonique LC.2', () {
    test('construit un graphe multi-domaines déterministe et versionné', () {
      final first = const LifeContextRelationEngine().build(_snapshot(at));
      final second = const LifeContextRelationEngine().build(_snapshot(at));

      expect(first.schemaVersion, LifeContextGraph.currentSchemaVersion);
      expect(first.toJson(), second.toJson());
      expect(
          first.nodes.map((node) => node.id),
          orderedEquals(
            [...first.nodes.map((node) => node.id)]..sort(),
          ));
      expect(
          first.relations.map((edge) => edge.id),
          orderedEquals(
            [...first.relations.map((edge) => edge.id)]..sort(),
          ));
      expect(first.dependencies, isEmpty);
      expect(first.toJson().toString(), isNot(contains('medical-secret')));
      expect(first.toJson(), isNot(containsPair('accountScopeId', anything)));
    });

    test('accepte un snapshot vide valide sans inventer de liens', () {
      final graph =
          const LifeContextRelationEngine().build(_snapshot(at, empty: true));
      expect(graph.nodes, isEmpty);
      expect(graph.relations, isEmpty);
      expect(graph.dependencies, isEmpty);
    });

    test('refuse version future, scope absent et référence manquante', () {
      expect(
        () => LifeContextGraph(
          schemaVersion: 2,
          accountScopeId: 'account-a',
          snapshotId: 'snapshot-a',
          nodes: const [],
          relations: const [],
        ),
        throwsA(_graphError('unsupported_graph_version')),
      );
      final broken = _snapshot(
        at,
        human: _human(
          at,
          relationships: [
            _record(
              'relationship-missing',
              'parent',
              const ['person-main', 'missing'],
              source: 'person-main',
              target: 'missing',
            ),
          ],
        ),
      );
      expect(
        () => const LifeContextRelationEngine().build(broken),
        throwsA(_graphError('invalid_graph_relations')),
      );
    });

    test('refuse doublons exacts et auto-dépendances', () {
      final node = _node('a');
      expect(
        () => LifeContextGraph(
          accountScopeId: 'account-a',
          snapshotId: 'snapshot-a',
          nodes: [node, node],
          relations: const [],
        ),
        throwsA(_graphError('invalid_graph_nodes')),
      );
      expect(
        () => LifeContextDependency(
          prerequisiteNodeId: node.id,
          dependentNodeId: node.id,
          type: LifeContextDependencyType.requires,
          provenance: _provenance('dependency-a'),
        ),
        throwsA(_graphError('invalid_graph_dependency')),
      );
    });

    test('refuse toute règle non enregistrée', () {
      final a = _node('a');
      final b = _node('b');
      expect(
        () => LifeContextGraph(
          accountScopeId: 'account-a',
          snapshotId: 'snapshot-a',
          nodes: [a, b],
          relations: const [],
          dependencies: [
            LifeContextDependency(
              prerequisiteNodeId: a.id,
              dependentNodeId: b.id,
              type: LifeContextDependencyType.requires,
              provenance: LifeContextRelationProvenance(
                sourceDomain: LifeContextDomain.task,
                sourceRecordId: 'dependency-a',
                evidenceType: 'structured',
                confirmation: LifeContextConfirmation.confirmed,
                ruleId: 'unregistered.rule',
                ruleVersion: 1,
                readAt: DateTime.utc(2026),
                snapshotId: 'snapshot-a',
                sectionSource: LifeContextSourceKind.taskService,
                nature: LifeContextRelationNature.direct,
              ),
            ),
          ],
        ),
        throwsA(_graphError('invalid_graph_dependencies')),
      );
    });
  });

  group('relations humaines, foyers et temporalité', () {
    late LifeContextGraph graph;
    late LifeContextGraphQuery query;

    setUp(() {
      graph = const LifeContextRelationEngine().build(_snapshot(at));
      query = LifeContextGraphQuery(graph);
    });

    test('projette uniquement les relations humaines explicites', () {
      final human = query.ofType(LifeContextRelationType.humanRelation);
      expect(human, hasLength(6));
      expect(
          human.map((edge) => edge.provenance.evidenceType),
          containsAll([
            'explicitUserInput',
            'legacyProfile',
          ]));
      expect(
        human.where((edge) => edge.provenance.ruleId.contains('inverse')),
        isEmpty,
      );
    });

    test('requête plusieurs foyers et une double appartenance', () {
      final person = _id(LifeContextNodeType.person, 'person-child');
      expect(query.householdsOfPerson(person), hasLength(2));
      expect(
        query.personsOfHousehold(
          _id(LifeContextNodeType.household, 'household-a'),
        ),
        hasLength(2),
      );
    });

    test('requête résidences explicites sans inventer cohabitation ou garde',
        () {
      final person = _id(LifeContextNodeType.person, 'person-main');
      final household = _id(LifeContextNodeType.household, 'household-a');
      expect(query.residencesOf(person), hasLength(1));
      expect(query.residencesOf(household), hasLength(1));
      expect(
        graph.relations.where(
          (edge) =>
              edge.type == LifeContextRelationType.householdMembership &&
              edge.provenance.sourceRecordId.contains('residence'),
        ),
        isEmpty,
      );
    });

    test('conserve historique, futur, incertitude et rejet', () {
      expect(query.historicalRelations(at), isNotEmpty);
      expect(query.futureRelations(at), isNotEmpty);
      expect(
        query.activeRelationsAt(at, confirmedOnly: true),
        everyElement(
          predicate<LifeContextGraphRelation>(
            (edge) => edge.confirmation == LifeContextConfirmation.confirmed,
          ),
        ),
      );
      expect(
        query.activeRelationsAt(at).where(
              (edge) => edge.confirmation == LifeContextConfirmation.rejected,
            ),
        isEmpty,
      );
      expect(
        graph.relations.where(
          (edge) =>
              edge.confirmation == LifeContextConfirmation.needsConfirmation,
        ),
        isNotEmpty,
      );
    });

    test('explique la relation sans recopier de contenu humain', () {
      final relation =
          query.ofType(LifeContextRelationType.householdMembership).first;
      final explanation = query.explainRelation(relation.id);
      expect(explanation.ruleId, 'human.householdMembership.explicit');
      expect(explanation.ruleVersion, 1);
      expect(explanation.snapshotId, 'snapshot-a');
      expect(explanation.toJson(), isNot(containsPair('name', anything)));
    });
  });

  group('responsabilités, Identity, Event, Task et Routine', () {
    late LifeContextGraph graph;
    late LifeContextGraphQuery query;

    setUp(() {
      graph = const LifeContextRelationEngine().build(_snapshot(at));
      query = LifeContextGraphQuery(graph);
    });

    test('requête plusieurs responsables et plusieurs personnes concernées',
        () {
      final child = _id(LifeContextNodeType.person, 'person-child');
      final main = _id(LifeContextNodeType.person, 'person-main');
      expect(query.activeResponsiblePeople(child, at), hasLength(2));
      expect(query.peopleUnderResponsibility(main, at), hasLength(2));
    });

    test('ne transforme pas responsabilité en obligation Event', () {
      expect(
        graph.relations.where(
          (edge) =>
              edge.type == LifeContextRelationType.responsibilityFor &&
              (edge.sourceNodeId.contains(':event:') ||
                  edge.targetNodeId.contains(':event:')),
        ),
        isEmpty,
      );
    });

    test('lie HumanPerson à Identity et Identity à Event explicitement', () {
      final person = _id(LifeContextNodeType.person, 'person-child');
      expect(query.eventsForPerson(person), hasLength(1));
      expect(
        query.ofType(LifeContextRelationType.eventParticipant),
        hasLength(1),
      );
      expect(
        graph.relations.where(
          (edge) => edge.provenance.evidenceType == 'freeTextParticipant',
        ),
        isEmpty,
      );
    });

    test('conserve série explicite et conflit sans décision', () {
      expect(
        query.ofType(LifeContextRelationType.seriesMembership),
        hasLength(1),
      );
      expect(graph.dependencies, isEmpty);
      expect(
        graph.nodes
            .where((node) => node.resourceType == LifeContextNodeType.event),
        hasLength(2),
      );
    });

    test('Task sans lien reste un nœud sans priorité ni dépendance', () {
      final task = graph.nodes.singleWhere(
        (node) => node.resourceType == LifeContextNodeType.task,
      );
      expect(query.outgoing(task.id), isEmpty);
      expect(query.incoming(task.id), isEmpty);
      expect(graph.dependencies, isEmpty);
      expect(task.toJson(), isNot(containsPair('priority', anything)));
    });

    test('Routine lie seulement la référence humaine structurée', () {
      expect(
        query.ofType(LifeContextRelationType.routineAssociation),
        hasLength(1),
      );
      expect(
        graph.nodes.where(
          (node) => node.resourceType == LifeContextNodeType.routine,
        ),
        hasLength(2),
      );
    });

    test('deux homonymes ne sont jamais rapprochés', () {
      final people = graph.nodes.where(
        (node) => node.resourceType == LifeContextNodeType.person,
      );
      expect(people.map((node) => node.sourceId).toSet(), hasLength(4));
      expect(
        graph.relations.where(
          (edge) => edge.provenance.ruleId.contains('name'),
        ),
        isEmpty,
      );
    });
  });

  group('dépendances, parcours, cycles et conséquences', () {
    test('distingue relation et dépendance explicite', () {
      final graph = _dependencyGraph([
        ('a', 'b'),
        ('b', 'c'),
        ('c', 'd'),
      ]);
      final query = LifeContextGraphQuery(graph);
      expect(query.directDependencies(_node('a').id), hasLength(1));
      expect(query.outgoing(_node('a').id), isEmpty);

      final full = query.transitiveDependencies(
        _node('a').id,
        maxDepth: 4,
      );
      expect(full.nodeIds, hasLength(3));
      expect(full.truncated, false);

      final bounded = query.transitiveDependencies(
        _node('a').id,
        maxDepth: 1,
      );
      expect(bounded.nodeIds, hasLength(1));
      expect(bounded.truncated, true);
    });

    test('refuse un parcours sans limites valides', () {
      final query = LifeContextGraphQuery(_dependencyGraph([('a', 'b')]));
      expect(
        () => query.transitiveDependencies(_node('a').id, maxDepth: 0),
        throwsA(_graphError('invalid_traversal_limit')),
      );
    });

    test('détecte cycles simple et triple de manière déterministe', () {
      final simple = LifeContextGraphQuery(
        _dependencyGraph([('a', 'b'), ('b', 'a')]),
      ).dependencyCycles();
      expect(simple, hasLength(1));
      expect(simple.single.nodeIds.first, simple.single.nodeIds.last);

      final tripleGraph = _dependencyGraph([
        ('a', 'b'),
        ('b', 'c'),
        ('c', 'a'),
      ]);
      final first = LifeContextGraphQuery(tripleGraph).dependencyCycles();
      final second = LifeContextGraphQuery(tripleGraph).dependencyCycles();
      expect(first, hasLength(1));
      expect(first.single.nodeIds, second.single.nodeIds);
      expect(first.single.dependencyIds, second.single.dependencyIds);
    });

    test('les cycles relationnels ne sont pas des cycles de dépendance', () {
      final graph = const LifeContextRelationEngine().build(_snapshot(at));
      expect(LifeContextGraphQuery(graph).dependencyCycles(), isEmpty);
    });

    test('conséquences restent techniques, bornées et explicables', () {
      final graph = const LifeContextRelationEngine().build(_snapshot(at));
      final query = LifeContextGraphQuery(graph);
      final person = _id(LifeContextNodeType.person, 'person-main');
      final consequences = query.consequencesOf(
        person,
        maxDepth: 2,
        maxVisitedNodes: 20,
      );
      expect(consequences, isNotEmpty);
      expect(
        consequences.map((item) => item.impactType),
        contains(LifeContextImpactType.revalidateMembership),
      );
      expect(
        consequences.map((item) => item.ruleId),
        everyElement(isNot(isEmpty)),
      );
      expect(
        consequences.toString(),
        isNot(anyOf(contains('recommend'), contains('priority'))),
      );
    });
  });
}

LifeContextSnapshot _snapshot(
  DateTime at, {
  bool empty = false,
  HumanContextSection? human,
}) {
  final humanSection = human ?? (empty ? _emptyHuman(at) : _human(at));
  return LifeContextSnapshot(
    generatedAt: at,
    identity: const IdentityContext(),
    household: HouseholdContext(),
    places: const PlaceContext(),
    mobility: const MobilityContext(),
    work: WorkContext(),
    agenda: AgendaContext(),
    routines: RoutineContext(),
    goals: GoalContext(),
    preferences: PreferenceContext(
      wantsNotifications: LifeContextFact(
        value: false,
        provenance: LifeContextProvenance(
          sourceType: LifeContextSourceType.derived,
          evidenceType: LifeContextEvidenceType.derived,
          sourceId: 'testShell',
        ),
      ),
    ),
    constraints: const ConstraintContext(),
    notes: const NotesContext(),
    accountScopeId: 'account-a',
    snapshotId: 'snapshot-a',
    globalState: LifeContextGlobalState.complete,
    settingsDomain: SettingsContextSection(
      metadata: _metadata(
        LifeContextDomain.settings,
        LifeContextSourceKind.settingsRegistry,
        at,
        1,
      ),
      automaticTravelCalculationEnabled: false,
      notificationsEnabled: false,
      notificationSoundEnabled: false,
      notificationVibrationEnabled: false,
      notificationBadgeEnabled: false,
      actionAutonomyMode: 'suggestions',
      memoryGeneralMode: 'askEveryTime',
      memoryHealthMode: 'disabled',
    ),
    human: humanSection,
    identityDomain: IdentityDomainSection(
      metadata: _metadata(
        LifeContextDomain.identity,
        LifeContextSourceKind.identityLinks,
        at,
        empty ? 0 : 2,
      ),
      links: empty
          ? const []
          : const [
              IdentityContextLink(
                humanPersonId: 'person-child',
                entityId: 'identity-child',
                entityType: 'person',
                confirmed: true,
              ),
              IdentityContextLink(
                humanPersonId: 'person-helper',
                entityId: 'identity-helper',
                entityType: 'person',
                confirmed: false,
              ),
            ],
    ),
    eventDomain: EventDomainSection(
      metadata: _metadata(
        LifeContextDomain.event,
        LifeContextSourceKind.eventService,
        at,
        empty ? 0 : 2,
      ),
      events: empty
          ? const []
          : const [
              EventContextItem(
                id: 'event-a',
                title: 'medical-secret must not enter graph',
                startDateTimeIso: '2026-07-24T10:00:00.000Z',
                endDateTimeIso: '2026-07-24T11:00:00.000Z',
                durationMinutes: 60,
                travelGoMinutes: 10,
                travelBackMinutes: 10,
                marginMinutes: 5,
                isRecurring: true,
                recurringType: 'weekly',
                revision: 2,
                syncStatus: 'conflict',
                participantEntityId: 'identity-child',
                parentRecurringId: 'series-a',
              ),
              EventContextItem(
                id: 'event-free-text',
                title: 'Alex',
                startDateTimeIso: '2026-07-25T10:00:00.000Z',
                endDateTimeIso: '2026-07-25T11:00:00.000Z',
                durationMinutes: 60,
                travelGoMinutes: 0,
                travelBackMinutes: 0,
                marginMinutes: 0,
                isRecurring: false,
                recurringType: '',
                revision: 1,
                syncStatus: 'synced',
              ),
            ],
    ),
    taskDomain: TaskDomainSection(
      metadata: _metadata(
        LifeContextDomain.task,
        LifeContextSourceKind.taskService,
        at,
        empty ? 0 : 1,
      ),
      tasks: empty
          ? const []
          : const [
              TaskContextItem(
                id: 'task-a',
                title: 'Same title as event',
                isCompleted: false,
                dueDate: '2026-07-24',
                durationMinutes: null,
                syncStatus: 'unknown',
              ),
            ],
    ),
    routineDomain: RoutineDomainSection(
      metadata: _metadata(
        LifeContextDomain.routine,
        LifeContextSourceKind.legacyProfileRoutine,
        at,
        empty ? 0 : 2,
      ),
      routines: empty
          ? const []
          : const [
              RoutineContextItem(
                id: 'routine-linked',
                source: 'legacyProfile.schoolTimeRanges',
                label: 'Secret routine label',
                days: ['monday'],
                startTime: '08:00',
                endTime: '09:00',
                travelMinutes: 5,
                humanPersonId: 'person-child',
              ),
              RoutineContextItem(
                id: 'routine-unlinked',
                source: 'legacyProfile.personalActivities',
                label: 'Alex',
                days: ['monday'],
                startTime: null,
                endTime: null,
                travelMinutes: null,
              ),
            ],
    ),
  );
}

HumanContextSection _emptyHuman(DateTime at) => HumanContextSection(
      metadata: _metadata(
        LifeContextDomain.human,
        LifeContextSourceKind.humanModelLocal,
        at,
        0,
      ),
      primaryPersonId: null,
    );

HumanContextSection _human(
  DateTime at, {
  List<HumanContextRecord>? relationships,
}) =>
    HumanContextSection(
      metadata: _metadata(
        LifeContextDomain.human,
        LifeContextSourceKind.humanModelLocal,
        at,
        20,
      ),
      primaryPersonId: 'person-main',
      persons: const [
        HumanContextPerson(
          id: 'person-main',
          displayName: 'Alex',
          status: 'active',
          confirmation: 'confirmed',
        ),
        HumanContextPerson(
          id: 'person-child',
          displayName: 'Camille',
          status: 'active',
          confirmation: 'confirmed',
          identityEntityId: 'identity-child',
        ),
        HumanContextPerson(
          id: 'person-helper',
          displayName: 'Alex',
          status: 'active',
          confirmation: 'needsConfirmation',
        ),
        HumanContextPerson(
          id: 'person-second',
          displayName: 'Morgan',
          status: 'active',
          confirmation: 'confirmed',
        ),
      ],
      relationships: relationships ??
          [
            _record(
              'relationship-partner',
              'partner',
              const ['person-main', 'person-second'],
              source: 'person-main',
              target: 'person-second',
            ),
            _record(
              'relationship-parent',
              'parent',
              const ['person-main', 'person-child'],
              source: 'person-main',
              target: 'person-child',
            ),
            _record(
              'relationship-half',
              'halfSibling',
              const ['person-child', 'person-helper'],
              source: 'person-child',
              target: 'person-helper',
              confirmation: 'needsConfirmation',
              evidence: 'legacyProfile',
            ),
            _record(
              'relationship-old',
              'formerPartner',
              const ['person-main', 'person-helper'],
              source: 'person-main',
              target: 'person-helper',
              status: 'historical',
              confirmation: 'historical',
              until: DateTime.utc(2025),
            ),
            _record(
              'relationship-future',
              'caregiver',
              const ['person-helper', 'person-child'],
              source: 'person-helper',
              target: 'person-child',
              from: DateTime.utc(2027),
            ),
            _record(
              'relationship-rejected',
              'stepParent',
              const ['person-helper', 'person-child'],
              source: 'person-helper',
              target: 'person-child',
              confirmation: 'rejected',
            ),
          ],
      households: [
        _record('household-a', 'primary', const []),
        _record('household-b', 'secondary', const []),
      ],
      residences: [
        _record(
          'residence-a',
          'primary',
          const ['household-a', 'person-main'],
          householdIds: const ['household-a'],
          personIds: const ['person-main'],
        ),
        _record(
          'residence-b',
          'secondary',
          const ['household-b'],
          householdIds: const ['household-b'],
        ),
      ],
      memberships: [
        _record(
          'membership-main',
          'permanentMember',
          const ['person-main', 'household-a'],
          source: 'person-main',
          target: 'household-a',
        ),
        _record(
          'membership-child-a',
          'alternatingMember',
          const ['person-child', 'household-a'],
          source: 'person-child',
          target: 'household-a',
        ),
        _record(
          'membership-child-b',
          'alternatingMember',
          const ['person-child', 'household-b'],
          source: 'person-child',
          target: 'household-b',
        ),
      ],
      responsibilities: [
        _record(
          'responsibility-main-child',
          'parental',
          const ['person-main', 'person-child'],
          source: 'person-main',
          target: 'person-child',
        ),
        _record(
          'responsibility-helper-child',
          'transport',
          const ['person-helper', 'person-child'],
          source: 'person-helper',
          target: 'person-child',
        ),
        _record(
          'responsibility-main-second',
          'dailyAssistance',
          const ['person-main', 'person-second'],
          source: 'person-main',
          target: 'person-second',
        ),
      ],
    );

HumanContextRecord _record(
  String id,
  String kind,
  List<String> references, {
  String status = 'active',
  String confirmation = 'confirmed',
  String evidence = 'explicitUserInput',
  String? source,
  String? target,
  DateTime? from,
  DateTime? until,
  List<String> householdIds = const [],
  List<String> personIds = const [],
}) =>
    HumanContextRecord(
      id: id,
      kind: kind,
      references: references,
      status: status,
      confirmation: confirmation,
      validFrom: from,
      validUntil: until,
      sourceReferenceId: source,
      targetReferenceId: target,
      householdIds: householdIds,
      personIds: personIds,
      evidenceSource: evidence,
    );

LifeContextSourceMetadata _metadata(
  LifeContextDomain domain,
  LifeContextSourceKind source,
  DateTime at,
  int count,
) =>
    LifeContextSourceMetadata(
      domain: domain,
      source: source,
      readAt: at,
      availability: count == 0
          ? LifeContextAvailability.empty
          : LifeContextAvailability.available,
      freshness: LifeContextFreshness.current,
      isLocal: domain == LifeContextDomain.human ||
          domain == LifeContextDomain.identity ||
          domain == LifeContextDomain.routine,
      itemCount: count,
      revision: domain == LifeContextDomain.human ||
              domain == LifeContextDomain.identity ||
              domain == LifeContextDomain.routine
          ? 3
          : null,
    );

LifeContextGraph _dependencyGraph(List<(String, String)> links) {
  final ids = links.expand((link) => [link.$1, link.$2]).toSet().toList()
    ..sort();
  final nodes = ids.map(_node).toList();
  final dependencies = links
      .map(
        (link) => LifeContextDependency(
          prerequisiteNodeId: _node(link.$1).id,
          dependentNodeId: _node(link.$2).id,
          type: LifeContextDependencyType.explicitUserDependency,
          provenance: _provenance('${link.$1}-${link.$2}'),
        ),
      )
      .toList();
  return LifeContextGraph(
    accountScopeId: 'account-a',
    snapshotId: 'snapshot-a',
    nodes: nodes,
    relations: const [],
    dependencies: dependencies,
  );
}

LifeContextGraphNode _node(String id) => LifeContextGraphNode(
      domain: LifeContextDomain.task,
      sourceId: id,
      resourceType: LifeContextNodeType.task,
      accountScopeId: 'account-a',
    );

LifeContextRelationProvenance _provenance(String id) =>
    LifeContextRelationProvenance(
      sourceDomain: LifeContextDomain.task,
      sourceRecordId: id,
      evidenceType: 'structuredTestDependency',
      confirmation: LifeContextConfirmation.confirmed,
      ruleId: LifeContextRegisteredRuleIds.explicitDependency,
      ruleVersion: 1,
      readAt: DateTime.utc(2026),
      snapshotId: 'snapshot-a',
      sectionSource: LifeContextSourceKind.taskService,
      nature: LifeContextRelationNature.direct,
    );

String _id(LifeContextNodeType type, String sourceId) =>
    LifeContextGraphNode.deterministicId(
      LifeContextDomain.human,
      type,
      sourceId,
    );

Matcher _graphError(String code) => isA<LifeContextGraphException>()
    .having((error) => error.code, 'code', code);
