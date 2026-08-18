import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_id_generator.dart';
import 'package:moms_ai/models/life_context/identity_context.dart';
import 'package:moms_ai/models/life_context/intent_context.dart';
import 'package:moms_ai/models/life_context/life_context_domains.dart';
import 'package:moms_ai/models/life_context/life_context_graph.dart';
import 'package:moms_ai/models/life_context/life_context_projection.dart';
import 'package:moms_ai/models/life_context/life_context_provenance.dart';
import 'package:moms_ai/models/life_context/life_context_snapshot.dart';
import 'package:moms_ai/models/life_context/notes_context.dart';
import 'package:moms_ai/models/life_context/schedule_context.dart';
import 'package:moms_ai/services/life_context/life_context_projection_compatibility.dart';
import 'package:moms_ai/services/life_context/life_context_domain_adapters.dart';
import 'package:moms_ai/services/life_context/life_context_projection_engine.dart';
import 'package:moms_ai/services/life_context/life_context_relation_engine.dart';

void main() {
  final now = DateTime.utc(2026, 7, 23, 12);

  group('contrats fermés et modèle LC.3', () {
    test('contrats Conversation et Planning sont bornés et versionnés', () {
      final conversation = LifeContextConsumerContract.forPurpose(
        LifeContextConsumerPurpose.conversation,
      );
      final planning = LifeContextConsumerContract.forPurpose(
        LifeContextConsumerPurpose.planning,
      );
      expect(
        conversation.schemaVersion,
        LifeContextConsumerContract.currentSchemaVersion,
      );
      expect(conversation.globalBudget, greaterThan(0));
      expect(planning.globalBudget, greaterThan(0));
      expect(
        conversation.sectionBudgets.values,
        everyElement(greaterThan(0)),
      );
      expect(planning.maxRelationDepth, greaterThanOrEqualTo(0));
      expect(
        conversation.allowedSensitivities,
        isNot(contains(LifeContextSensitivityLevel.highlySensitive)),
      );
    });

    test('version future de contrat et de projection est refusée', () {
      expect(
        () => LifeContextConsumerContract.forPurpose(
          LifeContextConsumerPurpose.conversation,
          schemaVersion: 2,
        ),
        throwsA(_projectionError('unsupported_consumer_contract_version')),
      );
      expect(
        () => LifeContextProjection(
          schemaVersion: 2,
          projectionId: 'projection',
          sourceSnapshotId: 'snapshot',
          accountScopeId: 'account-a',
          purpose: LifeContextConsumerPurpose.conversation,
          generatedAt: now,
          state: LifeContextProjectionState.complete,
          budgetRequested: 1,
          budgetUsed: 0,
          sections: [
            LifeContextProjectionSection(
              type: LifeContextProjectionSectionType.human,
              availability: LifeContextAvailability.empty,
              freshness: LifeContextFreshness.current,
              items: const [],
              budgetLimit: 1,
              budgetUsed: 0,
              omittedCount: 0,
              truncated: false,
            ),
          ],
          omittedCount: 0,
          warningCodes: const [],
        ),
        throwsA(_projectionError('unsupported_projection_version')),
      );
    });

    test('champ inconnu et donnée hautement sensible sont refusés', () {
      expect(
        () => LifeContextProjectionFact(
          key: 'unknownField',
          value: 'value',
          sensitivity: LifeContextSensitivityLevel.publicTechnical,
        ),
        throwsA(_projectionError('invalid_projection_fact')),
      );
      expect(
        () => LifeContextProjectionFact(
          key: LifeContextProjectionFactKeys.status,
          value: 'token',
          sensitivity: LifeContextSensitivityLevel.highlySensitive,
        ),
        throwsA(_projectionError('invalid_projection_fact')),
      );
    });
  });

  group('budget, sélection et sensibilité', () {
    test('respecte budgets global et par section avec troncature explicite',
        () {
      final projection = _build(
        _snapshot(now, eventCount: 8),
        LifeContextConsumerPurpose.conversation,
      );
      final eventSection = _section(
        projection,
        LifeContextProjectionSectionType.event,
      );
      expect(eventSection.budgetUsed, lessThan(eventSection.budgetLimit));
      expect(eventSection.items, hasLength(4));
      expect(eventSection.omittedCount, 4);
      expect(eventSection.truncated, true);
      expect(
          projection.budgetUsed, lessThanOrEqualTo(projection.budgetRequested));
      expect(projection.omittedCount, greaterThan(0));
      expect(projection.warningCodes, contains('projection_truncated'));
    });

    test('mêmes données donnent la même sélection et le même ordre', () {
      final snapshot = _snapshot(now, eventCount: 8);
      final first = _build(snapshot, LifeContextConsumerPurpose.conversation);
      final second = _build(snapshot, LifeContextConsumerPurpose.conversation);
      expect(
        _selection(first),
        _selection(second),
      );
      expect(
          first.sections.map((section) => section.type.index),
          orderedEquals(
            [...first.sections.map((section) => section.type.index)]..sort(),
          ));
    });

    test('Priority proactive retains 100 compact Tasks and truncates overflow',
        () {
      final complete = _build(
        _snapshot(now, taskCount: 100, allTasksActive: true),
        LifeContextConsumerPurpose.proactivePriority,
      );
      final completeTasks =
          _section(complete, LifeContextProjectionSectionType.task);
      expect(completeTasks.items, hasLength(100));
      expect(completeTasks.truncated, isFalse);
      expect(complete.state, LifeContextProjectionState.complete);
      expect(
        completeTasks.items.expand((item) => item.facts),
        isNot(contains(predicate<LifeContextProjectionFact>(
          (fact) => fact.key == LifeContextProjectionFactKeys.title,
        ))),
      );

      final overflow = _build(
        _snapshot(now, taskCount: 101, allTasksActive: true),
        LifeContextConsumerPurpose.proactivePriority,
      );
      final overflowTasks =
          _section(overflow, LifeContextProjectionSectionType.task);
      expect(overflowTasks.truncated, isTrue);
      expect(overflow.warningCodes, contains('projection_truncated'));
      expect(overflow.state, LifeContextProjectionState.partial);
    });

    test('Priority proactive receives normalized structured Task signals', () {
      final projection = _build(
        _snapshot(now, taskCount: 1, structuredTaskPriority: true),
        LifeContextConsumerPurpose.proactivePriority,
      );
      final task = _section(
        projection,
        LifeContextProjectionSectionType.task,
      ).items.single;
      final facts = {for (final fact in task.facts) fact.key: fact.value};

      expect(facts[LifeContextProjectionFactKeys.dueDate], '2026-07-25');
      expect(facts[LifeContextProjectionFactKeys.importance], '1.0');
      expect(facts[LifeContextProjectionFactKeys.urgency], '0.9');
      expect(facts[LifeContextProjectionFactKeys.category], 'personal');
      expect(
        facts[LifeContextProjectionFactKeys.createdAt],
        '2026-07-20T00:00:00.000Z',
      );
      expect(facts, isNot(contains(LifeContextProjectionFactKeys.title)));
    });

    test('texte libre est nettoyé et borné', () {
      final projection = _build(
        _snapshot(now, eventTitle: '${'A' * 100}\nsecret'),
        LifeContextConsumerPurpose.conversation,
      );
      final title = _section(
        projection,
        LifeContextProjectionSectionType.event,
      )
          .items
          .single
          .facts
          .singleWhere(
            (fact) => fact.key == LifeContextProjectionFactKeys.title,
          )
          .value;
      expect(title.length, 80);
      expect(title, isNot(contains('\n')));
    });

    test('données médicales, urgences et payload legacy restent exclus', () {
      final projection = _build(
        _snapshot(now),
        LifeContextConsumerPurpose.conversation,
      );
      final output = projection.toJson().toString();
      expect(output, isNot(contains('medical-secret')));
      expect(output, isNot(contains('allergy-secret')));
      expect(output, isNot(contains('emergency-secret')));
      expect(output, isNot(contains('legacy-secret')));
      expect(output, isNot(contains('account-a')));
    });

    test('seules les personnes actives explicitement reliées sont exportées',
        () {
      final projection = _build(
        _snapshot(now),
        LifeContextConsumerPurpose.conversation,
      );
      final people = _section(
        projection,
        LifeContextProjectionSectionType.human,
      ).items.where((item) => item.type == 'person');
      expect(people, hasLength(2));
      expect(
        people.expand((person) => person.facts).map((fact) => fact.value),
        contains('Personne principale'),
      );
      expect(
        people.expand((person) => person.facts).map((fact) => fact.value),
        contains('Enfant secret'),
      );
      final childFacts = {
        for (final fact in people
            .singleWhere((item) => item.id == 'human:person:person-child')
            .facts)
          fact.key: fact.value,
      };
      expect(
        childFacts[LifeContextProjectionFactKeys.nodeId],
        'human:person:person-child',
      );
      expect(
        childFacts[LifeContextProjectionFactKeys.birthDate],
        '2018-06-05',
      );
      expect(
        childFacts[LifeContextProjectionFactKeys.personRole],
        'related',
      );
      final primaryFacts = {
        for (final fact in people
            .singleWhere((item) => item.id == 'human:person:person-main')
            .facts)
          fact.key: fact.value,
      };
      expect(
        primaryFacts[LifeContextProjectionFactKeys.familyStatus],
        'Je vis en couple',
      );
      expect(
        primaryFacts[LifeContextProjectionFactKeys.workStatus],
        'Je suis salariée',
      );
      expect(
        primaryFacts[LifeContextProjectionFactKeys.personRole],
        'primary',
      );
    });
  });

  group('projection Conversation', () {
    test('inclut faits minimaux, relation utile et incertitude marquée', () {
      final projection = _build(
        _snapshot(now),
        LifeContextConsumerPurpose.conversation,
      );
      expect(projection.purpose, LifeContextConsumerPurpose.conversation);
      expect(
        _section(projection, LifeContextProjectionSectionType.human).items,
        isNotEmpty,
      );
      final relations =
          _section(projection, LifeContextProjectionSectionType.relation).items;
      expect(relations, isNotEmpty);
      final confirmedRelation = relations.singleWhere(
        (item) => item.facts.any(
          (fact) =>
              fact.key == LifeContextProjectionFactKeys.relationRole &&
              fact.value == 'parent',
        ),
      );
      expect(
        {
          for (final fact in confirmedRelation.facts) fact.key: fact.value,
        }[LifeContextProjectionFactKeys.relationRole],
        'parent',
      );
      expect(
        relations.where(
          (item) =>
              item.confirmation == LifeContextConfirmation.needsConfirmation,
        ),
        isNotEmpty,
      );
      expect(
        relations.where(
          (item) => item.confirmation == LifeContextConfirmation.rejected,
        ),
        isEmpty,
      );
    });

    test('transporte les détails confirmés du couple vers la conversation', () {
      final snapshot = _snapshot(now);
      final confirmedPartner = HumanContextRecord(
        id: 'relationship-couple',
        kind: 'spouse',
        references: const ['person-main', 'person-partner'],
        status: 'active',
        confirmation: 'confirmed',
        sourceReferenceId: 'person-main',
        targetReferenceId: 'person-partner',
        relationshipStatus: 'Mariée',
        marriageDate: '12/08/2020',
      );
      final enriched = LifeContextSnapshot(
        generatedAt: snapshot.generatedAt,
        identity: snapshot.identity,
        household: snapshot.household,
        places: snapshot.places,
        mobility: snapshot.mobility,
        work: snapshot.work,
        agenda: snapshot.agenda,
        routines: snapshot.routines,
        goals: snapshot.goals,
        preferences: snapshot.preferences,
        constraints: snapshot.constraints,
        notes: snapshot.notes,
        memory: snapshot.memory,
        accountScopeId: snapshot.accountScopeId,
        snapshotId: snapshot.snapshotId,
        globalState: snapshot.globalState,
        human: HumanContextSection(
          metadata: snapshot.human!.metadata,
          primaryPersonId: snapshot.human!.primaryPersonId,
          persons: [
            ...snapshot.human!.persons,
            const HumanContextPerson(
              id: 'person-partner',
              displayName: 'Partenaire',
              status: 'active',
              confirmation: 'confirmed',
            ),
          ],
          relationships: [
            ...snapshot.human!.relationships,
            confirmedPartner,
          ],
          households: snapshot.human!.households,
          residences: snapshot.human!.residences,
          memberships: snapshot.human!.memberships,
          responsibilities: snapshot.human!.responsibilities,
        ),
        identityDomain: snapshot.identityDomain,
        eventDomain: snapshot.eventDomain,
        taskDomain: snapshot.taskDomain,
        routineDomain: snapshot.routineDomain,
        memoryDomain: snapshot.memoryDomain,
      );

      final projection =
          _build(enriched, LifeContextConsumerPurpose.conversation);
      final relationship = _section(
        projection,
        LifeContextProjectionSectionType.human,
      ).items.singleWhere((item) => item.id.contains('relationship-couple'));
      final facts = {
        for (final fact in relationship.facts) fact.key: fact.value,
      };
      expect(facts[LifeContextProjectionFactKeys.relationshipStatus], 'Mariée');
      expect(facts[LifeContextProjectionFactKeys.marriageDate], '2020-08-12');
    });

    test('identifie le type et la personne de chaque horaire du profil', () {
      final projection = _build(
        _snapshot(now),
        LifeContextConsumerPurpose.conversation,
      );
      final routine = _section(
        projection,
        LifeContextProjectionSectionType.routine,
      ).items.single;
      final facts = {
        for (final fact in routine.facts) fact.key: fact.value,
      };
      expect(
        facts[LifeContextProjectionFactKeys.routineKind],
        'schoolSchedule',
      );
      expect(
        facts[LifeContextProjectionFactKeys.subjectNodeId],
        'human:person:person-child',
      );
      expect(
        facts.containsKey(LifeContextProjectionFactKeys.travelGoMinutes),
        isFalse,
      );
      expect(routine.facts.length, lessThanOrEqualTo(12));
    });

    test('transporte un profil complet avec plusieurs horaires', () {
      final projection = _build(
        _snapshot(now, routineCount: 8),
        LifeContextConsumerPurpose.conversation,
      );
      final routines = _section(
        projection,
        LifeContextProjectionSectionType.routine,
      );
      expect(routines.items, hasLength(8));
      expect(routines.omittedCount, 0);
      expect(routines.truncated, isFalse);
    });

    test('Planning conserve tous les éléments bornés d’un agenda chargé', () {
      final projection = _build(
        _snapshot(
          now,
          eventCount: LifeContextSourceBudgets.events,
          routineCount: LifeContextSourceBudgets.routines,
        ),
        LifeContextConsumerPurpose.planning,
      );
      final events =
          _section(projection, LifeContextProjectionSectionType.event);
      final routines =
          _section(projection, LifeContextProjectionSectionType.routine);

      expect(events.items, hasLength(60));
      expect(events.truncated, isFalse);
      expect(routines.items, hasLength(LifeContextSourceBudgets.routines));
      expect(routines.truncated, isFalse);
      expect(projection.warningCodes, isNot(contains('projection_truncated')));
    });

    test('filtre Events hors fenêtre et Tasks terminées', () {
      final projection = _build(
        _snapshot(now, includeOutsideEvent: true),
        LifeContextConsumerPurpose.conversation,
      );
      final events =
          _section(projection, LifeContextProjectionSectionType.event).items;
      final tasks =
          _section(projection, LifeContextProjectionSectionType.task).items;
      expect(events.map((item) => item.id), isNot(contains('event:event:old')));
      expect(tasks, hasLength(1));
      expect(tasks.single.id, contains('task-active'));
    });

    test('domaine indisponible est explicite et ne devient pas faux vide', () {
      final snapshot = _snapshot(
        now,
        taskAvailability: LifeContextAvailability.unavailable,
      );
      final projection =
          _build(snapshot, LifeContextConsumerPurpose.conversation);
      final tasks = _section(projection, LifeContextProjectionSectionType.task);
      expect(tasks.availability, LifeContextAvailability.unavailable);
      expect(tasks.warningCode, 'unavailable_section');
      expect(projection.state, LifeContextProjectionState.partial);
    });

    test('adaptateur ChatBackendRequest évite double contexte complet', () {
      final projection = _build(
        _snapshot(now),
        LifeContextConsumerPurpose.conversation,
      );
      final request =
          LifeContextConversationProjectionAdapter.toChatBackendRequest(
        message: 'Bonjour',
        projection: projection,
      );
      expect(request.profile, isEmpty);
      expect(request.profileContext, isEmpty);
      expect(request.events, isEmpty);
      expect(request.context, isNotNull);
      final json = request.toJson().toString();
      expect(json, isNot(contains('sourceSnapshotId')));
      expect(json, isNot(contains('LifeContextGraph')));
      expect(json, isNot(contains('legacy-secret')));
    });
  });

  group('projection Planning', () {
    test('inclut temps, trajets, marges, récurrence, conflit et révision', () {
      final projection = _build(
        _snapshot(now, eventLocation: 'Clinique Saint-Jean'),
        LifeContextConsumerPurpose.planning,
      );
      final event = _section(projection, LifeContextProjectionSectionType.event)
          .items
          .single;
      final facts = {for (final fact in event.facts) fact.key: fact.value};
      expect(facts[LifeContextProjectionFactKeys.start], isNotNull);
      expect(facts[LifeContextProjectionFactKeys.travelGoMinutes], '10');
      expect(facts[LifeContextProjectionFactKeys.travelBackMinutes], '15');
      expect(facts[LifeContextProjectionFactKeys.marginMinutes], '5');
      expect(facts[LifeContextProjectionFactKeys.recurringType], 'weekly');
      expect(facts[LifeContextProjectionFactKeys.syncStatus], 'conflict');
      expect(facts[LifeContextProjectionFactKeys.revision], '3');
      expect(
        facts[LifeContextProjectionFactKeys.location],
        'Clinique Saint-Jean',
      );
      expect(facts, isNot(contains(LifeContextProjectionFactKeys.title)));
    });

    test('exclut Task, noms, notes, priorité et recommandation', () {
      final projection =
          _build(_snapshot(now), LifeContextConsumerPurpose.planning);
      expect(
        projection.sections.map((section) => section.type),
        isNot(contains(LifeContextProjectionSectionType.task)),
      );
      final output = projection.toJson().toString();
      expect(output, isNot(contains('Personne principale')));
      expect(output, isNot(contains('Event visible')));
      expect(output, isNot(contains('priority')));
      expect(output, isNot(contains('recommendation')));
    });

    test('adaptateur planning produit uniquement des faits typés', () {
      final projection =
          _build(_snapshot(now), LifeContextConsumerPurpose.planning);
      final context =
          LifeContextPlanningProjectionAdapter.toPlanningContext(projection);
      expect(context.events, hasLength(1));
      expect(context.events.single.travelGoMinutes, 10);
      expect(context.routines, hasLength(1));
      expect(context.primaryPersonNodeId, 'human:person:person-main');
      expect(
        context.routines.single.subjectNodeId,
        'human:person:person-child',
      );
      expect(
        context.routines.single.toPlanningReasoning(
          primaryPersonNodeId: context.primaryPersonNodeId,
        ),
        containsPair('type', 'other_person_schedule'),
      );
      expect(context.temporalResponsibilities, hasLength(1));
      expect(context.planningConsequences, isEmpty);
    });

    test('projette seulement une conséquence temporelle explicitement bornée',
        () {
      final projection = _build(
        _snapshot(
          now,
          planningConsequenceType: 'transport',
          planningConsequenceStart: now.add(const Duration(hours: 2)),
          planningConsequenceEnd:
              now.add(const Duration(hours: 2, minutes: 20)),
          blocksResponsiblePerson: true,
        ),
        LifeContextConsumerPurpose.planning,
      );
      final context =
          LifeContextPlanningProjectionAdapter.toPlanningContext(projection);

      expect(context.planningConsequences, hasLength(1));
      final consequence = context.planningConsequences.single;
      expect(consequence.kind, 'transport');
      expect(
        consequence.responsiblePersonNodeId,
        'human:person:person-main',
      );
      expect(
        consequence.subjectPersonNodeId,
        'human:person:person-child',
      );
      final blocker = consequence.toBlockingEvent();
      expect(blocker, isNotNull);
      expect(blocker!.category, 'Responsabilité');
      expect(blocker.title, 'Un trajet à assurer');
    });

    test(
        'projette une conséquence récurrente sans bloquer le planning du tiers',
        () {
      final projection = _build(
        _snapshot(
          now,
          planningConsequenceType: 'transport',
          planningConsequenceWeekdays: const [
            DateTime.monday,
            DateTime.thursday,
          ],
          planningConsequenceStartTime: '08:20',
          planningConsequenceEndTime: '08:40',
          blocksResponsiblePerson: true,
        ),
        LifeContextConsumerPurpose.planning,
      );
      final context =
          LifeContextPlanningProjectionAdapter.toPlanningContext(projection);

      expect(context.planningConsequences, isEmpty);
      expect(context.recurringPlanningConsequences, hasLength(1));
      final consequence = context.recurringPlanningConsequences.single;
      expect(consequence.kind, 'transport');
      expect(
        consequence.responsiblePersonNodeId,
        'human:person:person-main',
      );
      expect(
        consequence.subjectPersonNodeId,
        'human:person:person-child',
      );
      expect(
        consequence.weekdays,
        [DateTime.monday, DateTime.thursday],
      );
      expect(consequence.startTime, '08:20');
      expect(consequence.endTime, '08:40');
      expect(
        consequence.toBlockedPeriod(),
        containsPair('days', ['1', '4']),
      );
    });

    test('ne transforme pas la validité générale en temps bloqué', () {
      final projection = _build(
        _snapshot(now),
        LifeContextConsumerPurpose.planning,
      );
      final responsibility = _section(
        projection,
        LifeContextProjectionSectionType.human,
      ).items.singleWhere((item) => item.type == 'responsibility');
      final facts = {
        for (final fact in responsibility.facts) fact.key: fact.value,
      };

      expect(facts, isNot(contains(LifeContextProjectionFactKeys.start)));
      expect(facts, isNot(contains(LifeContextProjectionFactKeys.end)));
      expect(
        LifeContextPlanningProjectionAdapter.toPlanningContext(projection)
            .planningConsequences,
        isEmpty,
      );
    });

    test('domaine indispensable indisponible échoue explicitement', () {
      expect(
        () => _build(
          _snapshot(
            now,
            eventAvailability: LifeContextAvailability.unavailable,
          ),
          LifeContextConsumerPurpose.planning,
        ),
        throwsA(
          _projectionError('required_projection_domain_unavailable'),
        ),
      );
    });

    test('routine locale périmée est conservée et signalée', () {
      final projection = _build(
        _snapshot(now, routineStale: true),
        LifeContextConsumerPurpose.planning,
      );
      final routine =
          _section(projection, LifeContextProjectionSectionType.routine);
      expect(routine.freshness, LifeContextFreshness.stale);
      expect(routine.warningCode, 'stale_section');
      expect(projection.state, LifeContextProjectionState.partial);
    });

    test('contrat strict refuse une section périmée', () {
      expect(
        () => _build(
          _snapshot(now, routineStale: true),
          LifeContextConsumerPurpose.planning,
          contract: LifeContextConsumerContract.forPurpose(
            LifeContextConsumerPurpose.planning,
          ).requiringFreshData(),
        ),
        throwsA(_projectionError('stale_projection_domain_not_allowed')),
      );
    });

    test('historique est exclu par défaut et inclus sur demande explicite', () {
      final snapshot = _snapshot(now, expiredResponsibility: true);
      final standard = _build(
        snapshot,
        LifeContextConsumerPurpose.planning,
      );
      final withHistory = _build(
        snapshot,
        LifeContextConsumerPurpose.planning,
        contract: LifeContextConsumerContract.forPurpose(
          LifeContextConsumerPurpose.planning,
        ).includingHistoricalData(),
      );
      expect(
        _section(standard, LifeContextProjectionSectionType.human)
            .items
            .where((item) => item.type == 'responsibility'),
        isEmpty,
      );
      expect(
        _section(standard, LifeContextProjectionSectionType.human)
            .items
            .where((item) => item.type == 'person'),
        hasLength(1),
      );
      expect(
        _section(withHistory, LifeContextProjectionSectionType.human)
            .items
            .where((item) => item.type == 'responsibility'),
        hasLength(1),
      );
    });
  });

  group('isolation, LC.2 et résilience', () {
    test('mauvais graphe ou snapshot est refusé', () {
      final snapshot = _snapshot(now);
      final graph = LifeContextGraph(
        accountScopeId: 'account-b',
        snapshotId: snapshot.snapshotId!,
        nodes: const [],
        relations: const [],
      );
      expect(
        () => LifeContextProjectionEngine(
          projectionIdGenerator: const _FixedIdGenerator(),
        ).build(
          snapshot: snapshot,
          graph: graph,
          contract: LifeContextConsumerContract.forPurpose(
            LifeContextConsumerPurpose.conversation,
          ),
        ),
        throwsA(_projectionError('projection_source_mismatch')),
      );
    });

    test('graphe absent reste explicite sans sérialisation implicite', () {
      final projection = LifeContextProjectionEngine(
        projectionIdGenerator: const _FixedIdGenerator(),
      ).build(
        snapshot: _snapshot(now),
        contract: LifeContextConsumerContract.forPurpose(
          LifeContextConsumerPurpose.conversation,
        ),
      );
      final relations =
          _section(projection, LifeContextProjectionSectionType.relation);
      expect(relations.availability, LifeContextAvailability.unsupported);
      expect(relations.items, isEmpty);
      expect(projection.state, LifeContextProjectionState.partial);
    });

    test('relations restent bornées et graphe complet jamais copié', () {
      final projection =
          _build(_snapshot(now), LifeContextConsumerPurpose.conversation);
      final relations =
          _section(projection, LifeContextProjectionSectionType.relation);
      final contract = LifeContextConsumerContract.forPurpose(
        LifeContextConsumerPurpose.conversation,
      );
      expect(relations.items.length, lessThanOrEqualTo(contract.maxRelations));
      expect(
        projection.toJson(),
        isNot(containsPair('nodes', anything)),
      );
      expect(
        projection.toJson(),
        isNot(containsPair('relations', anything)),
      );
    });
  });
}

LifeContextProjection _build(
  LifeContextSnapshot snapshot,
  LifeContextConsumerPurpose purpose, {
  LifeContextConsumerContract? contract,
}) {
  final graph = const LifeContextRelationEngine().build(snapshot);
  return LifeContextProjectionEngine(
    projectionIdGenerator: const _FixedIdGenerator(),
  ).build(
    snapshot: snapshot,
    graph: graph,
    contract: contract ?? LifeContextConsumerContract.forPurpose(purpose),
  );
}

LifeContextSnapshot _snapshot(
  DateTime now, {
  int eventCount = 1,
  String eventTitle = 'Event visible',
  bool includeOutsideEvent = false,
  LifeContextAvailability eventAvailability = LifeContextAvailability.available,
  LifeContextAvailability taskAvailability = LifeContextAvailability.available,
  int taskCount = 2,
  bool allTasksActive = false,
  bool routineStale = false,
  bool expiredResponsibility = false,
  int routineCount = 1,
  String? planningConsequenceType,
  DateTime? planningConsequenceStart,
  DateTime? planningConsequenceEnd,
  List<int> planningConsequenceWeekdays = const [],
  String? planningConsequenceStartTime,
  String? planningConsequenceEndTime,
  bool blocksResponsiblePerson = false,
  String? eventLocation,
  bool structuredTaskPriority = false,
}) {
  final events = <EventContextItem>[
    for (var index = 0; index < eventCount; index++)
      EventContextItem(
        id: 'event-$index',
        title: eventTitle,
        startDateTimeIso: now.add(Duration(days: index + 1)).toIso8601String(),
        endDateTimeIso:
            now.add(Duration(days: index + 1, hours: 1)).toIso8601String(),
        durationMinutes: 60,
        travelGoMinutes: 10,
        travelBackMinutes: 15,
        marginMinutes: 5,
        isRecurring: index == 0,
        recurringType: index == 0 ? 'weekly' : '',
        revision: 3,
        syncStatus: index == 0 ? 'conflict' : 'synced',
        participantEntityId: index == 0 ? 'identity-child' : null,
        location: index == 0 ? eventLocation : null,
      ),
    if (includeOutsideEvent)
      EventContextItem(
        id: 'old',
        title: 'Old',
        startDateTimeIso:
            now.subtract(const Duration(days: 30)).toIso8601String(),
        endDateTimeIso:
            now.subtract(const Duration(days: 30, hours: -1)).toIso8601String(),
        durationMinutes: 60,
        travelGoMinutes: 0,
        travelBackMinutes: 0,
        marginMinutes: 0,
        isRecurring: false,
        recurringType: '',
        revision: 1,
        syncStatus: 'synced',
      ),
  ];
  return LifeContextSnapshot(
    generatedAt: now,
    identity: const IdentityContext(),
    household: HouseholdContext(),
    places: const PlaceContext(),
    mobility: const MobilityContext(),
    work: WorkContext(),
    agenda: AgendaContext(),
    routines: RoutineContext(),
    goals: GoalContext(),
    preferences: PreferenceContext(
      wantsNotifications: _legacyFact(false, 'notifications'),
    ),
    constraints: ConstraintContext(
      allergies: _legacyString('allergy-secret', 'allergies'),
      medicalNotes: _legacyString('medical-secret', 'medical'),
      emergencyContactName: _legacyString('emergency-secret', 'emergency'),
    ),
    notes: NotesContext(
      personalNotes: _legacyString('legacy-secret', 'notes'),
    ),
    accountScopeId: 'account-a',
    snapshotId: 'snapshot-a',
    globalState: LifeContextGlobalState.complete,
    human: HumanContextSection(
      metadata: _metadata(
        LifeContextDomain.human,
        LifeContextSourceKind.humanModelLocal,
        now,
        LifeContextAvailability.available,
      ),
      primaryPersonId: 'person-main',
      persons: const [
        HumanContextPerson(
          id: 'person-main',
          displayName: 'Personne principale',
          status: 'active',
          confirmation: 'confirmed',
          familyStatus: 'Je vis en couple',
          workStatus: 'Je suis salariée',
        ),
        HumanContextPerson(
          id: 'person-child',
          displayName: 'Enfant secret',
          status: 'active',
          confirmation: 'confirmed',
          identityEntityId: 'identity-child',
          birthDate: '2018-06-05',
        ),
      ],
      relationships: [
        HumanContextRecord(
          id: 'relationship-confirmed',
          kind: 'parent',
          references: const ['person-main', 'person-child'],
          status: 'active',
          confirmation: 'confirmed',
          sourceReferenceId: 'person-main',
          targetReferenceId: 'person-child',
          evidenceSource: 'explicitUserInput',
        ),
        HumanContextRecord(
          id: 'relationship-uncertain',
          kind: 'closePerson',
          references: const ['person-child', 'person-main'],
          status: 'uncertain',
          confirmation: 'needsConfirmation',
          sourceReferenceId: 'person-child',
          targetReferenceId: 'person-main',
          evidenceSource: 'legacyProfile',
        ),
        HumanContextRecord(
          id: 'relationship-rejected',
          kind: 'partner',
          references: const ['person-main', 'person-child'],
          status: 'uncertain',
          confirmation: 'rejected',
          sourceReferenceId: 'person-main',
          targetReferenceId: 'person-child',
          evidenceSource: 'legacyProfile',
        ),
      ],
      households: const [
        HumanContextRecord(
          id: 'household-a',
          kind: 'primary',
          references: [],
          status: 'active',
          confirmation: 'confirmed',
          label: 'Foyer',
          evidenceSource: 'explicitUserInput',
        ),
      ],
      residences: const [
        HumanContextRecord(
          id: 'residence-a',
          kind: 'primary',
          references: ['household-a'],
          status: 'active',
          confirmation: 'confirmed',
          label: 'Chez moi',
          householdIds: ['household-a'],
          evidenceSource: 'explicitUserInput',
        ),
      ],
      memberships: const [
        HumanContextRecord(
          id: 'membership-a',
          kind: 'permanentMember',
          references: ['person-main', 'household-a'],
          status: 'active',
          confirmation: 'confirmed',
          sourceReferenceId: 'person-main',
          targetReferenceId: 'household-a',
          evidenceSource: 'explicitUserInput',
        ),
      ],
      responsibilities: [
        HumanContextRecord(
          id: 'responsibility-a',
          kind: 'transport',
          references: const ['person-main', 'person-child'],
          status: 'active',
          confirmation: 'confirmed',
          sourceReferenceId: 'person-main',
          targetReferenceId: 'person-child',
          validFrom: now.subtract(const Duration(days: 1)),
          validUntil: expiredResponsibility
              ? now.subtract(const Duration(hours: 1))
              : now.add(const Duration(days: 10)),
          evidenceSource: 'explicitUserInput',
          planningConsequenceType: planningConsequenceType,
          planningConsequenceStart: planningConsequenceStart,
          planningConsequenceEnd: planningConsequenceEnd,
          planningConsequenceWeekdays: planningConsequenceWeekdays,
          planningConsequenceStartTime: planningConsequenceStartTime,
          planningConsequenceEndTime: planningConsequenceEndTime,
          blocksResponsiblePerson: blocksResponsiblePerson,
        ),
      ],
    ),
    identityDomain: IdentityDomainSection(
      metadata: _metadata(
        LifeContextDomain.identity,
        LifeContextSourceKind.identityLinks,
        now,
        LifeContextAvailability.available,
      ),
      links: const [
        IdentityContextLink(
          humanPersonId: 'person-child',
          entityId: 'identity-child',
          entityType: 'person',
          confirmed: true,
        ),
      ],
    ),
    eventDomain: EventDomainSection(
      metadata: _metadata(
        LifeContextDomain.event,
        LifeContextSourceKind.eventService,
        now,
        eventAvailability,
      ),
      events: eventAvailability == LifeContextAvailability.available
          ? events
          : const [],
    ),
    taskDomain: TaskDomainSection(
      metadata: _metadata(
        LifeContextDomain.task,
        LifeContextSourceKind.taskService,
        now,
        taskAvailability,
      ),
      tasks: taskAvailability == LifeContextAvailability.available
          ? [
              for (var index = 0; index < taskCount; index++)
                TaskContextItem(
                  id: !allTasksActive && taskCount == 2
                      ? index == 0
                          ? 'task-active'
                          : 'task-done'
                      : 'task-$index',
                  title: !allTasksActive && taskCount == 2
                      ? index == 0
                          ? 'Task active'
                          : 'Task done'
                      : 'Task $index',
                  isCompleted: !allTasksActive && index == 1,
                  dueDate: !allTasksActive && index == 1 ? null : '2026-07-25',
                  durationMinutes: null,
                  syncStatus: 'synced',
                  importance: structuredTaskPriority ? 1 : null,
                  urgency: structuredTaskPriority ? .9 : null,
                  category: structuredTaskPriority ? 'personal' : null,
                  createdAt: structuredTaskPriority
                      ? '2026-07-20T00:00:00.000Z'
                      : null,
                ),
            ]
          : const [],
    ),
    routineDomain: RoutineDomainSection(
      metadata: LifeContextSourceMetadata(
        domain: LifeContextDomain.routine,
        source: LifeContextSourceKind.legacyProfileRoutine,
        readAt: now,
        availability: routineStale
            ? LifeContextAvailability.availableStale
            : LifeContextAvailability.available,
        freshness: routineStale
            ? LifeContextFreshness.stale
            : LifeContextFreshness.current,
        isLocal: true,
        itemCount: routineCount,
        revision: 1,
      ),
      routines: [
        for (var index = 0; index < routineCount; index++)
          RoutineContextItem(
            id: index == 0 ? 'routine-a' : 'routine-$index',
            source: index.isEven
                ? 'legacyProfile.schoolTimeRanges'
                : 'legacyProfile.personalActivities',
            label: 'Routine visible $index',
            days: const ['monday'],
            startTime: '08:00',
            endTime: '09:00',
            travelMinutes: 5,
            humanPersonId: index.isEven ? 'person-child' : 'person-main',
          ),
      ],
    ),
  );
}

LifeContextSourceMetadata _metadata(
  LifeContextDomain domain,
  LifeContextSourceKind source,
  DateTime now,
  LifeContextAvailability availability,
) =>
    LifeContextSourceMetadata(
      domain: domain,
      source: source,
      readAt: now,
      availability: availability,
      freshness: LifeContextFreshness.current,
      isLocal: domain == LifeContextDomain.human ||
          domain == LifeContextDomain.identity ||
          domain == LifeContextDomain.routine,
      itemCount: availability == LifeContextAvailability.available ? 1 : 0,
      revision: 1,
    );

LifeContextProjectionSection _section(
  LifeContextProjection projection,
  LifeContextProjectionSectionType type,
) =>
    projection.sections.singleWhere((section) => section.type == type);

List<List<String>> _selection(LifeContextProjection projection) =>
    projection.sections
        .map((section) => section.items.map((item) => item.id).toList())
        .toList();

LifeContextFact<bool> _legacyFact(bool value, String sourceId) =>
    LifeContextFact(
      value: value,
      provenance: LifeContextProvenance(
        sourceType: LifeContextSourceType.profile,
        evidenceType: LifeContextEvidenceType.explicit,
        sourceId: sourceId,
      ),
    );

LifeContextFact<String> _legacyString(String value, String sourceId) =>
    LifeContextFact(
      value: value,
      provenance: LifeContextProvenance(
        sourceType: LifeContextSourceType.profile,
        evidenceType: LifeContextEvidenceType.explicit,
        sourceId: sourceId,
      ),
    );

Matcher _projectionError(String code) =>
    isA<LifeContextProjectionException>().having(
      (error) => error.code,
      'code',
      code,
    );

final class _FixedIdGenerator implements EntityIdGenerator {
  const _FixedIdGenerator();

  @override
  String generate() => 'projection-fixed';
}
