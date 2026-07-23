import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/revisioned_domain_models.dart';
import '../models/revisioned_sync_protocol.dart';

final class RevisionedDomainLocalRepository {
  static const maxEntities = 500;
  static const maxEncodedBytes = 1024 * 1024;

  const RevisionedDomainLocalRepository();

  String _key(String scope, RevisionedSyncDomain domain) =>
      'zelia_y1_${domain.name}_state_v1:$scope';

  Future<List<RevisionedTask>> loadTasks(String accountScopeId) async {
    final values = await _load(accountScopeId, RevisionedSyncDomain.task);
    return values
        .map(
          (value) => RevisionedTask.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<void> saveTasks(
    String accountScopeId,
    List<RevisionedTask> values,
  ) =>
      _save(
        accountScopeId,
        RevisionedSyncDomain.task,
        values.map((value) => value.toJson()).toList(),
      );

  Future<List<RevisionedShoppingItem>> loadShopping(
    String accountScopeId,
  ) async {
    final values = await _load(accountScopeId, RevisionedSyncDomain.shopping);
    return values
        .map(
          (value) => RevisionedShoppingItem.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<void> saveShopping(
    String accountScopeId,
    List<RevisionedShoppingItem> values,
  ) =>
      _save(
        accountScopeId,
        RevisionedSyncDomain.shopping,
        values.map((value) => value.toJson()).toList(),
      );

  Future<RevisionedProfileState?> loadProfile(String accountScopeId) async {
    final values = await _load(accountScopeId, RevisionedSyncDomain.profile);
    if (values.isEmpty) return null;
    return RevisionedProfileState.fromJson(
      Map<String, dynamic>.from(values.single as Map),
    );
  }

  Future<void> saveProfile(
    String accountScopeId,
    RevisionedProfileState value,
  ) =>
      _save(
        accountScopeId,
        RevisionedSyncDomain.profile,
        [value.toJson()],
      );

  Future<List<dynamic>> _load(
    String scope,
    RevisionedSyncDomain domain,
  ) async {
    _validateScope(scope);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(scope, domain));
    if (raw == null) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! Map ||
        decoded['schemaVersion'] != 1 ||
        decoded['accountScopeId'] != scope ||
        decoded['domain'] != domain.name ||
        decoded['values'] is! List) {
      throw const FormatException('revisioned_local_state_corrupted');
    }
    final values = decoded['values'] as List<dynamic>;
    if (values.length > maxEntities) {
      throw const FormatException('revisioned_local_state_limit');
    }
    return values;
  }

  Future<void> _save(
    String scope,
    RevisionedSyncDomain domain,
    List<Map<String, Object?>> values,
  ) async {
    _validateScope(scope);
    if (values.length > maxEntities) {
      throw const FormatException('revisioned_local_state_limit');
    }
    final encoded = jsonEncode({
      'schemaVersion': 1,
      'accountScopeId': scope,
      'domain': domain.name,
      'values': values,
    });
    if (utf8.encode(encoded).length > maxEncodedBytes) {
      throw const FormatException('revisioned_local_state_size');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(scope, domain), encoded);
  }

  void _validateScope(String scope) {
    if (scope.trim().isEmpty) {
      throw const FormatException('revisioned_local_scope_required');
    }
  }
}
