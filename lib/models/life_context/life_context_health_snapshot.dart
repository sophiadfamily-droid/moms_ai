import 'dart:collection';

import 'life_context_domains.dart';

enum LifeContextCapability {
  conversation,
  priority,
  planning,
  memoryReasoning,
}

enum LifeContextCapabilityState { usable, partial, blocked }

final class LifeContextCapabilityCompatibility {
  LifeContextCapabilityCompatibility({
    required this.capability,
    required this.state,
    required Set<LifeContextDomain> requiredDomains,
    required List<String> reasonCodes,
    Set<LifeContextDomain> availableDomains = const {},
    Set<LifeContextDomain> blockingDomains = const {},
    List<String> warningCodes = const [],
    this.sourceGeneration = 0,
  })  : requiredDomains = UnmodifiableSetView(requiredDomains),
        availableDomains = UnmodifiableSetView(availableDomains),
        blockingDomains = UnmodifiableSetView(blockingDomains),
        warningCodes = UnmodifiableListView(warningCodes),
        reasonCodes = UnmodifiableListView(reasonCodes);

  final LifeContextCapability capability;
  final LifeContextCapabilityState state;
  final Set<LifeContextDomain> requiredDomains;
  final Set<LifeContextDomain> availableDomains;
  final Set<LifeContextDomain> blockingDomains;
  final List<String> warningCodes;
  final List<String> reasonCodes;
  final int sourceGeneration;

  bool get isUsable => state != LifeContextCapabilityState.blocked;
}

final class LifeContextHealthSnapshot {
  LifeContextHealthSnapshot({
    required this.schemaVersion,
    required this.generation,
    required this.globalState,
    required this.accountScopeMatch,
    required this.generatedAt,
    required Map<LifeContextDomain, LifeContextAvailability> availability,
    required Map<LifeContextDomain, LifeContextFreshness> freshness,
    required Map<LifeContextDomain, int> entityCounts,
    required Set<LifeContextDomain> invalidatedDomains,
    required List<String> warningCodes,
  })  : availability = UnmodifiableMapView(availability),
        freshness = UnmodifiableMapView(freshness),
        entityCounts = UnmodifiableMapView(entityCounts),
        invalidatedDomains = UnmodifiableSetView(invalidatedDomains),
        warningCodes = UnmodifiableListView(warningCodes);

  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final int generation;
  final LifeContextGlobalState globalState;
  final bool accountScopeMatch;
  final DateTime generatedAt;
  final Map<LifeContextDomain, LifeContextAvailability> availability;
  final Map<LifeContextDomain, LifeContextFreshness> freshness;
  final Map<LifeContextDomain, int> entityCounts;
  final Set<LifeContextDomain> invalidatedDomains;
  final List<String> warningCodes;
}
