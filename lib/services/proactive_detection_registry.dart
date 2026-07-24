import 'dart:collection';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/proactive_detection.dart';

final class ProactiveDetectionRegistryState {
  static const currentSchemaVersion = 1;
  static const maximumEntries = 128;

  ProactiveDetectionRegistryState({
    this.schemaVersion = currentSchemaVersion,
    required this.accountScopeId,
    required List<ProactiveDetectionSignal> signals,
    required this.updatedAt,
  }) : signals = UnmodifiableListView(
          List<ProactiveDetectionSignal>.of(signals)
            ..sort((a, b) {
              final date = b.detectedAt.compareTo(a.detectedAt);
              return date != 0 ? date : a.detectionId.compareTo(b.detectionId);
            }),
        ) {
    if (schemaVersion != currentSchemaVersion ||
        accountScopeId.trim().isEmpty ||
        signals.length > maximumEntries ||
        signals.any((item) => item.accountScopeId != accountScopeId) ||
        signals.map((item) => item.detectionId).toSet().length !=
            signals.length) {
      throw const FormatException('detection_registry_invalid');
    }
  }

  final int schemaVersion;
  final String accountScopeId;
  final List<ProactiveDetectionSignal> signals;
  final DateTime updatedAt;

  ProactiveDetectionRegistryState merge({
    required Iterable<ProactiveDetectionSignal> updates,
    required DateTime now,
  }) {
    final byId = {for (final item in signals) item.detectionId: item};
    for (final item in updates) {
      if (item.accountScopeId != accountScopeId) {
        throw const FormatException('detection_registry_account_mismatch');
      }
      byId.removeWhere(
        (id, existing) =>
            id != item.detectionId &&
            existing.incidentFingerprint == item.incidentFingerprint,
      );
      byId[item.detectionId] = item;
    }
    final retained = byId.values
        .where(
          (item) =>
              item.validUntil.isAfter(now) ||
              (item.resolvedAt != null &&
                  now.difference(item.resolvedAt!) <= const Duration(days: 7)),
        )
        .toList()
      ..sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
    return ProactiveDetectionRegistryState(
      accountScopeId: accountScopeId,
      signals: retained.take(maximumEntries).toList(),
      updatedAt: now.toUtc(),
    );
  }
}

abstract interface class ProactiveDetectionRegistry {
  Future<ProactiveDetectionRegistryState> load(String accountScopeId);
  Future<void> save(ProactiveDetectionRegistryState state);
}

final class SharedPreferencesProactiveDetectionRegistry
    implements ProactiveDetectionRegistry {
  const SharedPreferencesProactiveDetectionRegistry(this.preferences);

  final SharedPreferences preferences;

  String _key(String scope) => 'proactive_detection_registry_v1:$scope';
  String _backupKey(String scope) => '${_key(scope)}:previous';

  @override
  Future<ProactiveDetectionRegistryState> load(String accountScopeId) async {
    final raw = preferences.getString(_key(accountScopeId));
    if (raw == null) return _empty(accountScopeId);
    try {
      return _decode(raw, accountScopeId);
    } on Object {
      final backup = preferences.getString(_backupKey(accountScopeId));
      if (backup == null) return _empty(accountScopeId);
      try {
        return _decode(backup, accountScopeId);
      } on Object {
        return _empty(accountScopeId);
      }
    }
  }

  @override
  Future<void> save(ProactiveDetectionRegistryState state) async {
    final key = _key(state.accountScopeId);
    final previous = preferences.getString(key);
    if (previous != null) {
      _decode(previous, state.accountScopeId);
      await preferences.setString(_backupKey(state.accountScopeId), previous);
    }
    final encoded = jsonEncode({
      'schemaVersion': state.schemaVersion,
      'accountScopeId': state.accountScopeId,
      'updatedAt': state.updatedAt.toUtc().toIso8601String(),
      'signals': state.signals.map((item) => item.toJson()).toList(),
    });
    if (!await preferences.setString(key, encoded)) {
      throw const FormatException('detection_registry_save_failed');
    }
    _decode(preferences.getString(key)!, state.accountScopeId);
  }

  ProactiveDetectionRegistryState _decode(String raw, String expectedScope) {
    final json = jsonDecode(raw);
    const keys = {
      'schemaVersion',
      'accountScopeId',
      'updatedAt',
      'signals',
    };
    if (json is! Map ||
        json.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(json.keys.toSet()).isNotEmpty ||
        json['schemaVersion'] !=
            ProactiveDetectionRegistryState.currentSchemaVersion ||
        json['accountScopeId'] != expectedScope ||
        json['signals'] is! List ||
        (json['signals'] as List).length >
            ProactiveDetectionRegistryState.maximumEntries) {
      throw const FormatException('detection_registry_corrupted');
    }
    return ProactiveDetectionRegistryState(
      accountScopeId: expectedScope,
      signals: (json['signals'] as List)
          .map(
            (item) => ProactiveDetectionSignal.fromJson(
              Map<String, Object?>.from(item as Map),
              accountScopeId: expectedScope,
            ),
          )
          .toList(),
      updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
    );
  }

  ProactiveDetectionRegistryState _empty(String scope) =>
      ProactiveDetectionRegistryState(
        accountScopeId: scope,
        signals: const [],
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
}
