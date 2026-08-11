import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_id_generator.dart';
import 'package:moms_ai/core/identity/entity_types.dart';
import 'package:moms_ai/core/identity/persisted_identity_link.dart';
import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/models/human/human_model.dart';
import 'package:moms_ai/models/human/human_model_persistence.dart';
import 'package:moms_ai/models/life_context/life_context_domains.dart';
import 'package:moms_ai/models/life_context/life_context_snapshot.dart';
import 'package:moms_ai/models/memory_policy.dart';
import 'package:moms_ai/models/task_model.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/services/life_context/life_context_adapter.dart';
import 'package:moms_ai/services/life_context/life_context_domain_adapters.dart';
import 'package:moms_ai/services/life_context/life_context_engine.dart';
import 'package:moms_ai/services/life_context/user_profile_life_context_mapper.dart';

void main() {
  final now = DateTime.utc(2026, 7, 23, 12);

  group('canonical Life Context snapshot', () {
    test('composes every domain with deterministic ordering and metadata',
        () async {
      final engine = _engine(now: now);

      final snapshot = await engine.buildCanonicalSnapshot(
        accountScopeId: 'account-a',
        generatedAt: now,
      );

      snapshot.validateCanonical();
      expect(snapshot.schemaVersion, LifeContextSnapshot.currentSchemaVersion);
      expect(snapshot.accountScopeId, 'account-a');
      expect(snapshot.snapshotId, 'snapshot-1');
      expect(snapshot.globalState, LifeContextGlobalState.complete);
      expect(snapshot.human!.persons.map((item) => item.id),
          ['person-a', 'person-b']);
      expect(snapshot.eventDomain!.events.map((item) => item.id),
          ['event-a', 'event-b']);
      expect(snapshot.taskDomain!.tasks.map((item) => item.id),
          ['task-a', 'task-b']);
      expect(snapshot.routineDomain!.routines, hasLength(4));
      for (final metadata in [
        snapshot.human!.metadata,
        snapshot.identityDomain!.metadata,
        snapshot.eventDomain!.metadata,
        snapshot.taskDomain!.metadata,
        snapshot.routineDomain!.metadata,
      ]) {
        expect(metadata.readAt, now);
        expect(
            metadata.availability, isNot(LifeContextAvailability.unavailable));
      }
      expect(
        snapshot.human!.toJson()['schemaVersion'],
        LifeContextDomainSection.currentSchemaVersion,
      );
    });

    test('same sources produce the same ordered domain projection', () async {
      final first = await _engine(now: now).buildCanonicalSnapshot(
        accountScopeId: 'account-a',
        generatedAt: now,
      );
      final second = await _engine(now: now).buildCanonicalSnapshot(
        accountScopeId: 'account-a',
        generatedAt: now,
      );
      final firstJson = first.toJson()
        ..remove('snapshotId')
        ..remove('generatedAt');
      final secondJson = second.toJson()
        ..remove('snapshotId')
        ..remove('generatedAt');
      expect(firstJson, secondJson);
    });

    test('future schema version is rejected explicitly', () {
      final current = const UserProfileLifeContextMapper().map(
        profile: UserProfile(
          firstName: '',
          familyStatus: '',
          workStatus: '',
          partnerName: '',
          wantsNotifications: false,
          children: const [],
        ),
        generatedAt: now,
      );
      expect(
        () => LifeContextSnapshot(
          schemaVersion: LifeContextSnapshot.currentSchemaVersion + 1,
          generatedAt: now,
          identity: current.identity,
          household: current.household,
          places: current.places,
          mobility: current.mobility,
          work: current.work,
          agenda: current.agenda,
          routines: current.routines,
          goals: current.goals,
          preferences: current.preferences,
          constraints: current.constraints,
        ),
        throwsFormatException,
      );
    });

    test('snapshot identifier is technical and independent from account',
        () async {
      final snapshot = await _engine(now: now).buildCanonicalSnapshot(
        accountScopeId: 'account-a',
        generatedAt: now,
      );
      expect(snapshot.snapshotId, isNot(contains('account-a')));
    });

    test('canonical projection excludes legacy and medical payloads', () async {
      final snapshot = await _engine(now: now).buildCanonicalSnapshot(
        accountScopeId: 'account-a',
        generatedAt: now,
      );
      final encoded = jsonEncode(snapshot.toJson());
      expect(encoded, isNot(contains('medicalNotes')));
      expect(encoded, isNot(contains('allergies')));
      expect(encoded, isNot(contains('emergencyContact')));
      expect(encoded, isNot(contains('"legacyProfile":')));
      expect(encoded, isNot(contains('secret medical value')));
    });
  });

  group('domain adapters', () {
    test('Human preserves universal structures, time and confirmation',
        () async {
      final section = await HumanModelLifeContextAdapter(
        load: (_) async => _humanState(),
      ).load(
          LifeContextAdapterRequest(accountScopeId: 'account-a', readAt: now));

      expect(section.persons, hasLength(2));
      expect(section.households, hasLength(2));
      expect(section.residences, hasLength(2));
      expect(section.memberships, hasLength(2));
      expect(section.responsibilities.single.kind, 'temporary');
      expect(section.relationships.single.status, 'historical');
      expect(section.relationships.single.validUntil, isNotNull);
      expect(section.relationships.single.relationshipStatus, 'Mariée');
      expect(section.relationships.single.marriageDate, '2020-08-12');
      expect(section.relationships.single.engagementDate, '2019-03-17');
      expect(section.persons.last.confirmation, 'needsConfirmation');
      expect(section.persons.first.birthDate, '1990-02-01');
      expect(section.persons.first.familyStatus, 'Je vis en couple');
      expect(section.persons.first.workStatus, 'Je suis salariée');
      expect(section.metadata.revision, 3);
    });

    test('Human distinguishes stale local state from unavailable', () async {
      final stale = _humanState(syncStatus: HumanModelSyncStatus.pendingUpload);
      final section = await HumanModelLifeContextAdapter(
        load: (_) async => stale,
      ).load(
          LifeContextAdapterRequest(accountScopeId: 'account-a', readAt: now));
      expect(section.metadata.availability,
          LifeContextAvailability.availableStale);
      expect(section.metadata.freshness, LifeContextFreshness.stale);
    });

    test('Human account mismatch is explicit', () async {
      final section = await HumanModelLifeContextAdapter(
        load: (_) async => _humanState(scope: 'account-b'),
      ).load(
          LifeContextAdapterRequest(accountScopeId: 'account-a', readAt: now));
      expect(section.metadata.availability,
          LifeContextAvailability.accountMismatch);
    });

    test('Human recovered corruption remains explicit instead of empty',
        () async {
      final section = await HumanModelLifeContextAdapter(
        load: (_) async =>
            _humanState(syncStatus: HumanModelSyncStatus.corruptedLocal),
      ).load(
        LifeContextAdapterRequest(accountScopeId: 'account-a', readAt: now),
      );
      expect(section.persons, isNotEmpty);
      expect(
        section.metadata.availability,
        LifeContextAvailability.corrupted,
      );
      expect(section.metadata.errorCode, 'human_local_recovered');
    });

    test('Identity exposes only confirmed links and allows missing links',
        () async {
      final section = await IdentityLifeContextAdapter(
        loadHuman: (_) async => _humanState(),
      ).load(
          LifeContextAdapterRequest(accountScopeId: 'account-a', readAt: now));
      expect(section.links, hasLength(1));
      expect(section.links.single.humanPersonId, 'person-a');
      expect(section.links.single.entityType, 'person');
    });

    test('Event keeps time, travel, recurrence and revision without writes',
        () async {
      var reads = 0;
      final section = await EventLifeContextAdapter(load: (_) async {
        reads++;
        return _events();
      }).load(
          LifeContextAdapterRequest(accountScopeId: 'account-a', readAt: now));
      expect(reads, 1);
      expect(section.events.first.travelGoMinutes, 15);
      expect(section.events.first.travelBackMinutes, 20);
      expect(section.events.first.marginMinutes, 10);
      expect(section.events.first.isRecurring, isTrue);
      expect(section.events.first.revision, 4);
    });

    test('Event corruption is not converted to an empty domain', () async {
      final invalid = _events().first.copyWith(clearId: true);
      final section = await EventLifeContextAdapter(
        load: (_) async => [invalid],
      ).load(
          LifeContextAdapterRequest(accountScopeId: 'account-a', readAt: now));
      expect(section.metadata.availability, LifeContextAvailability.corrupted);
      expect(section.events, isEmpty);
    });

    test('Task source budget is deterministic and reports truncation',
        () async {
      final tasks = List<TaskModel>.generate(
        LifeContextSourceBudgets.tasks + 1,
        (index) => TaskModel(
          id: 'task-${index.toString().padLeft(3, '0')}',
          title: 'Tâche synthétique',
          category: 'Perso',
          isDone: false,
          createdAt: now,
        ),
      );
      final section = await TaskLifeContextAdapter(
        load: (_) async => tasks.reversed.toList(),
      ).load(
        LifeContextAdapterRequest(accountScopeId: 'account-a', readAt: now),
      );

      expect(section.tasks, hasLength(LifeContextSourceBudgets.tasks));
      expect(section.tasks.first.id, 'task-000');
      expect(
        section.metadata.truncationState,
        LifeContextTruncationState.truncated,
      );
      expect(section.metadata.warningCodes, ['task_source_truncated']);
    });

    test('Event sync conflict is represented but never resolved', () async {
      var syncReadCalls = 0;
      final section = await EventLifeContextAdapter(
        load: (_) async => _events(),
        loadSyncStatuses: (_) async {
          syncReadCalls++;
          return const {'event-a': 'conflict'};
        },
      ).load(
        LifeContextAdapterRequest(accountScopeId: 'account-a', readAt: now),
      );
      expect(section.events.first.syncStatus, 'conflict');
      expect(section.metadata.syncStatus, 'conflicts');
      expect(syncReadCalls, 1);
    });

    test('Task preserves completion and optional due date without priority',
        () async {
      final section = await TaskLifeContextAdapter(
        load: (_) async => _tasks(),
        loadSyncMetadata: (_) async => const TaskLifeContextSyncMetadata(
          revision: 7,
          syncStatus: 'pending',
          pendingCount: 1,
          hasConflict: false,
          itemSyncStatuses: {
            'task-a': 'queued',
            'task-b': 'synced',
          },
        ),
      ).load(
          LifeContextAdapterRequest(accountScopeId: 'account-a', readAt: now));
      expect(section.tasks, hasLength(2));
      expect(section.tasks.first.dueDate, '2026-07-30');
      expect(section.tasks.last.dueDate, isNull);
      expect(section.metadata.revision, 7);
      expect(section.metadata.syncStatus, 'pending');
      expect(section.tasks.first.syncStatus, 'queued');
      expect(section.toJson().toString(), isNot(contains('priority')));
      expect(section.toJson().toString(), isNot(contains('important')));
    });

    test('Routine uses only explicit legacy structures, never memory text',
        () async {
      final section = await RoutineLifeContextAdapter(
        loadHuman: (_) async => _humanState(),
      ).load(
          LifeContextAdapterRequest(accountScopeId: 'account-a', readAt: now));
      expect(section.routines, hasLength(4));
      final work =
          section.routines.singleWhere((item) => item.id == 'workSchedule:0');
      expect(work.days, ['Mardi']);
      expect(work.humanPersonId, 'person-a');
      expect(work.travelMinutes, 25);
      final personalActivity = section.routines
          .singleWhere((item) => item.id == 'personalActivity:0:0');
      expect(personalActivity.days, ['Mercredi']);
      expect(personalActivity.humanPersonId, 'person-a');
      final childActivity = section.routines
          .singleWhere((item) => item.id == 'childActivity:0:0:0');
      expect(childActivity.days, ['Samedi']);
      expect(childActivity.humanPersonId, 'person-b');
      expect(
        section.routines
            .singleWhere((item) => item.id == 'schoolSchedule:0:0')
            .days,
        ['Lundi'],
      );
      expect(
        section.routines.map((item) => item.source),
        containsAll({
          'legacyProfile.workTimeRanges',
          'legacyProfile.childActivities',
          'legacyProfile.personalActivities',
          'legacyProfile.schoolTimeRanges',
        }),
      );
      expect(
          section.metadata.source, LifeContextSourceKind.legacyProfileRoutine);
      expect(section.metadata.availability, LifeContextAvailability.available);
      expect(section.metadata.freshness, LifeContextFreshness.current);
      expect(section.toJson().toString(), isNot(contains('memory')));
    });

    test('Routine keeps unsynced legacy state stale and empty distinct',
        () async {
      final stale = await RoutineLifeContextAdapter(
        loadHuman: (_) async =>
            _humanState(syncStatus: HumanModelSyncStatus.pendingUpload),
      ).load(
          LifeContextAdapterRequest(accountScopeId: 'account-a', readAt: now));
      expect(
        stale.metadata.availability,
        LifeContextAvailability.availableStale,
      );
      expect(stale.metadata.freshness, LifeContextFreshness.stale);

      final empty = await RoutineLifeContextAdapter(
        loadHuman: (_) async => null,
        loadCanonical: (_) async => const [],
      ).load(
          LifeContextAdapterRequest(accountScopeId: 'account-a', readAt: now));
      expect(empty.metadata.availability, LifeContextAvailability.empty);
      expect(empty.routines, isEmpty);
    });

    test('Routine keeps profile schedules when canonical loading fails',
        () async {
      final section = await RoutineLifeContextAdapter(
        loadHuman: (_) async => _humanState(),
        loadCanonical: (_) async => throw StateError('offline'),
      ).load(
        LifeContextAdapterRequest(accountScopeId: 'account-a', readAt: now),
      );

      expect(section.routines, hasLength(4));
      expect(
        section.routines.map((item) => item.id),
        contains('personalActivity:0:0'),
      );
      expect(
        section.metadata.availability,
        LifeContextAvailability.availableStale,
      );
      expect(
        section.metadata.warningCodes,
        contains('canonical_routines_unavailable'),
      );
    });

    test('empty is distinct from unavailable', () async {
      final empty = await TaskLifeContextAdapter(
        load: (_) async => [],
      ).load(
          LifeContextAdapterRequest(accountScopeId: 'account-a', readAt: now));
      final unavailable = await TaskLifeContextAdapter(
        load: (_) async => throw StateError('synthetic'),
      ).load(
          LifeContextAdapterRequest(accountScopeId: 'account-a', readAt: now));
      expect(empty.metadata.availability, LifeContextAvailability.empty);
      expect(unavailable.metadata.availability,
          LifeContextAvailability.unavailable);
    });
  });

  group('resilience and accounts', () {
    test('one unavailable domain creates an explicit partial snapshot',
        () async {
      final engine = _engine(
        now: now,
        taskLoader: (_) async => throw StateError('synthetic'),
      );
      final snapshot = await engine.buildCanonicalSnapshot(
        accountScopeId: 'account-a',
        generatedAt: now,
      );
      expect(snapshot.globalState, LifeContextGlobalState.partial);
      expect(snapshot.taskDomain!.metadata.availability,
          LifeContextAvailability.unavailable);
      expect(snapshot.eventDomain!.events, isNotEmpty);
    });

    test('timeout is bounded and represented without raw exception', () async {
      final engine = _engine(
        now: now,
        timeout: const Duration(milliseconds: 5),
        taskLoader: (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return _tasks();
        },
      );
      final snapshot = await engine.buildCanonicalSnapshot(
        accountScopeId: 'account-a',
        generatedAt: now,
      );
      expect(snapshot.taskDomain!.metadata.errorCode, 'context_timeout');
      expect(snapshot.toJson().toString(), isNot(contains('TimeoutException')));
    });

    test('cancellation stops construction', () async {
      final token = LifeContextCancellationToken()..cancel();
      expect(
        () => _engine(now: now).buildCanonicalSnapshot(
          accountScopeId: 'account-a',
          cancellationToken: token,
        ),
        throwsA(
          isA<LifeContextEngineException>()
              .having((error) => error.code, 'code', 'cancelled'),
        ),
      );
    });

    test('wrong account and missing session are globally refused', () async {
      expect(
        () => _engine(now: now).buildCanonicalSnapshot(
          accountScopeId: 'account-b',
        ),
        throwsA(
          isA<LifeContextEngineException>()
              .having((error) => error.code, 'code', 'account_mismatch'),
        ),
      );
      expect(
        () => _engine(now: now, authenticatedScope: null)
            .buildCanonicalSnapshot(accountScopeId: 'account-a'),
        throwsA(
          isA<LifeContextEngineException>()
              .having((error) => error.code, 'code', 'unauthenticated'),
        ),
      );
    });

    test('anonymous and linked Firebase scopes follow the same contract',
        () async {
      for (final scope in ['anonymous-account', 'linked-account']) {
        final snapshot = await _engine(
          now: now,
          authenticatedScope: scope,
          humanLoader: (_) async => _humanState(scope: scope),
        ).buildCanonicalSnapshot(accountScopeId: scope, generatedAt: now);
        expect(snapshot.accountScopeId, scope);
      }
    });

    test('engine rejects duplicate or missing canonical adapters', () async {
      final adapter = TaskLifeContextAdapter(load: (_) async => []);
      final duplicate = LifeContextEngine(
        currentAccountScopeId: () => 'account-a',
        adapters: [adapter, adapter],
      );
      expect(
        () => duplicate.buildCanonicalSnapshot(accountScopeId: 'account-a'),
        throwsA(isA<LifeContextEngineException>()),
      );
    });

    test('changing shared Human revision refuses an incoherent snapshot',
        () async {
      var reads = 0;
      Future<HumanModelLocalState?> changingLoader(String _) async {
        reads++;
        return _humanState(knownRevision: reads);
      }

      expect(
        () => _engine(now: now, humanLoader: changingLoader)
            .buildCanonicalSnapshot(accountScopeId: 'account-a'),
        throwsA(
          isA<LifeContextEngineException>().having(
            (error) => error.code,
            'code',
            'source_changed_during_snapshot',
          ),
        ),
      );
    });
  });
}

LifeContextEngine _engine({
  required DateTime now,
  String? authenticatedScope = 'account-a',
  Duration timeout = const Duration(seconds: 1),
  HumanContextLoader? humanLoader,
  TaskContextLoader? taskLoader,
}) {
  final loadHuman = humanLoader ?? (_) async => _humanState();
  return LifeContextEngine(
    currentAccountScopeId: () => authenticatedScope,
    snapshotIdGenerator: _FixedIdGenerator(),
    adapterTimeout: timeout,
    adapters: [
      HumanModelLifeContextAdapter(load: loadHuman),
      IdentityLifeContextAdapter(loadHuman: loadHuman),
      EventLifeContextAdapter(load: (_) async => _events()),
      TaskLifeContextAdapter(load: taskLoader ?? (_) async => _tasks()),
      RoutineLifeContextAdapter(loadHuman: loadHuman),
      MemoryLifeContextAdapter(
        loadMemories: (_) async => const [],
        loadPolicy: (scope) async => MemoryPolicy.restrictiveDefault(
          accountScopeId: scope,
          changedAt: now,
        ),
      ),
    ],
  );
}

HumanModelLocalState _humanState({
  String scope = 'account-a',
  HumanModelSyncStatus syncStatus = HumanModelSyncStatus.synced,
  int knownRevision = 3,
}) {
  const confirmed = HumanEvidence(
    source: HumanInformationSource.explicitUserInput,
    confirmation: HumanConfirmationStatus.confirmed,
  );
  const pending = HumanEvidence(
    source: HumanInformationSource.legacyProfile,
    confirmation: HumanConfirmationStatus.needsConfirmation,
  );
  final model = HumanModel(
    accountScopeId: scope,
    primaryPersonId: 'person-a',
    persons: [
      HumanPerson(
        id: 'person-b',
        accountScopeId: scope,
        displayName: 'Homonyme',
        evidence: pending,
        customFields: const {
          'relationshipStatus': 'Mariée',
          'marriageDate': '12/08/2020',
          'engagementDate': '17/03/2019',
        },
      ),
      HumanPerson(
        id: 'person-a',
        accountScopeId: scope,
        displayName: 'Homonyme',
        identityLink: PersistedIdentityLink(
          entityId: 'identity-a',
          entityType: EntityType.person,
        ),
        evidence: confirmed,
        customFields: const {
          'birthDate': '01/02/1990',
        },
      ),
    ],
    relationships: [
      HumanRelationship(
        id: 'relation-a',
        accountScopeId: scope,
        sourcePersonId: 'person-a',
        targetPersonId: 'person-b',
        type: HumanRelationshipTypes.formerPartner,
        status: HumanRecordStatus.historical,
        validity: HumanValidityPeriod(
          validUntil: DateTime.utc(2025, 1, 1),
        ),
        evidence: confirmed,
      ),
    ],
    households: [
      HumanHousehold(
        id: 'household-b',
        accountScopeId: scope,
        status: HouseholdStatus.secondary,
        evidence: confirmed,
      ),
      HumanHousehold(
        id: 'household-a',
        accountScopeId: scope,
        evidence: confirmed,
      ),
    ],
    residences: [
      HumanResidence(
        id: 'residence-b',
        accountScopeId: scope,
        label: 'Résidence temporaire',
        householdIds: const ['household-b'],
        status: ResidenceStatus.temporary,
        evidence: confirmed,
      ),
      HumanResidence(
        id: 'residence-a',
        accountScopeId: scope,
        label: 'Lieu principal',
        householdIds: const ['household-a'],
        evidence: confirmed,
      ),
    ],
    memberships: [
      HumanHouseholdMembership(
        id: 'membership-b',
        accountScopeId: scope,
        householdId: 'household-b',
        personId: 'person-b',
        role: HouseholdMembershipRoles.alternatingMember,
        evidence: confirmed,
      ),
      HumanHouseholdMembership(
        id: 'membership-a',
        accountScopeId: scope,
        householdId: 'household-a',
        personId: 'person-b',
        role: HouseholdMembershipRoles.dependent,
        evidence: confirmed,
      ),
    ],
    responsibilities: [
      HumanResponsibility(
        id: 'responsibility-a',
        accountScopeId: scope,
        responsiblePersonId: 'person-a',
        subjectPersonId: 'person-b',
        type: HumanResponsibilityTypes.temporary,
        validity: HumanValidityPeriod(
          validFrom: DateTime.utc(2026, 7, 1),
          validUntil: DateTime.utc(2026, 8, 1),
        ),
        evidence: confirmed,
      ),
    ],
    legacyProfile: UserProfile(
      firstName: 'Synthetic',
      familyStatus: 'Je vis en couple',
      workStatus: 'Je suis salariée',
      partnerName: '',
      wantsNotifications: false,
      allergies: 'secret medical value',
      workDays: const ['Lundi', 'Mardi'],
      workTimeRanges: [
        TimeRangeModel(
          label: 'Travail',
          startTime: '09:00',
          endTime: '17:00',
          notes: '__DAYS__:Mardi__',
        ),
      ],
      workTravelMinutes: '25',
      children: [
        ChildProfile(
          humanPersonId: 'person-b',
          firstName: 'Synthetic child',
          age: '',
          birthDate: '',
          gender: '',
          school: '',
          notes: '',
          schoolTimeRanges: [
            TimeRangeModel(
              label: 'École',
              startTime: '08:30',
              endTime: '16:30',
              travelMinutes: '10',
              notes: '__DAYS__:Lundi__',
            ),
          ],
          activities: [
            ActivityModel(
              title: 'Activité enfant',
              days: const ['Mercredi'],
              travelMinutes: '15',
              timeRanges: [
                TimeRangeModel(
                  startTime: '17:00',
                  endTime: '18:00',
                  notes: '__DAYS__:Samedi__',
                ),
              ],
            ),
          ],
        ),
      ],
      personalActivities: [
        ActivityModel(
          title: 'Activité',
          days: const ['Mardi', 'Lundi'],
          timeRanges: [
            TimeRangeModel(
              startTime: '18:00',
              endTime: '19:00',
              notes: '__DAYS__:Mercredi__',
            ),
          ],
        ),
      ],
    ).toJson(),
  );
  return HumanModelLocalState(
    model: model,
    knownCloudRevision: knownRevision,
    syncStatus: syncStatus,
    lastMutationId: 'mutation-a',
    migrationStatus: HumanModelMigrationStatus.complete,
  );
}

List<EventModel> _events() => [
      EventModel(
        id: 'event-b',
        title: 'Second',
        date: '2026-07-24',
        time: '12:00',
        notes: '',
        createdAt: DateTime.utc(2026, 7, 20),
        startDateTimeIso: '2026-07-24T12:00:00.000Z',
        eventRevision: 2,
      ),
      EventModel(
        id: 'event-a',
        title: 'Premier',
        date: '2026-07-23',
        time: '09:00',
        notes: '',
        createdAt: DateTime.utc(2026, 7, 20),
        startDateTimeIso: '2026-07-23T09:00:00.000Z',
        endDateTimeIso: '2026-07-23T10:00:00.000Z',
        durationMinutes: 60,
        travelGoMinutes: 15,
        travelBackMinutes: 20,
        usesSeparateTravelTimes: true,
        marginMinutes: 10,
        isRecurring: true,
        recurringType: 'weekly',
        eventRevision: 4,
      ),
    ];

List<TaskModel> _tasks() => [
      TaskModel(
        id: 'task-b',
        title: 'Sans échéance',
        category: 'Perso',
        isDone: true,
        createdAt: DateTime.utc(2026, 7, 20),
      ),
      TaskModel(
        id: 'task-a',
        title: 'Avec échéance',
        category: 'Perso',
        isDone: false,
        createdAt: DateTime.utc(2026, 7, 20),
        dueDate: '2026-07-30',
        priority: 'Urgente',
        isImportant: true,
      ),
    ];

final class _FixedIdGenerator implements EntityIdGenerator {
  @override
  String generate() => 'snapshot-1';
}
