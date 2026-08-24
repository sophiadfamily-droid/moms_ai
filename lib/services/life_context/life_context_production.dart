import 'dart:async';

import '../../models/life_context/life_context_domains.dart';
import '../../models/life_context/life_context_graph.dart';
import '../../models/life_context/life_context_health_snapshot.dart';
import '../../models/life_context/life_context_projection.dart';
import '../../models/life_context/life_context_snapshot.dart';
import '../app_diagnostics.dart';
import 'life_context_engine.dart';
import 'life_context_projection_engine.dart';
import 'life_context_relation_engine.dart';

typedef LifeContextEngineLoader = Future<LifeContextEngine> Function();
typedef LifeContextClock = DateTime Function();

abstract final class LifeContextFreshnessPolicy {
  static const Map<LifeContextDomain, Duration> maximumAges = {
    LifeContextDomain.human: Duration(minutes: 15),
    LifeContextDomain.identity: Duration(minutes: 15),
    LifeContextDomain.event: Duration(minutes: 2),
    LifeContextDomain.task: Duration(minutes: 2),
    LifeContextDomain.routine: Duration(minutes: 5),
    LifeContextDomain.memory: Duration(minutes: 5),
    LifeContextDomain.settings: Duration(minutes: 5),
    LifeContextDomain.shopping: Duration(minutes: 2),
  };

  static bool requiresRefresh(
    LifeContextSourceMetadata metadata,
    DateTime now,
  ) {
    return now.toUtc().difference(metadata.readAt.toUtc()) >
        maximumAges[metadata.domain]!;
  }
}

/// Account-scoped production owner of the canonical LC.1 → LC.2 → LC.3 chain.
///
/// Domain repositories remain authoritative. This service only caches an
/// immutable reconstructible snapshot and serializes bounded refreshes.
final class LifeContextProduction {
  LifeContextProduction({
    required LifeContextEngineLoader loadEngine,
    required String? Function() currentAccountScopeId,
    LifeContextClock clock = DateTime.now,
    LifeContextRelationEngine relationEngine =
        const LifeContextRelationEngine(),
    LifeContextProjectionEngine? projectionEngine,
  })  : _loadEngine = loadEngine,
        _currentAccountScopeId = currentAccountScopeId,
        _clock = clock,
        _relationEngine = relationEngine,
        _projectionEngine = projectionEngine ?? LifeContextProjectionEngine();

  final LifeContextEngineLoader _loadEngine;
  final String? Function() _currentAccountScopeId;
  final LifeContextClock _clock;
  final LifeContextRelationEngine _relationEngine;
  final LifeContextProjectionEngine _projectionEngine;
  final StreamController<int> _generationController =
      StreamController<int>.broadcast();
  final Set<LifeContextDomain> _invalidatedDomains =
      LifeContextDomain.values.toSet();

  LifeContextSnapshot? _snapshot;
  LifeContextGraph? _graph;
  String? _accountScopeId;
  int _accountGeneration = 0;
  int _projectionGeneration = 0;
  Future<LifeContextSnapshot>? _refreshInFlight;

  LifeContextSnapshot? get currentSnapshot => _snapshot;
  LifeContextGraph? get currentGraph => _graph;
  int get projectionGeneration => _projectionGeneration;
  Stream<int> observeProjectionGeneration() => _generationController.stream;

  Future<LifeContextProjection> getCurrentProjection(
    LifeContextConsumerPurpose purpose,
  ) async {
    final snapshot = await refreshIfNeeded();
    return _projectionEngine.build(
      snapshot: snapshot,
      graph: _graph,
      contract: LifeContextConsumerContract.forPurpose(purpose),
    );
  }

  Future<LifeContextSnapshot> refreshIfNeeded({bool force = false}) async {
    final scope = _currentAccountScopeId()?.trim();
    if (scope == null || scope.isEmpty) {
      _resetForScope(null);
      throw const LifeContextEngineException('unauthenticated');
    }
    if (_accountScopeId != scope) _resetForScope(scope);

    final now = _clock().toUtc();
    final current = _snapshot;
    if (current != null) {
      for (final metadata in _metadata(current).values) {
        if ({
          LifeContextAvailability.unavailable,
          LifeContextAvailability.corrupted,
          LifeContextAvailability.accountMismatch,
        }.contains(metadata.availability)) {
          _invalidatedDomains.add(metadata.domain);
        }
        if (LifeContextFreshnessPolicy.requiresRefresh(metadata, now)) {
          _invalidatedDomains.add(metadata.domain);
        }
      }
    }
    if (!force && current != null && _invalidatedDomains.isEmpty) {
      return current;
    }
    final existing = _refreshInFlight;
    if (existing != null) return existing;

    final generation = _accountGeneration;
    final refreshDomains = force || current == null
        ? LifeContextDomain.values.toSet()
        : Set<LifeContextDomain>.of(_invalidatedDomains);
    final operation = _refresh(
      scope: scope,
      generation: generation,
      now: now,
      refreshDomains: refreshDomains,
      previous: current,
    );
    _refreshInFlight = operation;
    try {
      return await operation;
    } finally {
      if (identical(_refreshInFlight, operation)) _refreshInFlight = null;
    }
  }

  Future<LifeContextSnapshot> _refresh({
    required String scope,
    required int generation,
    required DateTime now,
    required Set<LifeContextDomain> refreshDomains,
    required LifeContextSnapshot? previous,
  }) async {
    final stopwatch = Stopwatch()..start();
    final engine = await _loadEngine();
    final next = await engine.buildCanonicalSnapshot(
      accountScopeId: scope,
      generatedAt: now,
      previousSnapshot: previous,
      domainsToRefresh: refreshDomains,
    );
    if (_currentAccountScopeId()?.trim() != scope ||
        _accountScopeId != scope ||
        generation != _accountGeneration) {
      _record(
        step: 'reject_stale_result',
        code: AppErrorCode.staleResult,
        generation: generation,
        durationMs: stopwatch.elapsedMilliseconds,
      );
      throw const LifeContextEngineException('stale_result_rejected');
    }
    _snapshot = next;
    _graph = _relationEngine.build(next);
    _invalidatedDomains.removeAll(refreshDomains);
    _projectionGeneration++;
    _generationController.add(_projectionGeneration);
    _record(
      step: 'refresh',
      code: AppErrorCode.lifecycleEvent,
      generation: _projectionGeneration,
      durationMs: stopwatch.elapsedMilliseconds,
      count: _metadata(next)
          .values
          .fold<int>(0, (sum, item) => sum + item.itemCount),
      technicalStatus: next.globalState!.name,
    );
    return next;
  }

  void invalidateSection(LifeContextDomain domain) {
    _invalidatedDomains.add(domain);
    if (domain == LifeContextDomain.human) {
      _invalidatedDomains
        ..add(LifeContextDomain.identity)
        ..add(LifeContextDomain.routine);
    }
  }

  void invalidateAll() {
    _invalidatedDomains.addAll(LifeContextDomain.values);
  }

  LifeContextSourceMetadata? getSectionState(LifeContextDomain domain) {
    final snapshot = _snapshot;
    return snapshot == null ? null : _metadata(snapshot)[domain];
  }

  LifeContextCapabilityCompatibility compatibility(
    LifeContextCapability capability, {
    Set<LifeContextDomain> additionalRequiredDomains = const {},
  }) {
    final required = <LifeContextDomain>{
      ...switch (capability) {
        LifeContextCapability.conversation => {LifeContextDomain.human},
        LifeContextCapability.priority => {LifeContextDomain.task},
        LifeContextCapability.planning => {
            LifeContextDomain.event,
            LifeContextDomain.routine,
          },
        LifeContextCapability.memoryReasoning => {LifeContextDomain.memory},
      },
      ...additionalRequiredDomains,
    };
    final snapshot = _snapshot;
    if (snapshot == null) {
      return LifeContextCapabilityCompatibility(
        capability: capability,
        state: LifeContextCapabilityState.blocked,
        requiredDomains: required,
        reasonCodes: const ['projection_unavailable'],
        blockingDomains: required,
        sourceGeneration: _projectionGeneration,
      );
    }
    final reasons = <String>[];
    final warnings = <String>[];
    final available = <LifeContextDomain>{};
    final blocking = <LifeContextDomain>{};
    for (final domain in required) {
      final metadata = _metadata(snapshot)[domain]!;
      if ({
        LifeContextAvailability.unavailable,
        LifeContextAvailability.corrupted,
        LifeContextAvailability.unsupported,
        LifeContextAvailability.accountMismatch,
      }.contains(metadata.availability)) {
        reasons.add('${domain.name}_${metadata.availability.name}');
        blocking.add(domain);
      } else if (metadata.availability ==
              LifeContextAvailability.availableStale ||
          metadata.freshness == LifeContextFreshness.stale) {
        reasons.add('${domain.name}_stale');
        blocking.add(domain);
      } else if (metadata.truncationState ==
          LifeContextTruncationState.truncated) {
        reasons.add('${domain.name}_truncated');
        blocking.add(domain);
      } else {
        available.add(domain);
      }
    }
    for (final entry in _metadata(snapshot).entries) {
      if (!required.contains(entry.key) &&
          (entry.value.availability == LifeContextAvailability.availableStale ||
              entry.value.freshness == LifeContextFreshness.stale)) {
        warnings.add('${entry.key.name}_stale');
      }
    }
    return LifeContextCapabilityCompatibility(
      capability: capability,
      state: reasons.isEmpty
          ? (snapshot.globalState == LifeContextGlobalState.complete
              ? LifeContextCapabilityState.usable
              : LifeContextCapabilityState.partial)
          : LifeContextCapabilityState.blocked,
      requiredDomains: required,
      availableDomains: available,
      blockingDomains: blocking,
      warningCodes: warnings,
      reasonCodes: reasons,
      sourceGeneration: _projectionGeneration,
    );
  }

  LifeContextHealthSnapshot getHealthSnapshot() {
    final snapshot = _snapshot;
    final metadata = snapshot == null
        ? <LifeContextDomain, LifeContextSourceMetadata>{}
        : _metadata(snapshot);
    return LifeContextHealthSnapshot(
      schemaVersion: LifeContextHealthSnapshot.currentSchemaVersion,
      generation: _projectionGeneration,
      globalState: snapshot?.globalState ?? LifeContextGlobalState.unavailable,
      accountScopeMatch: snapshot == null ||
          snapshot.accountScopeId == _currentAccountScopeId(),
      generatedAt: snapshot?.generatedAt ?? _clock().toUtc(),
      availability: {
        for (final entry in metadata.entries)
          entry.key: entry.value.availability,
      },
      freshness: {
        for (final entry in metadata.entries) entry.key: entry.value.freshness,
      },
      entityCounts: {
        for (final entry in metadata.entries)
          entry.key: entry.value.entityCount,
      },
      invalidatedDomains: Set<LifeContextDomain>.of(_invalidatedDomains),
      warningCodes: [
        for (final entry in metadata.entries)
          if (entry.value.errorCode case final code?) code,
      ]..sort(),
    );
  }

  void handleAccountScopeChanged(String? scope) {
    final normalized = scope?.trim();
    if (_accountScopeId != normalized) _resetForScope(normalized);
  }

  void dispose() {
    _generationController.close();
  }

  void _resetForScope(String? scope) {
    _accountGeneration++;
    _accountScopeId = scope;
    _snapshot = null;
    _graph = null;
    _refreshInFlight = null;
    _invalidatedDomains
      ..clear()
      ..addAll(LifeContextDomain.values);
    _projectionGeneration++;
    _generationController.add(_projectionGeneration);
  }

  Map<LifeContextDomain, LifeContextSourceMetadata> _metadata(
    LifeContextSnapshot snapshot,
  ) =>
      {
        LifeContextDomain.human: snapshot.human!.metadata,
        LifeContextDomain.identity: snapshot.identityDomain!.metadata,
        LifeContextDomain.event: snapshot.eventDomain!.metadata,
        LifeContextDomain.task: snapshot.taskDomain!.metadata,
        LifeContextDomain.routine: snapshot.routineDomain!.metadata,
        LifeContextDomain.memory: snapshot.memoryDomain!.metadata,
        LifeContextDomain.settings: snapshot.settingsDomain!.metadata,
        LifeContextDomain.shopping: snapshot.shoppingDomain!.metadata,
      };

  void _record({
    required String step,
    required AppErrorCode code,
    required int generation,
    required int durationMs,
    int? count,
    String? technicalStatus,
  }) {
    AppDiagnostics.record(
      component: 'life_context',
      domain: 'life_context',
      operation: 'project',
      step: step,
      code: code,
      technicalStatus: technicalStatus,
      metadata: {
        'durationMs': durationMs,
        'sessionGeneration': generation,
        if (count != null) 'count': count,
      },
    );
  }
}
