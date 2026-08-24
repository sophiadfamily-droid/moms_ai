import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_id_generator.dart';
import 'package:moms_ai/models/life_context/life_context_domains.dart';
import 'package:moms_ai/models/life_context/life_context_health_snapshot.dart';
import 'package:moms_ai/models/life_context/life_context_projection.dart';
import 'package:moms_ai/services/life_context/life_context_adapter.dart';
import 'package:moms_ai/services/life_context/life_context_engine.dart';
import 'package:moms_ai/services/life_context/life_context_production.dart';

void main() {
  const scopeA = 'account-a';
  const scopeB = 'account-b';
  final now = DateTime.utc(2026, 7, 28, 12);

  test('shares one canonical generation across production consumers', () async {
    var scope = scopeA;
    final fixture = _Fixture(scope: () => scope, now: now);
    final production = fixture.production(clock: () => now);

    final conversation = await production.getCurrentProjection(
      LifeContextConsumerPurpose.conversation,
    );
    final priority = await production.getCurrentProjection(
      LifeContextConsumerPurpose.proactivePriority,
    );

    expect(conversation.sourceSnapshotId, priority.sourceSnapshotId);
    expect(fixture.totalReads, LifeContextDomain.values.length);
    expect(production.projectionGeneration, 2);
    expect(production.getHealthSnapshot().globalState,
        LifeContextGlobalState.complete);
  });

  test('targeted invalidation reloads only the affected domain', () async {
    var scope = scopeA;
    final fixture = _Fixture(scope: () => scope, now: now);
    final production = fixture.production(clock: () => now);
    final first = await production.refreshIfNeeded();
    final initialReads = Map<LifeContextDomain, int>.of(fixture.reads);

    production.invalidateSection(LifeContextDomain.task);
    final second = await production.refreshIfNeeded();

    expect(second.snapshotId, isNot(first.snapshotId));
    for (final domain in LifeContextDomain.values) {
      expect(
        fixture.reads[domain],
        initialReads[domain]! + (domain == LifeContextDomain.task ? 1 : 0),
      );
    }
    expect(second.eventDomain, same(first.eventDomain));
    expect(second.taskDomain, isNot(same(first.taskDomain)));
  });

  test('fresh sources are reused and expired sources are reloaded', () async {
    var scope = scopeA;
    var clock = now;
    final fixture = _Fixture(scope: () => scope, now: now);
    final production = fixture.production(clock: () => clock);
    await production.refreshIfNeeded();
    final initial = Map<LifeContextDomain, int>.of(fixture.reads);

    clock = now.add(const Duration(minutes: 1));
    await production.refreshIfNeeded();
    expect(fixture.reads, initial);

    clock = now.add(const Duration(minutes: 16));
    await production.refreshIfNeeded();
    for (final domain in LifeContextDomain.values) {
      expect(fixture.reads[domain], initial[domain]! + 1);
    }
  });

  test('an unavailable domain is retried on the next request', () async {
    var scope = scopeA;
    final availability = <LifeContextDomain, LifeContextAvailability>{
      LifeContextDomain.shopping: LifeContextAvailability.unavailable,
    };
    final fixture = _Fixture(
      scope: () => scope,
      now: now,
      availability: availability,
    );
    final production = fixture.production(clock: () => now);

    final unavailable = await production.refreshIfNeeded();
    expect(
      unavailable.shoppingDomain!.metadata.availability,
      LifeContextAvailability.unavailable,
    );
    final initialReads = Map<LifeContextDomain, int>.of(fixture.reads);
    availability[LifeContextDomain.shopping] = LifeContextAvailability.empty;

    final recovered = await production.refreshIfNeeded();

    expect(
      recovered.shoppingDomain!.metadata.availability,
      LifeContextAvailability.empty,
    );
    for (final domain in LifeContextDomain.values) {
      expect(
        fixture.reads[domain],
        initialReads[domain]! + (domain == LifeContextDomain.shopping ? 1 : 0),
      );
    }
  });

  test('concurrent consumers serialize one source refresh', () async {
    var scope = scopeA;
    final gate = Completer<void>();
    final fixture = _Fixture(
      scope: () => scope,
      now: now,
      gateDomain: LifeContextDomain.task,
      gate: gate,
    );
    final production = fixture.production(clock: () => now);

    final first = production.refreshIfNeeded();
    final second = production.refreshIfNeeded();
    gate.complete();

    expect(await first, same(await second));
    expect(fixture.totalReads, LifeContextDomain.values.length);
  });

  test('late account A result is rejected after switching to B', () async {
    var scope = scopeA;
    final gate = Completer<void>();
    final fixture = _Fixture(
      scope: () => scope,
      now: now,
      gateDomain: LifeContextDomain.event,
      gate: gate,
    );
    final production = fixture.production(clock: () => now);

    final pending = production.refreshIfNeeded();
    await Future<void>.delayed(Duration.zero);
    scope = scopeB;
    production.handleAccountScopeChanged(scopeB);
    gate.complete();

    await expectLater(
      pending,
      throwsA(
        isA<LifeContextEngineException>().having(
          (error) => error.code,
          'code',
          'stale_result_rejected',
        ),
      ),
    );
    expect(production.currentSnapshot, isNull);
    final snapshotB = await production.refreshIfNeeded();
    expect(snapshotB.accountScopeId, scopeB);
  });

  test('capability compatibility blocks only required degraded sections',
      () async {
    var scope = scopeA;
    final fixture = _Fixture(
      scope: () => scope,
      now: now,
      availability: const {
        LifeContextDomain.memory: LifeContextAvailability.availableStale,
      },
    );
    final production = fixture.production(clock: () => now);
    await production.refreshIfNeeded();

    expect(
      production.compatibility(LifeContextCapability.priority).isUsable,
      isTrue,
    );
    final memory =
        production.compatibility(LifeContextCapability.memoryReasoning);
    expect(memory.state, LifeContextCapabilityState.blocked);
    expect(memory.reasonCodes, ['memory_stale']);
    expect(memory.blockingDomains, {LifeContextDomain.memory});
    expect(memory.availableDomains, isEmpty);
    expect(memory.sourceGeneration, production.projectionGeneration);
  });

  test('capability exposes scenario-specific required domains', () async {
    var scope = scopeA;
    final fixture = _Fixture(scope: () => scope, now: now);
    final production = fixture.production(clock: () => now);
    await production.refreshIfNeeded();

    final planning = production.compatibility(
      LifeContextCapability.planning,
      additionalRequiredDomains: const {
        LifeContextDomain.task,
        LifeContextDomain.human,
        LifeContextDomain.identity,
      },
    );

    expect(
      planning.requiredDomains,
      containsAll({
        LifeContextDomain.event,
        LifeContextDomain.routine,
        LifeContextDomain.task,
        LifeContextDomain.human,
        LifeContextDomain.identity,
      }),
    );
    expect(planning.blockingDomains, isEmpty);
  });

  test('human invalidation also refreshes identity and routine', () async {
    var scope = scopeA;
    final fixture = _Fixture(scope: () => scope, now: now);
    final production = fixture.production(clock: () => now);
    await production.refreshIfNeeded();
    final initial = Map<LifeContextDomain, int>.of(fixture.reads);

    production.invalidateSection(LifeContextDomain.human);
    await production.refreshIfNeeded();

    expect(fixture.reads[LifeContextDomain.human],
        initial[LifeContextDomain.human]! + 1);
    expect(fixture.reads[LifeContextDomain.identity],
        initial[LifeContextDomain.identity]! + 1);
    expect(fixture.reads[LifeContextDomain.routine],
        initial[LifeContextDomain.routine]! + 1);
    expect(
        fixture.reads[LifeContextDomain.task], initial[LifeContextDomain.task]);
  });

  test('material source truncation keeps snapshot and projection partial',
      () async {
    var scope = scopeA;
    final fixture = _Fixture(
      scope: () => scope,
      now: now,
      truncatedDomains: const {LifeContextDomain.task},
    );
    final production = fixture.production(clock: () => now);

    final projection = await production.getCurrentProjection(
      LifeContextConsumerPurpose.proactivePriority,
    );

    expect(
      production.currentSnapshot!.globalState,
      LifeContextGlobalState.partial,
    );
    expect(projection.state, LifeContextProjectionState.partial);
    expect(projection.warningCodes, contains('source_truncated'));
    final task = projection.sections.singleWhere(
      (section) => section.type == LifeContextProjectionSectionType.task,
    );
    expect(task.sourceTruncationState, LifeContextTruncationState.truncated);
    expect(task.accountScopeMatch, isTrue);
    expect(task.sourceRevision, 1);
  });
}

final class _Fixture {
  _Fixture({
    required this.scope,
    required this.now,
    this.gateDomain,
    this.gate,
    this.availability = const {},
    this.truncatedDomains = const {},
  }) {
    for (final domain in LifeContextDomain.values) {
      reads[domain] = 0;
    }
  }

  final String Function() scope;
  final DateTime now;
  final LifeContextDomain? gateDomain;
  final Completer<void>? gate;
  final Map<LifeContextDomain, LifeContextAvailability> availability;
  final Set<LifeContextDomain> truncatedDomains;
  final Map<LifeContextDomain, int> reads = {};
  int _id = 0;

  int get totalReads => reads.values.fold(0, (sum, value) => sum + value);

  LifeContextProduction production({required DateTime Function() clock}) {
    final engine = LifeContextEngine(
      currentAccountScopeId: scope,
      snapshotIdGenerator: _IncrementingId(() => ++_id),
      adapters: [
        for (final domain in LifeContextDomain.values)
          _Adapter(
            domain: domain,
            onRead: () async {
              reads[domain] = reads[domain]! + 1;
              if (gateDomain == domain && gate?.isCompleted == false) {
                await gate!.future;
              }
            },
            availability: () =>
                availability[domain] ?? LifeContextAvailability.empty,
            truncated: truncatedDomains.contains(domain),
          ),
      ],
    );
    return LifeContextProduction(
      loadEngine: () async => engine,
      currentAccountScopeId: scope,
      clock: clock,
    );
  }
}

final class _IncrementingId implements EntityIdGenerator {
  const _IncrementingId(this.next);
  final int Function() next;

  @override
  String generate() => 'snapshot-${next()}';
}

final class _Adapter implements LifeContextDomainAdapter {
  const _Adapter({
    required this.domain,
    required this.onRead,
    required this.availability,
    this.truncated = false,
  });

  @override
  final LifeContextDomain domain;
  final Future<void> Function() onRead;
  final LifeContextAvailability Function() availability;
  final bool truncated;

  @override
  Future<LifeContextDomainSection> load(
    LifeContextAdapterRequest request,
  ) async {
    await onRead();
    final currentAvailability = availability();
    final metadata = LifeContextSourceMetadata(
      domain: domain,
      source: switch (domain) {
        LifeContextDomain.human => LifeContextSourceKind.humanModelLocal,
        LifeContextDomain.identity => LifeContextSourceKind.identityLinks,
        LifeContextDomain.event => LifeContextSourceKind.eventService,
        LifeContextDomain.task => LifeContextSourceKind.taskService,
        LifeContextDomain.routine => LifeContextSourceKind.legacyProfileRoutine,
        LifeContextDomain.memory => LifeContextSourceKind.memoryFirestore,
        LifeContextDomain.settings => LifeContextSourceKind.settingsRegistry,
        LifeContextDomain.shopping => LifeContextSourceKind.shoppingService,
      },
      readAt: request.readAt,
      availability: currentAvailability,
      freshness: currentAvailability == LifeContextAvailability.availableStale
          ? LifeContextFreshness.stale
          : LifeContextFreshness.current,
      isLocal: true,
      itemCount: 0,
      revision: 1,
      truncationState: truncated
          ? LifeContextTruncationState.truncated
          : LifeContextTruncationState.complete,
      warningCodes: truncated ? const ['synthetic_source_truncated'] : const [],
    );
    return switch (domain) {
      LifeContextDomain.human =>
        HumanContextSection(metadata: metadata, primaryPersonId: null),
      LifeContextDomain.identity => IdentityDomainSection(metadata: metadata),
      LifeContextDomain.event => EventDomainSection(metadata: metadata),
      LifeContextDomain.task => TaskDomainSection(metadata: metadata),
      LifeContextDomain.routine => RoutineDomainSection(metadata: metadata),
      LifeContextDomain.memory => MemoryDomainSection(
          metadata: metadata,
          policyGeneralMode: 'askEveryTime',
          policyHealthMode: 'disabled',
          policyConfigured: false,
        ),
      LifeContextDomain.settings => SettingsContextSection(
          metadata: metadata,
          automaticTravelCalculationEnabled: false,
          notificationsEnabled: false,
          notificationSoundEnabled: false,
          notificationVibrationEnabled: false,
          notificationBadgeEnabled: false,
          actionAutonomyMode: 'suggestions',
          memoryGeneralMode: 'askEveryTime',
          memoryHealthMode: 'disabled',
        ),
      LifeContextDomain.shopping => ShoppingDomainSection(metadata: metadata),
    };
  }
}
