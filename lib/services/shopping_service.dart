import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/identity/entity_id_generator.dart';
import '../core/identity/entity_identity.dart';
import '../core/identity/entity_matcher.dart';
import '../core/identity/uuid_v7_entity_id_generator.dart';
import '../models/shopping_item_model.dart';
import '../models/revisioned_domain_models.dart';
import '../models/revisioned_sync_protocol.dart';
import 'auth_service.dart';
import 'app_diagnostics.dart';
import 'app_error_classifier.dart';
import 'revisioned_cloud_repositories.dart';
import 'revisioned_domain_sync_service.dart';
import 'revisioned_action_ledger_observer.dart';
import 'shopping/shopping_lifecycle_mutation_adapter.dart';

enum ShoppingPersistenceStatus { durable, synchronizationPending }

final class ShoppingPersistenceResult {
  const ShoppingPersistenceResult({
    required this.status,
    required this.entityId,
  });

  final ShoppingPersistenceStatus status;
  final String entityId;

  bool get isSynchronizationPending =>
      status == ShoppingPersistenceStatus.synchronizationPending;
}

final class ShoppingPersistenceException implements Exception {
  const ShoppingPersistenceException(this.code);

  final String code;
}

class ShoppingService {
  static const String shoppingKey = "shopping_items";

  static final EntityMatcher<ShoppingItemModel> _shoppingItemMatcher =
      EntityMatcher(
    idOf: (item) => item.id,
    legacyEquals: (first, second) {
      return first.title == second.title && first.createdAt == second.createdAt;
    },
  );

  static final ValueNotifier<int> shoppingVersion = ValueNotifier<int>(0);
  static final ValueNotifier<int> shoppingContextVersion =
      ValueNotifier<int>(0);
  static final ShoppingRevisionSyncService _sync = ShoppingRevisionSyncService(
    cloud: const FirestoreRevisionedShoppingRepository(),
    currentAccountScope: () => AuthService.currentUserId,
  );
  static final Set<String> _repairedRemovalScopes = <String>{};
  static final Map<String, List<ShoppingItemModel>> _activeItemsByScope =
      <String, List<ShoppingItemModel>>{};
  static final Map<String, String> _activeItemSignaturesByScope =
      <String, String>{};

  static void notifyUpdate() {
    shoppingVersion.value++;
  }

  static Future<void> saveItems(
    List<ShoppingItemModel> items,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final scope = _currentAccountScope();
    final activeItems = _canonicalLocalActiveItems(items);
    _rememberActiveItems(scope, activeItems);

    final encoded = items
        .map(
          (item) => jsonEncode(item.toJson()),
        )
        .toList();

    await prefs.setStringList(
      scope == null ? shoppingKey : shoppingCacheKeyForAccountScope(scope),
      scope == null
          ? encoded
          : activeItems.map((item) => jsonEncode(item.toJson())).toList(),
    );

    try {
      if (scope != null) await _reconcileRevisioned(scope, items);
    } catch (error) {
      final descriptor = AppErrorClassifier.classify(
        error,
        boundary: AppErrorBoundaryKind.synchronization,
      );
      AppDiagnostics.record(
        component: 'shopping_storage',
        domain: 'shopping',
        operation: 'save',
        step: 'cloud_sync',
        code: descriptor.code,
        severity: descriptor.severity,
        retryStrategy: descriptor.retryStrategy,
        correlationId: descriptor.correlationId,
        sourceExceptionType: AppErrorClassifier.safeExceptionType(error),
      );
    }

    notifyUpdate();
  }

  static Future<List<ShoppingItemModel>> getItems() async {
    final prefs = await SharedPreferences.getInstance();
    final scope = _currentAccountScope();

    final data = prefs.getStringList(
      scope == null ? shoppingKey : shoppingCacheKeyForAccountScope(scope),
    );

    final localItems = data == null
        ? <ShoppingItemModel>[]
        : data
            .map(
              (item) => ShoppingItemModel.fromJson(
                jsonDecode(item),
              ),
            )
            .toList();

    if (scope == null) {
      final activeItems = _canonicalLocalActiveItems(localItems);
      if (activeItems.length != localItems.length) {
        await prefs.setStringList(
          shoppingKey,
          activeItems.map((item) => jsonEncode(item.toJson())).toList(),
        );
      }
      _rememberActiveItems(scope, activeItems);
      return activeItems;
    }

    try {
      if (_repairedRemovalScopes.add(scope)) {
        unawaited(_repairRemoteRemovalsInBackground(scope));
      }
      final cloudValues = await _sync.bootstrap(scope);
      final activeItems = _canonicalCloudActiveItems(cloudValues);
      _rememberActiveItems(scope, activeItems);
      await _writeScopedCache(prefs, scope, activeItems);
      final storedActiveCount =
          cloudValues.where((value) => !value.isTombstone).length;
      if (storedActiveCount != activeItems.length) {
        await _reconcileRevisioned(scope, activeItems);
      }
      return activeItems;
    } catch (error) {
      final descriptor = AppErrorClassifier.classify(
        error,
        boundary: AppErrorBoundaryKind.synchronization,
      );
      AppDiagnostics.record(
        component: 'shopping_storage',
        domain: 'shopping',
        operation: 'load',
        step: 'cloud_load',
        code: descriptor.code,
        severity: descriptor.severity,
        retryStrategy: descriptor.retryStrategy,
        correlationId: descriptor.correlationId,
        sourceExceptionType: AppErrorClassifier.safeExceptionType(error),
      );
    }

    return _cachedActiveItems(scope) ?? localItems;
  }

  /// Returns the list the user is currently seeing without waiting for a
  /// second cloud synchronization. Conversation context has a short deadline;
  /// this cache prevents it from falling back to an older remote snapshot.
  static Future<List<ShoppingItemModel>> getItemsForLifeContext() async {
    final scope = _currentAccountScope();
    final cached = _cachedActiveItems(scope);
    if (cached != null) return cached;
    if (scope != null) {
      final prefs = await SharedPreferences.getInstance();
      final local = _readScopedCache(prefs, scope);
      if (local != null) {
        _rememberActiveItems(scope, local);
        return local;
      }
    }
    return getItems();
  }

  static String _cacheKey(String? scope) => scope ?? '@local';

  static String shoppingCacheKeyForAccountScope(String scope) =>
      '$shoppingKey.current.$scope';

  static List<ShoppingItemModel>? _readScopedCache(
    SharedPreferences prefs,
    String scope,
  ) {
    final encoded = prefs.getStringList(shoppingCacheKeyForAccountScope(scope));
    if (encoded == null) return null;
    try {
      return _canonicalLocalActiveItems(
        encoded
            .map(
              (item) => ShoppingItemModel.fromJson(jsonDecode(item)),
            )
            .toList(),
      );
    } on Object {
      return null;
    }
  }

  static Future<void> _writeScopedCache(
    SharedPreferences prefs,
    String scope,
    List<ShoppingItemModel> items,
  ) {
    return prefs.setStringList(
      shoppingCacheKeyForAccountScope(scope),
      items.map((item) => jsonEncode(item.toJson())).toList(),
    );
  }

  static List<ShoppingItemModel>? _cachedActiveItems(String? scope) {
    final cached = _activeItemsByScope[_cacheKey(scope)];
    return cached == null ? null : List<ShoppingItemModel>.of(cached);
  }

  static void _rememberActiveItems(
    String? scope,
    List<ShoppingItemModel> items,
  ) {
    final key = _cacheKey(scope);
    final activeItems = _canonicalLocalActiveItems(items);
    final signatureParts =
        activeItems.map((item) => jsonEncode(item.toJson())).toList()..sort();
    final signature = jsonEncode(signatureParts);
    _activeItemsByScope[key] = List<ShoppingItemModel>.of(activeItems);
    if (_activeItemSignaturesByScope[key] == signature) return;
    _activeItemSignaturesByScope[key] = signature;
    shoppingContextVersion.value++;
  }

  @visibleForTesting
  static void resetRuntimeCacheForTesting() {
    _activeItemsByScope.clear();
    _activeItemSignaturesByScope.clear();
  }

  /// Removes only the transient state owned by one authenticated account.
  /// Guest data and caches belonging to other accounts remain untouched.
  static void clearAccountRuntimeCache(String accountScopeId) {
    final scope = accountScopeId.trim();
    if (scope.isEmpty || scope == '@local') return;
    final hadItems = _activeItemsByScope.remove(scope) != null;
    final hadSignature = _activeItemSignaturesByScope.remove(scope) != null;
    _repairedRemovalScopes.remove(scope);
    if (hadItems || hadSignature) shoppingContextVersion.value++;
  }

  static Future<void> _repairRemoteRemovalsInBackground(String scope) async {
    try {
      await _sync.retryExhaustedRemovals(scope);
      await _sync.repairRemoteRemovals(scope);
    } on Object catch (error) {
      final descriptor = AppErrorClassifier.classify(
        error,
        boundary: AppErrorBoundaryKind.synchronization,
      );
      AppDiagnostics.record(
        component: 'shopping_storage',
        domain: 'shopping',
        operation: 'repair',
        step: 'remote_removals',
        code: descriptor.code,
        severity: descriptor.severity,
        retryStrategy: descriptor.retryStrategy,
        correlationId: descriptor.correlationId,
        sourceExceptionType: AppErrorClassifier.safeExceptionType(error),
      );
    }
  }

  static List<ShoppingItemModel> _canonicalLocalActiveItems(
    List<ShoppingItemModel> values,
  ) {
    final latestByTitle = <String, ShoppingItemModel>{};
    for (final item in values) {
      final key = _normalizedTitle(item.title);
      if (key.isEmpty) continue;
      final current = latestByTitle[key];
      if (current == null || item.createdAt.isAfter(current.createdAt)) {
        latestByTitle[key] = item;
      }
    }
    return latestByTitle.values.where((item) => !item.isBought).toList();
  }

  static List<ShoppingItemModel> _canonicalCloudActiveItems(
    List<RevisionedShoppingItem> values,
  ) {
    final latestByTitle = <String, RevisionedShoppingItem>{};
    for (final value in values) {
      final key = _normalizedTitle(value.item.title);
      if (key.isEmpty) continue;
      final current = latestByTitle[key];
      if (current == null || _isNewerShoppingRevision(value, current)) {
        latestByTitle[key] = value;
      }
    }
    return latestByTitle.values
        .where((value) => !value.isTombstone && !value.item.isBought)
        .map((value) => value.item)
        .toList();
  }

  static bool _isNewerShoppingRevision(
    RevisionedShoppingItem candidate,
    RevisionedShoppingItem current,
  ) {
    final timestampComparison =
        candidate.updatedAt.compareTo(current.updatedAt);
    if (timestampComparison != 0) return timestampComparison > 0;
    final revisionComparison = candidate.revision.compareTo(current.revision);
    if (revisionComparison != 0) return revisionComparison > 0;
    return candidate.entityId.compareTo(current.entityId) > 0;
  }

  static String _normalizedTitle(String value) {
    const replacements = <String, String>{
      'à': 'a',
      'â': 'a',
      'ä': 'a',
      'á': 'a',
      'ç': 'c',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'î': 'i',
      'ï': 'i',
      'í': 'i',
      'ô': 'o',
      'ö': 'o',
      'ó': 'o',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ú': 'u',
      'ÿ': 'y',
    };
    var normalized = value.trim().toLowerCase();
    replacements.forEach((source, target) {
      normalized = normalized.replaceAll(source, target);
    });
    return normalized
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static Future<ShoppingPersistenceResult> addItem(
    ShoppingItemModel item, {
    EntityIdGenerator idGenerator = const UuidV7EntityIdGenerator(),
    String? mutationId,
  }) async {
    final identified = _withIdForCreation(item, idGenerator);
    final entityId = identified.id!;
    final scope = _currentAccountScope();
    if (scope != null) {
      final requestedMutationId = mutationId?.trim() ?? '';
      final stableMutationId = requestedMutationId.isEmpty
          ? 'shopping:create:$entityId'
          : requestedMutationId;
      try {
        final current = await _sync.bootstrap(scope);
        if (_currentAccountScope() != scope) {
          throw const ShoppingPersistenceException(
            'shopping_account_scope_mismatch',
          );
        }
        final matches = current.where((value) => value.entityId == entityId);
        if (matches.isNotEmpty) {
          final existing = matches.single;
          _rememberActiveItems(scope, _canonicalCloudActiveItems(current));
          notifyUpdate();
          return ShoppingPersistenceResult(
            status: existing.syncStatus == RevisionedSyncStatus.synced
                ? ShoppingPersistenceStatus.durable
                : ShoppingPersistenceStatus.synchronizationPending,
            entityId: entityId,
          );
        }
        final plan = const ShoppingLifecycleMutationAdapter().add(
          identified,
          clearGeneration: 0,
        );
        final mutation = ShoppingMutation(
          mutationId: stableMutationId,
          targetId: entityId,
          expectedRevision: 0,
          createdAt: identified.createdAt.toUtc(),
          attempt: 0,
          nextRetryAt: null,
          state: RevisionedMutationState.queued,
          type: plan.mutationType,
          item: plan.persistencePayload,
          clearGeneration: plan.transition.clearGeneration,
        );
        final result = await RevisionedActionLedgerObserver.shopping(
          scope,
          mutation,
          () => _sync.apply(scope, mutation),
        );
        final persistenceResult = switch (result.status) {
          RevisionedCloudWriteStatus.success ||
          RevisionedCloudWriteStatus.idempotent =>
            ShoppingPersistenceResult(
              status: ShoppingPersistenceStatus.durable,
              entityId: entityId,
            ),
          RevisionedCloudWriteStatus.unavailable =>
            _synchronizationPending(entityId),
          RevisionedCloudWriteStatus.accountMismatch =>
            throw const ShoppingPersistenceException(
              'shopping_account_scope_mismatch',
            ),
          RevisionedCloudWriteStatus.revisionConflict ||
          RevisionedCloudWriteStatus.mutationConflict =>
            throw const ShoppingPersistenceException(
              'shopping_revision_conflict',
            ),
          RevisionedCloudWriteStatus.corrupted =>
            throw const ShoppingPersistenceException(
              'shopping_payload_corrupted',
            ),
          RevisionedCloudWriteStatus.notFound =>
            throw const ShoppingPersistenceException(
              'shopping_mutation_not_found',
            ),
        };
        _rememberActiveItems(scope, [
          ..._canonicalCloudActiveItems(current),
          identified,
        ]);
        notifyUpdate();
        return persistenceResult;
      } on ShoppingPersistenceException catch (error) {
        _recordCreateFailure(error);
        rethrow;
      } on Object catch (error) {
        _recordCreateFailure(error);
        rethrow;
      }
    }

    final items = await getItems();
    final existingIndex = items.indexWhere(
      (current) =>
          EntityIdentity.isValid(identified.id) && current.id == identified.id,
    );
    if (existingIndex >= 0) {
      items[existingIndex] = identified;
    } else {
      items.add(identified);
    }

    await saveItems(items);
    return ShoppingPersistenceResult(
      status: ShoppingPersistenceStatus.durable,
      entityId: entityId,
    );
  }

  static void _recordCreateFailure(Object error) {
    final descriptor = error is ShoppingPersistenceException
        ? AppErrorCatalog.describe(
            switch (error.code) {
              'shopping_account_scope_mismatch' =>
                AppErrorCode.accountScopeMismatch,
              'shopping_revision_conflict' => AppErrorCode.conflict,
              'shopping_payload_corrupted' ||
              'shopping_mutation_not_found' =>
                AppErrorCode.invalidArgument,
              _ => AppErrorCode.storageFailure,
            },
          )
        : AppErrorClassifier.classify(
            error,
            boundary: AppErrorBoundaryKind.localStorage,
          );
    AppDiagnostics.record(
      component: 'shopping_repository',
      domain: 'shopping',
      operation: 'create',
      step: 'local_persist',
      code: descriptor.code,
      severity: descriptor.severity,
      retryStrategy: descriptor.retryStrategy,
      sourceExceptionType: AppErrorClassifier.safeExceptionType(error),
    );
  }

  static ShoppingPersistenceResult _synchronizationPending(String entityId) {
    final descriptor = AppErrorCatalog.describe(AppErrorCode.syncPending);
    AppDiagnostics.record(
      component: 'shopping_repository',
      domain: 'shopping',
      operation: 'create',
      step: 'cloud_sync',
      code: descriptor.code,
      severity: descriptor.severity,
      retryStrategy: descriptor.retryStrategy,
      sourceExceptionType: 'RevisionedCloudWriteStatus',
    );
    return ShoppingPersistenceResult(
      status: ShoppingPersistenceStatus.synchronizationPending,
      entityId: entityId,
    );
  }

  static ShoppingItemModel _withIdForCreation(
    ShoppingItemModel item,
    EntityIdGenerator idGenerator,
  ) {
    if (EntityIdentity.isValid(item.id)) return item;
    final generatedId = idGenerator.generate();
    return item.copyWith(id: generatedId);
  }

  static bool areSameShoppingItem(
    ShoppingItemModel first,
    ShoppingItemModel second,
  ) {
    return _shoppingItemMatcher.matches(first, second);
  }

  static Future<void> updateItems(
    List<ShoppingItemModel> items,
  ) async {
    await saveItems(items);
  }

  static Future<void> _reconcileRevisioned(
    String scope,
    List<ShoppingItemModel> proposed,
  ) async {
    final current = await _sync.bootstrap(scope);
    final currentById = {for (final value in current) value.entityId: value};
    final proposedById = {
      for (final item in proposed)
        if (EntityIdentity.isValid(item.id)) item.id!: item,
    };
    const mutationIds = UuidV7EntityIdGenerator();
    const lifecycle = ShoppingLifecycleMutationAdapter();
    for (final entry in proposedById.entries) {
      final existing = currentById[entry.key];
      final plan = existing == null
          ? lifecycle.add(entry.value, clearGeneration: 0)
          : lifecycle.change(current: existing, proposed: entry.value);
      if (plan == null) continue;
      final mutation = ShoppingMutation(
        mutationId: mutationIds.generate(),
        targetId: entry.key,
        expectedRevision: existing?.revision ?? 0,
        createdAt: DateTime.now().toUtc(),
        attempt: 0,
        nextRetryAt: null,
        state: RevisionedMutationState.queued,
        type: plan.mutationType,
        item: plan.persistencePayload,
        clearGeneration: plan.transition.clearGeneration,
      );
      await RevisionedActionLedgerObserver.shopping(
        scope,
        mutation,
        () => _sync.apply(scope, mutation),
      );
    }
    for (final existing in current.where(
      (value) =>
          !value.isTombstone && !proposedById.containsKey(value.entityId),
    )) {
      final plan = lifecycle.change(current: existing, proposed: null);
      if (plan == null) continue;
      final mutation = ShoppingMutation(
        mutationId: mutationIds.generate(),
        targetId: existing.entityId,
        expectedRevision: existing.revision,
        createdAt: DateTime.now().toUtc(),
        attempt: 0,
        nextRetryAt: null,
        state: RevisionedMutationState.queued,
        type: plan.mutationType,
        item: plan.persistencePayload,
        clearGeneration: plan.transition.clearGeneration,
      );
      await RevisionedActionLedgerObserver.shopping(
        scope,
        mutation,
        () => _sync.apply(scope, mutation),
      );
    }
  }

  static String? _currentAccountScope() {
    try {
      return AuthService.currentUserId;
    } on Object {
      return null;
    }
  }
}
