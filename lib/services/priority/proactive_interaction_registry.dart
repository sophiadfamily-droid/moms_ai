import 'dart:collection';

import 'package:flutter/foundation.dart';

enum ProactiveInteractionSource {
  conversationRequest,
  taskClarification,
  taskConfirmation,
  smartPlanningConsent,
  smartPlanningDuration,
  smartPlanningSlotSelection,
  smartPlanningFinalConfirmation,
  eventConfirmation,
  routineConfirmation,
  memoryConfirmation,
  identityClarification,
  identityConfirmation,
}

final class ProactiveInteractionSnapshot {
  const ProactiveInteractionSnapshot({
    required this.sources,
    required this.lastTransition,
    required this.generation,
  });

  final Set<ProactiveInteractionSource> sources;
  final String lastTransition;
  final int generation;

  bool get isActive => sources.isNotEmpty;
}

final class ProactiveInteractionRegistry extends ChangeNotifier {
  ProactiveInteractionRegistry();

  static final ProactiveInteractionRegistry instance =
      ProactiveInteractionRegistry();

  final Map<String, Map<String, Set<ProactiveInteractionSource>>>
      _sourcesByAccountAndOwner = {};
  final Map<String, String> _lastTransitionByAccount = {};
  final Map<String, int> _generationByAccount = {};

  String get diagnosticInstanceIdentifier =>
      'registry-${identityHashCode(this).toRadixString(16)}';

  bool isActive(String accountScopeId) =>
      activeSources(accountScopeId).isNotEmpty;

  Set<ProactiveInteractionSource> activeSources(String accountScopeId) =>
      UnmodifiableSetView(
        {
          for (final sources
              in _sourcesByAccountAndOwner[accountScopeId]?.values ??
                  const <Set<ProactiveInteractionSource>>[])
            ...sources,
        },
      );

  ProactiveInteractionSnapshot snapshot(String accountScopeId) =>
      ProactiveInteractionSnapshot(
        sources: activeSources(accountScopeId),
        lastTransition: _lastTransitionByAccount[accountScopeId] ?? 'none',
        generation: _generationByAccount[accountScopeId] ?? 0,
      );

  void activate(
    String? accountScopeId, {
    required String ownerId,
    required ProactiveInteractionSource source,
  }) {
    final scope = accountScopeId?.trim();
    final owner = ownerId.trim();
    if (scope == null || scope.isEmpty || owner.isEmpty) return;
    final owners = _sourcesByAccountAndOwner.putIfAbsent(scope, () => {});
    final sources = owners.putIfAbsent(owner, () => {});
    if (!sources.add(source)) return;
    _record(scope, 'activate:${source.name}');
  }

  void deactivate(
    String? accountScopeId, {
    required String ownerId,
    required ProactiveInteractionSource source,
  }) {
    final scope = accountScopeId?.trim();
    final owner = ownerId.trim();
    if (scope == null || scope.isEmpty || owner.isEmpty) return;
    final owners = _sourcesByAccountAndOwner[scope];
    final sources = owners?[owner];
    if (sources == null || !sources.remove(source)) return;
    if (sources.isEmpty) owners!.remove(owner);
    if (owners != null && owners.isEmpty) {
      _sourcesByAccountAndOwner.remove(scope);
    }
    _record(scope, 'deactivate:${source.name}');
  }

  void replaceOwnerSources(
    String? accountScopeId, {
    required String ownerId,
    required Set<ProactiveInteractionSource> sources,
  }) {
    final scope = accountScopeId?.trim();
    final owner = ownerId.trim();
    if (scope == null || scope.isEmpty || owner.isEmpty) return;
    final previous = Set<ProactiveInteractionSource>.of(
      _sourcesByAccountAndOwner[scope]?[owner] ?? const {},
    );
    if (setEquals(previous, sources)) return;
    final owners = _sourcesByAccountAndOwner.putIfAbsent(scope, () => {});
    if (sources.isEmpty) {
      owners.remove(owner);
      if (owners.isEmpty) _sourcesByAccountAndOwner.remove(scope);
    } else {
      owners[owner] = Set.of(sources);
    }
    final removed = previous.difference(sources).map((value) => value.name);
    final added = sources.difference(previous).map((value) => value.name);
    _record(
      scope,
      'replace:-${removed.join("+")}:+${added.join("+")}',
    );
  }

  void deactivateOwner(String? accountScopeId, {required String ownerId}) {
    replaceOwnerSources(accountScopeId, ownerId: ownerId, sources: const {});
  }

  void _record(String scope, String transition) {
    _lastTransitionByAccount[scope] = transition;
    _generationByAccount[scope] = (_generationByAccount[scope] ?? 0) + 1;
    notifyListeners();
  }
}
