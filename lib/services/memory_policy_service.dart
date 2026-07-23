import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/identity/uuid_v7_entity_id_generator.dart';
import '../models/memory_policy.dart';
import '../models/memory_sync.dart';
import 'memory_sync_cloud_repository.dart';
import 'memory_sync_local_repository.dart';
import 'memory_sync_service.dart';

enum MemoryPolicySaveStatus { synced, pendingSync, conflict }

abstract interface class MemoryPolicyRepository {
  Future<MemoryPolicy?> load(String accountScopeId);
  Future<void> save(MemoryPolicy policy);
}

final class SharedPreferencesMemoryPolicyRepository
    implements MemoryPolicyRepository {
  const SharedPreferencesMemoryPolicyRepository(this.preferences);

  final SharedPreferences preferences;

  String _key(String scope) => 'memory_policy_v1:$scope';

  @override
  Future<MemoryPolicy?> load(String accountScopeId) async {
    final raw = preferences.getString(_key(accountScopeId));
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const MemoryPolicyException('invalid_memory_policy');
      }
      return MemoryPolicy.fromJson(
        Map<String, Object?>.from(decoded),
        expectedAccountScopeId: accountScopeId,
      );
    } on MemoryPolicyException {
      rethrow;
    } on Object {
      throw const MemoryPolicyException('corrupted_memory_policy');
    }
  }

  @override
  Future<void> save(MemoryPolicy policy) async {
    policy.validate();
    final saved = await preferences.setString(
      _key(policy.accountScopeId),
      jsonEncode(policy.toJson()),
    );
    if (!saved) throw const MemoryPolicyException('memory_policy_save_failed');
  }
}

final class MemoryPolicyService {
  const MemoryPolicyService({
    required this.repository,
    required this.currentAccountScopeId,
    this.now = DateTime.now,
    MemorySyncService? syncService,
    UuidV7EntityIdGenerator idGenerator = const UuidV7EntityIdGenerator(),
  })  : _syncService = syncService,
        _idGenerator = idGenerator;

  final MemoryPolicyRepository repository;
  final String? Function() currentAccountScopeId;
  final DateTime Function() now;
  final MemorySyncService? _syncService;
  final UuidV7EntityIdGenerator _idGenerator;

  static Future<MemoryPolicyService> local({
    required String? Function() currentAccountScopeId,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final sync = MemorySyncService(
      local: MemorySyncLocalRepository(preferences),
      cloud: FirestoreMemorySyncRepository(
        firestore: FirebaseFirestore.instance,
        currentUid: currentAccountScopeId,
      ),
      currentScope: currentAccountScopeId,
    );
    return MemoryPolicyService(
      repository: SharedPreferencesMemoryPolicyRepository(preferences),
      currentAccountScopeId: currentAccountScopeId,
      syncService: sync,
    );
  }

  Future<MemoryPolicy> load() async {
    final scope = _scope();
    if (_syncService != null) {
      final bootstrap = await _syncService.bootstrap();
      final syncedPolicy = bootstrap.state.policy?.policy;
      if (syncedPolicy != null) {
        await repository.save(syncedPolicy);
        return syncedPolicy;
      }
    }
    return await repository.load(scope) ??
        MemoryPolicy.restrictiveDefault(
          accountScopeId: scope,
          changedAt: now().toUtc(),
        );
  }

  Future<MemoryPolicySaveStatus> save(MemoryPolicy policy) async {
    final scope = _scope();
    if (policy.accountScopeId != scope) {
      throw const MemoryPolicyException('memory_policy_account_mismatch');
    }
    await repository.save(policy);
    final sync = _syncService;
    if (sync == null) return MemoryPolicySaveStatus.pendingSync;
    await sync.bootstrap();
    await sync.queuePolicy(
      policy: policy,
      mutationId: _idGenerator.generate(),
    );
    final state = await sync.synchronize();
    return switch (state.syncStatus) {
      MemorySyncStatus.synced => MemoryPolicySaveStatus.synced,
      MemorySyncStatus.conflict => MemoryPolicySaveStatus.conflict,
      _ => MemoryPolicySaveStatus.pendingSync,
    };
  }

  String _scope() {
    final scope = currentAccountScopeId()?.trim() ?? '';
    if (scope.isEmpty) {
      throw const MemoryPolicyException('memory_policy_unauthenticated');
    }
    return scope;
  }
}
