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
  static final ShoppingRevisionSyncService _sync = ShoppingRevisionSyncService(
    cloud: const FirestoreRevisionedShoppingRepository(),
    currentAccountScope: () => AuthService.currentUserId,
  );

  static void notifyUpdate() {
    shoppingVersion.value++;
  }

  static Future<void> saveItems(
    List<ShoppingItemModel> items,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final scope = _currentAccountScope();

    final encoded = items
        .map(
          (item) => jsonEncode(item.toJson()),
        )
        .toList();

    if (scope == null) {
      await prefs.setStringList(
        shoppingKey,
        encoded,
      );
    }

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

    final data = scope == null ? prefs.getStringList(shoppingKey) : null;

    final localItems = data == null
        ? <ShoppingItemModel>[]
        : data
            .map(
              (item) => ShoppingItemModel.fromJson(
                jsonDecode(item),
              ),
            )
            .toList();

    try {
      final cloudValues = scope == null
          ? const <RevisionedShoppingItem>[]
          : await _sync.bootstrap(scope);
      final cloudItems = cloudValues
          .where((value) => !value.isTombstone)
          .map((value) => value.item)
          .toList();

      if (scope != null) {
        return cloudItems;
      }
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

    return localItems;
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
          return ShoppingPersistenceResult(
            status: existing.syncStatus == RevisionedSyncStatus.synced
                ? ShoppingPersistenceStatus.durable
                : ShoppingPersistenceStatus.synchronizationPending,
            entityId: entityId,
          );
        }
        final mutation = ShoppingMutation(
          mutationId: stableMutationId,
          targetId: entityId,
          expectedRevision: 0,
          createdAt: identified.createdAt.toUtc(),
          attempt: 0,
          nextRetryAt: null,
          state: RevisionedMutationState.queued,
          type: ShoppingMutationType.addItem,
          item: identified,
          clearGeneration: 0,
        );
        final result = await RevisionedActionLedgerObserver.shopping(
          scope,
          mutation,
          () => _sync.apply(scope, mutation),
        );
        return switch (result.status) {
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
    for (final entry in proposedById.entries) {
      final existing = currentById[entry.key];
      final mutation = ShoppingMutation(
        mutationId: mutationIds.generate(),
        targetId: entry.key,
        expectedRevision: existing?.revision ?? 0,
        createdAt: DateTime.now().toUtc(),
        attempt: 0,
        nextRetryAt: null,
        state: RevisionedMutationState.queued,
        type: existing == null
            ? ShoppingMutationType.addItem
            : ShoppingMutationType.updateItem,
        item: entry.value,
        clearGeneration: existing?.clearGeneration ?? 0,
      );
      if (existing == null ||
          !existing.isTombstone &&
              jsonEncode(existing.item.toJson()) !=
                  jsonEncode(entry.value.toJson())) {
        await RevisionedActionLedgerObserver.shopping(
          scope,
          mutation,
          () => _sync.apply(scope, mutation),
        );
      }
    }
    for (final existing in current.where(
      (value) =>
          !value.isTombstone && !proposedById.containsKey(value.entityId),
    )) {
      final mutation = ShoppingMutation(
        mutationId: mutationIds.generate(),
        targetId: existing.entityId,
        expectedRevision: existing.revision,
        createdAt: DateTime.now().toUtc(),
        attempt: 0,
        nextRetryAt: null,
        state: RevisionedMutationState.queued,
        type: ShoppingMutationType.removeItem,
        item: existing.item,
        clearGeneration: existing.clearGeneration,
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
