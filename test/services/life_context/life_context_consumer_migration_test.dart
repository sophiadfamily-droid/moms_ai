import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_id_generator.dart';
import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/models/life_context/life_context_domains.dart';
import 'package:moms_ai/models/life_context/life_context_projection.dart';
import 'package:moms_ai/models/smart_planning_continuation.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/services/life_context/life_context_adapter.dart';
import 'package:moms_ai/services/life_context/life_context_engine.dart';
import 'package:moms_ai/services/life_context/life_context_production.dart';
import 'package:moms_ai/services/memory_planning_compatibility_service.dart';
import 'package:moms_ai/services/memory_reasoning_service.dart';
import 'package:moms_ai/services/smart_planning_continuation_coordinator.dart';

void main() {
  final now = DateTime.utc(2026, 7, 28, 8);

  test('Planning and Memory consume one canonical production generation',
      () async {
    var reads = 0;
    final production = _production(
      now: now,
      onRead: () => reads++,
      events: [
        EventContextItem(
          id: 'event-1',
          title: 'Texte non projeté vers Planning',
          startDateTimeIso: '2026-07-29T09:00:00.000',
          endDateTimeIso: '2026-07-29T10:00:00.000',
          durationMinutes: 60,
          travelGoMinutes: 15,
          travelBackMinutes: 25,
          marginMinutes: 10,
          isRecurring: false,
          recurringType: '',
          revision: 3,
          syncStatus: 'synced',
        ),
      ],
      routines: const [
        RoutineContextItem(
          id: 'routine-1',
          source: 'routine.v1',
          label: 'Texte non projeté vers Planning',
          days: ['mercredi'],
          startTime: '14:00',
          endTime: '15:00',
          travelMinutes: 0,
          recurrenceType: 'weekly',
          travelGoMinutes: 5,
          travelBackMinutes: 10,
          marginMinutes: 5,
        ),
      ],
      memories: [
        MemoryContextItem(
          id: 'memory-active',
          text: 'Tous les mercredis de 16h à 17h',
          semanticType: 'routine',
          category: 'routine',
          importance: 8,
          status: 'active',
          confirmation: 'confirmed',
          provenance: 'explicitUserMessage',
          sensitivity: 'ordinary',
          isExplicitHealth: false,
          createdAt: now.subtract(const Duration(days: 14)),
          semanticIdentityKey: 'v1|routine|schedule',
          revision: 4,
        ),
        const MemoryContextItem(
          id: 'memory-proposed',
          text: 'Tous les mercredis de 18h à 19h',
          semanticType: 'routine',
          category: 'routine',
          importance: 10,
          status: 'proposed',
          confirmation: 'unconfirmed',
          provenance: 'assistantCandidate',
          sensitivity: 'ordinary',
          isExplicitHealth: false,
        ),
      ],
    );
    final gateway = ProductionSmartPlanningContinuationGateway(
      _profile(),
      loadLifeContext: () async => production,
    );

    final planning = await gateway.findOptions(
      startDate: DateTime(2026, 7, 29),
      totalMinutes: 60,
      searchDays: 1,
    );
    final snapshot = production.currentSnapshot!;
    final memory = MemoryReasoningService.contextFromLifeContext(
      section: snapshot.memoryDomain!,
      sourceGeneration: production.projectionGeneration,
      referenceDate: now,
    );

    expect(planning.hasOptions, isTrue);
    expect(planning.options, hasLength(3));
    expect(
      planning.options.map((option) => option.startTime),
      isNot(contains('09:00')),
    );
    expect(memory.memories.map((item) => item.id), ['memory-active']);
    expect(memory.memories.single.semanticIdentityKey, 'v1|routine|schedule');
    expect(memory.sourceGeneration, production.projectionGeneration);
    final conflict = await gateway.conflict(
      EventModel(
        id: 'candidate',
        title: 'Candidat',
        date: '2026-07-29',
        time: '09:30',
        durationMinutes: 15,
        notes: '',
        createdAt: now,
        startDateTimeIso: '2026-07-29T09:30:00.000',
      ),
    );
    expect(conflict?.id, 'event:event:event-1');
    expect(reads, LifeContextDomain.values.length);
  });

  test('Planning softly ranks a confirmed appointment preference', () async {
    final production = _production(
      now: now,
      memories: const [
        MemoryContextItem(
          id: 'appointment-preference',
          text: 'Mes rendez-vous',
          semanticType: 'preference',
          category: 'preference',
          importance: 5,
          status: 'active',
          confirmation: 'confirmed',
          provenance: 'explicitUserMessage',
          sensitivity: 'ordinary',
          isExplicitHealth: false,
          semanticIdentityKey: 'v1|planning|preferred_appointment_period|'
              'authenticated_user|scope|personal_appointments|none',
          semanticValue: 'morning',
        ),
      ],
    );
    final gateway = ProductionSmartPlanningContinuationGateway(
      _profile(),
      loadLifeContext: () async => production,
    );

    final planning = await gateway.findOptions(
      startDate: DateTime(2026, 7, 29),
      totalMinutes: 60,
      searchDays: 1,
    );

    expect(planning.hasOptions, isTrue);
    expect(planning.options, isNotEmpty);
    expect(
      planning.options.every((option) => option.start.hour < 12),
      isTrue,
    );
  });

  test('Planning fails closed when Event is unavailable', () async {
    final production = _production(
      now: now,
      eventAvailability: LifeContextAvailability.unavailable,
    );
    final gateway = ProductionSmartPlanningContinuationGateway(
      _profile(),
      loadLifeContext: () async => production,
    );

    await expectLater(
      gateway.findOptions(
        startDate: DateTime(2026, 7, 29),
        totalMinutes: 60,
        searchDays: 1,
      ),
      throwsA(
        isA<LifeContextProjectionException>().having(
          (error) => error.code,
          'code',
          'required_projection_domain_unavailable',
        ),
      ),
    );
  });

  test('Planning still searches when optional Task context is unavailable',
      () async {
    final production = _production(
      now: now,
      taskAvailability: LifeContextAvailability.unavailable,
    );
    final gateway = ProductionSmartPlanningContinuationGateway(
      _profile(),
      loadLifeContext: () async => production,
    );

    final planning = await gateway.findOptions(
      startDate: DateTime(2026, 8, 17),
      totalMinutes: 90,
      searchDays: 7,
    );

    expect(planning.hasOptions, isTrue);
    expect(planning.options, isNotEmpty);
  });

  test(
      'Slot request reaches proposals after duration, outbound and same return travel',
      () async {
    final production = _production(
      now: now,
      taskAvailability: LifeContextAvailability.unavailable,
      events: [
        for (var index = 0; index < 30; index++)
          EventContextItem(
            id: 'busy-event-$index',
            title: 'Rendez-vous existant',
            startDateTimeIso: now
                .add(Duration(days: index % 10, hours: index))
                .toIso8601String(),
            endDateTimeIso: now
                .add(Duration(days: index % 10, hours: index + 1))
                .toIso8601String(),
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
      routines: [
        for (var index = 0; index < 20; index++)
          RoutineContextItem(
            id: 'busy-routine-$index',
            source: 'routine.v1',
            label: 'Habitude existante',
            days: const ['dimanche'],
            startTime: '07:00',
            endTime: '07:05',
            travelMinutes: 0,
            recurrenceType: 'weekly',
          ),
      ],
    );
    final gateway = ProductionSmartPlanningContinuationGateway(
      _profile(),
      loadLifeContext: () async => production,
    );
    final coordinator = SmartPlanningContinuationCoordinator(
      gateway: gateway,
      clock: () => now,
    );

    final started = await coordinator.tryStartExplicitSlotRequest(
      text: 'Propose-moi un créneau pour le dentiste la semaine prochaine',
      sessionGeneration: 1,
    );
    expect(started, isNotNull);

    await coordinator.resolve('1h', sessionGeneration: 1);
    await coordinator.resolve('10', sessionGeneration: 1);
    final result = await coordinator.resolve('pareil', sessionGeneration: 1);

    expect(result, isNotNull);
    expect(result!.reply, isNot(contains('problème')));
    expect(
      coordinator.active!.step,
      SmartPlanningContinuationStep.optionChoice,
    );
    expect(coordinator.active!.travelGoMinutes, 10);
    expect(coordinator.active!.travelBackMinutes, 10);
    expect(coordinator.active!.options, isNotEmpty);
  });

  test('Planning excludes a dated responsibility of the primary person',
      () async {
    final production = _production(
      now: now,
      human: _humanWithPlanningResponsibility(
        now,
        responsiblePersonId: 'person-main',
        start: DateTime(2026, 8, 3, 8, 30),
        end: DateTime(2026, 8, 3, 8, 31),
      ),
    );
    final gateway = ProductionSmartPlanningContinuationGateway(
      _profile(),
      loadLifeContext: () async => production,
    );

    final planning = await gateway.findOptions(
      startDate: DateTime(2026, 8, 3),
      totalMinutes: 750,
      searchDays: 1,
    );

    expect(planning.hasOptions, isFalse);
  });

  test('Planning excludes a recurring responsibility of the primary person',
      () async {
    final production = _production(
      now: now,
      human: _humanWithPlanningResponsibility(
        now,
        responsiblePersonId: 'person-main',
        recurringWeekdays: const [DateTime.monday],
      ),
    );
    final gateway = ProductionSmartPlanningContinuationGateway(
      _profile(),
      loadLifeContext: () async => production,
    );

    final planning = await gateway.findOptions(
      startDate: DateTime(2026, 8, 3),
      totalMinutes: 750,
      searchDays: 1,
    );

    expect(planning.hasOptions, isFalse);
  });

  test("Planning does not block the primary person for another person's duty",
      () async {
    final production = _production(
      now: now,
      human: _humanWithPlanningResponsibility(
        now,
        responsiblePersonId: 'person-other',
        recurringWeekdays: const [DateTime.monday],
      ),
    );
    final gateway = ProductionSmartPlanningContinuationGateway(
      _profile(),
      loadLifeContext: () async => production,
    );

    final planning = await gateway.findOptions(
      startDate: DateTime(2026, 8, 3),
      totalMinutes: 750,
      searchDays: 1,
    );

    expect(planning.hasOptions, isTrue);
    expect(
      planning.options.map((option) => option.startTime),
      contains('08:00'),
    );
  });

  test('Memory reasoning excludes stale lifecycle and expired records', () {
    final section = MemoryDomainSection(
      metadata: _metadata(
        LifeContextDomain.memory,
        now,
        LifeContextAvailability.available,
        count: 3,
      ),
      policyGeneralMode: 'automatic',
      policyHealthMode: 'disabled',
      policyConfigured: true,
      memories: [
        const MemoryContextItem(
          id: 'confirmed',
          text: "Je préfère les rendez-vous l'après-midi",
          semanticType: 'preference',
          category: 'preference',
          importance: 4,
          status: 'active',
          confirmation: 'confirmed',
          provenance: 'explicitUserMessage',
          sensitivity: 'ordinary',
          isExplicitHealth: false,
        ),
        const MemoryContextItem(
          id: 'superseded',
          text: 'Ancienne préférence',
          semanticType: 'preference',
          category: 'preference',
          importance: 9,
          status: 'superseded',
          confirmation: 'confirmed',
          provenance: 'explicitUserMessage',
          sensitivity: 'ordinary',
          isExplicitHealth: false,
        ),
        MemoryContextItem(
          id: 'expired',
          text: 'Préférence expirée',
          semanticType: 'preference',
          category: 'preference',
          importance: 9,
          status: 'active',
          confirmation: 'confirmed',
          provenance: 'explicitUserMessage',
          sensitivity: 'ordinary',
          isExplicitHealth: false,
          validUntil: now.subtract(const Duration(seconds: 1)),
        ),
      ],
    );

    final context = MemoryReasoningService.contextFromLifeContext(
      section: section,
      sourceGeneration: 7,
      referenceDate: now,
    );
    final reasoning = MemoryReasoningService.buildReasoningFromLifeContext(
      context,
      referenceDate: now,
    );

    expect(context.memories.map((item) => item.id), ['confirmed']);
    expect(
      reasoning,
      contains(
        containsPair('preferredPeriod', 'afternoon'),
      ),
    );
  });

  test('Memory reasoning ignores a preference unrelated to appointments', () {
    final section = MemoryDomainSection(
      metadata: _metadata(
        LifeContextDomain.memory,
        now,
        LifeContextAvailability.available,
        count: 1,
      ),
      policyGeneralMode: 'automatic',
      policyHealthMode: 'disabled',
      policyConfigured: true,
      memories: const [
        MemoryContextItem(
          id: 'shopping-preference',
          text: 'Je préfère faire mes courses le matin',
          semanticType: 'preference',
          category: 'preference',
          importance: 4,
          status: 'active',
          confirmation: 'confirmed',
          provenance: 'explicitUserMessage',
          sensitivity: 'ordinary',
          isExplicitHealth: false,
          semanticIdentityKey:
              'v1|preference|general_preference|authenticated_user|scope|'
              'general|none',
          semanticValue: 'courses le matin',
        ),
      ],
    );

    final context = MemoryReasoningService.contextFromLifeContext(
      section: section,
      sourceGeneration: 8,
      referenceDate: now,
    );
    final reasoning = MemoryReasoningService.buildReasoningFromLifeContext(
      context,
      referenceDate: now,
    );

    expect(
      reasoning.where((item) => item['type'] == 'schedule_preference'),
      isEmpty,
    );
  });

  test('Planning bridge does not revive broad work text as a constraint',
      () async {
    final production = _production(
      now: now,
      memories: const [
        MemoryContextItem(
          id: 'foreign-work-text',
          text: 'Mon colocataire travaille de nuit',
          semanticType: 'fact',
          category: 'fact',
          importance: 4,
          status: 'active',
          confirmation: 'confirmed',
          provenance: 'explicitUserMessage',
          sensitivity: 'ordinary',
          isExplicitHealth: false,
        ),
      ],
    );

    final reasoning =
        await MemoryPlanningCompatibilityService.buildFromLifeContext(
      production: production,
      referenceDate: now,
    );

    expect(
      reasoning.where((item) => item['type'] == 'schedule_constraint'),
      isEmpty,
    );
  });

  test('Memory reasoning exposes an incompatible canonical capability',
      () async {
    final production = _production(
      now: now,
      memoryAvailability: LifeContextAvailability.unavailable,
    );

    await expectLater(
      MemoryReasoningService.loadFromProduction(production: production),
      throwsA(
        isA<MemoryReasoningContextException>()
            .having(
          (error) => error.code,
          'code',
          'memory_reasoning_context_incompatible',
        )
            .having(
          (error) => error.compatibility.blockingDomains,
          'blockingDomains',
          {LifeContextDomain.memory},
        ),
      ),
    );
  });
}

LifeContextProduction _production({
  required DateTime now,
  void Function()? onRead,
  HumanContextSection? human,
  List<EventContextItem> events = const [],
  List<RoutineContextItem> routines = const [],
  List<MemoryContextItem> memories = const [],
  LifeContextAvailability eventAvailability = LifeContextAvailability.available,
  LifeContextAvailability taskAvailability = LifeContextAvailability.available,
  LifeContextAvailability memoryAvailability =
      LifeContextAvailability.available,
}) {
  const scope = 'account-a';
  final engine = LifeContextEngine(
    currentAccountScopeId: () => scope,
    snapshotIdGenerator: const _IdGenerator(),
    adapters: [
      for (final domain in LifeContextDomain.values)
        _SectionAdapter(
          domain: domain,
          now: now,
          onRead: onRead,
          eventAvailability: eventAvailability,
          taskAvailability: taskAvailability,
          memoryAvailability: memoryAvailability,
          events: events,
          routines: routines,
          memories: memories,
          human: human,
        ),
    ],
  );
  return LifeContextProduction(
    loadEngine: () async => engine,
    currentAccountScopeId: () => scope,
    clock: () => now,
  );
}

final class _IdGenerator implements EntityIdGenerator {
  const _IdGenerator();

  @override
  String generate() => 'snapshot-consumer-migration';
}

final class _SectionAdapter implements LifeContextDomainAdapter {
  const _SectionAdapter({
    required this.domain,
    required this.now,
    required this.eventAvailability,
    required this.taskAvailability,
    required this.memoryAvailability,
    required this.events,
    required this.routines,
    required this.memories,
    required this.human,
    this.onRead,
  });

  @override
  final LifeContextDomain domain;
  final DateTime now;
  final void Function()? onRead;
  final LifeContextAvailability eventAvailability;
  final LifeContextAvailability taskAvailability;
  final LifeContextAvailability memoryAvailability;
  final List<EventContextItem> events;
  final List<RoutineContextItem> routines;
  final List<MemoryContextItem> memories;
  final HumanContextSection? human;

  @override
  Future<LifeContextDomainSection> load(
    LifeContextAdapterRequest request,
  ) async {
    onRead?.call();
    final availability = domain == LifeContextDomain.event
        ? eventAvailability
        : switch (domain) {
            LifeContextDomain.event => eventAvailability,
            LifeContextDomain.task => taskAvailability,
            LifeContextDomain.routine => routines.isEmpty
                ? LifeContextAvailability.empty
                : LifeContextAvailability.available,
            LifeContextDomain.memory => memories.isEmpty
                ? (memoryAvailability == LifeContextAvailability.available
                    ? LifeContextAvailability.empty
                    : memoryAvailability)
                : memoryAvailability,
            LifeContextDomain.human => human == null
                ? LifeContextAvailability.empty
                : LifeContextAvailability.available,
            _ => LifeContextAvailability.empty,
          };
    final metadata = _metadata(
      domain,
      request.readAt,
      availability,
      count: switch (domain) {
        LifeContextDomain.event => events.length,
        LifeContextDomain.routine => routines.length,
        LifeContextDomain.memory => memories.length,
        LifeContextDomain.human => human?.metadata.itemCount ?? 0,
        _ => 0,
      },
    );
    return switch (domain) {
      LifeContextDomain.human =>
        human ?? HumanContextSection(metadata: metadata, primaryPersonId: null),
      LifeContextDomain.identity => IdentityDomainSection(metadata: metadata),
      LifeContextDomain.event =>
        EventDomainSection(metadata: metadata, events: events),
      LifeContextDomain.task => TaskDomainSection(metadata: metadata),
      LifeContextDomain.routine =>
        RoutineDomainSection(metadata: metadata, routines: routines),
      LifeContextDomain.memory => MemoryDomainSection(
          metadata: metadata,
          policyGeneralMode: 'automatic',
          policyHealthMode: 'disabled',
          policyConfigured: true,
          memories: memories,
        ),
    };
  }
}

HumanContextSection _humanWithPlanningResponsibility(
  DateTime now, {
  required String responsiblePersonId,
  DateTime? start,
  DateTime? end,
  List<int> recurringWeekdays = const [],
}) =>
    HumanContextSection(
      metadata: _metadata(
        LifeContextDomain.human,
        now,
        LifeContextAvailability.available,
        count: 4,
      ),
      primaryPersonId: 'person-main',
      persons: const [
        HumanContextPerson(
          id: 'person-main',
          displayName: 'Personne principale',
          status: 'active',
          confirmation: 'confirmed',
        ),
        HumanContextPerson(
          id: 'person-child',
          displayName: 'Enfant',
          status: 'active',
          confirmation: 'confirmed',
        ),
        HumanContextPerson(
          id: 'person-other',
          displayName: 'Autre personne',
          status: 'active',
          confirmation: 'confirmed',
        ),
      ],
      responsibilities: [
        HumanContextRecord(
          id: 'responsibility-1',
          kind: 'transport',
          label: 'Déposer une personne',
          references: [responsiblePersonId, 'person-child'],
          status: 'active',
          confirmation: 'confirmed',
          sourceReferenceId: responsiblePersonId,
          targetReferenceId: 'person-child',
          validFrom: now.subtract(const Duration(days: 1)),
          validUntil: DateTime.utc(2026, 8, 20),
          planningConsequenceType: 'transport',
          planningConsequenceStart: start,
          planningConsequenceEnd: end,
          planningConsequenceWeekdays: recurringWeekdays,
          planningConsequenceStartTime:
              recurringWeekdays.isEmpty ? null : '08:20',
          planningConsequenceEndTime:
              recurringWeekdays.isEmpty ? null : '08:40',
          blocksResponsiblePerson: true,
        ),
      ],
    );

LifeContextSourceMetadata _metadata(
  LifeContextDomain domain,
  DateTime at,
  LifeContextAvailability availability, {
  required int count,
}) =>
    LifeContextSourceMetadata(
      domain: domain,
      source: switch (domain) {
        LifeContextDomain.human => LifeContextSourceKind.humanModelLocal,
        LifeContextDomain.identity => LifeContextSourceKind.identityLinks,
        LifeContextDomain.event => LifeContextSourceKind.eventService,
        LifeContextDomain.task => LifeContextSourceKind.taskService,
        LifeContextDomain.routine => LifeContextSourceKind.legacyProfileRoutine,
        LifeContextDomain.memory => LifeContextSourceKind.memoryFirestore,
      },
      readAt: at,
      availability: availability,
      freshness: availability == LifeContextAvailability.unavailable
          ? LifeContextFreshness.unknown
          : LifeContextFreshness.current,
      isLocal: true,
      itemCount: count,
      revision: 1,
    );

UserProfile _profile() => UserProfile(
      firstName: 'Test',
      familyStatus: '',
      workStatus: '',
      partnerName: '',
      wantsNotifications: false,
      children: const [],
    );
