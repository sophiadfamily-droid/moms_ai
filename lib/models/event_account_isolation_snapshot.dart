enum EventAuthScopeType {
  authenticated,
  guest,
  signedOut,
}

enum EventLoadSourceType {
  memory,
  local,
  cloud,
  merged,
}

final class EventAccountIsolationSnapshot {
  const EventAccountIsolationSnapshot({
    required this.authScopeType,
    required this.eventServiceScopeType,
    required this.localCacheScopeType,
    required this.activeListenerScopeMatch,
    required this.eventCount,
    required this.loadGeneration,
    required this.activeAccountGeneration,
    required this.staleResultDiscarded,
    required this.sourceType,
    required this.screenInstanceGeneration,
  });

  final EventAuthScopeType authScopeType;
  final EventAuthScopeType eventServiceScopeType;
  final EventAuthScopeType localCacheScopeType;
  final bool activeListenerScopeMatch;
  final int eventCount;
  final int loadGeneration;
  final int activeAccountGeneration;
  final bool staleResultDiscarded;
  final EventLoadSourceType sourceType;
  final int screenInstanceGeneration;

  EventAccountIsolationSnapshot copyWith({
    EventAuthScopeType? authScopeType,
    EventAuthScopeType? eventServiceScopeType,
    EventAuthScopeType? localCacheScopeType,
    bool? activeListenerScopeMatch,
    int? eventCount,
    int? loadGeneration,
    int? activeAccountGeneration,
    bool? staleResultDiscarded,
    EventLoadSourceType? sourceType,
    int? screenInstanceGeneration,
  }) {
    return EventAccountIsolationSnapshot(
      authScopeType: authScopeType ?? this.authScopeType,
      eventServiceScopeType:
          eventServiceScopeType ?? this.eventServiceScopeType,
      localCacheScopeType: localCacheScopeType ?? this.localCacheScopeType,
      activeListenerScopeMatch:
          activeListenerScopeMatch ?? this.activeListenerScopeMatch,
      eventCount: eventCount ?? this.eventCount,
      loadGeneration: loadGeneration ?? this.loadGeneration,
      activeAccountGeneration:
          activeAccountGeneration ?? this.activeAccountGeneration,
      staleResultDiscarded: staleResultDiscarded ?? this.staleResultDiscarded,
      sourceType: sourceType ?? this.sourceType,
      screenInstanceGeneration:
          screenInstanceGeneration ?? this.screenInstanceGeneration,
    );
  }
}
