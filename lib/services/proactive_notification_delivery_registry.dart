import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/proactive_notification_policy.dart';

final class ProactiveNotificationDeliveryState {
  static const currentSchemaVersion = 1;
  static const maximumRecords = 128;

  ProactiveNotificationDeliveryState({
    this.schemaVersion = currentSchemaVersion,
    required this.accountScopeId,
    required List<NotificationDeliveryRecord> records,
    required this.updatedAt,
  }) : records = List.unmodifiable(
          (List<NotificationDeliveryRecord>.of(records)
                ..sort((a, b) => b.decidedAt.compareTo(a.decidedAt)))
              .take(maximumRecords),
        ) {
    if (schemaVersion != currentSchemaVersion ||
        accountScopeId.trim().isEmpty ||
        records.length > maximumRecords ||
        records.any(
          (item) =>
              item.incidentFingerprint.trim().isEmpty ||
              item.incidentFingerprint.length > 200 ||
              item.replacementCount < 0 ||
              item.replacementCount > 10 ||
              item.deferralCount < 0 ||
              item.deferralCount > 3,
        )) {
      throw const FormatException('proactive_delivery_registry_invalid');
    }
  }

  final int schemaVersion;
  final String accountScopeId;
  final List<NotificationDeliveryRecord> records;
  final DateTime updatedAt;

  ProactiveNotificationDeliveryState add(
    NotificationDeliveryRecord record, {
    required DateTime now,
  }) =>
      ProactiveNotificationDeliveryState(
        accountScopeId: accountScopeId,
        records: [record, ...records]
            .where(
              (item) =>
                  now.toUtc().difference(item.decidedAt.toUtc()) <=
                  const Duration(days: 30),
            )
            .take(maximumRecords)
            .toList(),
        updatedAt: now.toUtc(),
      );
}

abstract interface class ProactiveNotificationDeliveryRegistry {
  Future<ProactiveNotificationDeliveryState> load(String accountScopeId);
  Future<void> save(ProactiveNotificationDeliveryState state);
}

final class SharedPreferencesProactiveNotificationDeliveryRegistry
    implements ProactiveNotificationDeliveryRegistry {
  const SharedPreferencesProactiveNotificationDeliveryRegistry(
    this.preferences,
  );

  final SharedPreferences preferences;

  String _key(String scope) => 'proactive_notification_delivery_v1:$scope';
  String _backupKey(String scope) => '${_key(scope)}:previous';

  @override
  Future<ProactiveNotificationDeliveryState> load(
    String accountScopeId,
  ) async {
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
  Future<void> save(ProactiveNotificationDeliveryState state) async {
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
      'records': state.records
          .map(
            (item) => {
              'incidentFingerprint': item.incidentFingerprint,
              'category': item.category.name,
              'decidedAt': item.decidedAt.toUtc().toIso8601String(),
              'decision': item.decision.name,
              'replacementCount': item.replacementCount,
              'deferralCount': item.deferralCount,
              'critical': item.critical,
            },
          )
          .toList(),
    });
    if (!await preferences.setString(key, encoded)) {
      throw const FormatException('proactive_delivery_registry_save_failed');
    }
    _decode(preferences.getString(key)!, state.accountScopeId);
  }

  ProactiveNotificationDeliveryState _decode(String raw, String scope) {
    final decoded = jsonDecode(raw);
    const keys = {
      'schemaVersion',
      'accountScopeId',
      'updatedAt',
      'records',
    };
    if (decoded is! Map ||
        decoded.length != keys.length ||
        !decoded.keys.toSet().containsAll(keys) ||
        decoded['schemaVersion'] !=
            ProactiveNotificationDeliveryState.currentSchemaVersion ||
        decoded['accountScopeId'] != scope ||
        decoded['records'] is! List ||
        (decoded['records'] as List).length >
            ProactiveNotificationDeliveryState.maximumRecords) {
      throw const FormatException('proactive_delivery_registry_corrupted');
    }
    return ProactiveNotificationDeliveryState(
      accountScopeId: scope,
      records: (decoded['records'] as List).map((rawRecord) {
        final record = Map<String, Object?>.from(rawRecord as Map);
        const recordKeys = {
          'incidentFingerprint',
          'category',
          'decidedAt',
          'decision',
          'replacementCount',
          'deferralCount',
          'critical',
        };
        if (record.length != recordKeys.length ||
            !record.keys.toSet().containsAll(recordKeys)) {
          throw const FormatException('proactive_delivery_record_corrupted');
        }
        return NotificationDeliveryRecord(
          incidentFingerprint: record['incidentFingerprint'] as String,
          category: ProactiveAlertCategory.values
              .where((item) => item.name == record['category'])
              .single,
          decidedAt: DateTime.parse(record['decidedAt'] as String).toUtc(),
          decision: NotificationDeliveryDecisionType.values
              .where((item) => item.name == record['decision'])
              .single,
          replacementCount: record['replacementCount'] as int,
          deferralCount: record['deferralCount'] as int,
          critical: record['critical'] as bool,
        );
      }).toList(),
      updatedAt: DateTime.parse(decoded['updatedAt'] as String).toUtc(),
    );
  }

  ProactiveNotificationDeliveryState _empty(String scope) =>
      ProactiveNotificationDeliveryState(
        accountScopeId: scope,
        records: const [],
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
}
