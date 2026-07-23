import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/identity/uuid_v7_entity_id_generator.dart';
import '../models/life_context/life_context_provenance.dart';
import '../models/life_context/memory_context.dart';
import '../models/memory_lifecycle_state.dart';
import '../models/memory_policy.dart';
import '../models/memory_sync.dart';
import 'auth_service.dart';
import 'memory_sync_cloud_repository.dart';
import 'memory_sync_local_repository.dart';
import 'memory_sync_service.dart';

enum MemoryLibraryFilter {
  all,
  preference,
  habit,
  goal,
  constraint,
  instruction,
  personalFact,
  health,
  historical,
}

enum MemoryLibraryActionStatus {
  synced,
  pendingSync,
  conflict,
  blockedByPolicy,
  invalid,
  protectedDomain,
  notFound,
}

final class MemoryExplanation {
  const MemoryExplanation({
    required this.origin,
    required this.confirmation,
    required this.lifecycle,
    required this.synchronization,
    required this.conversationUse,
    required this.planningUse,
  });

  final String origin;
  final String confirmation;
  final String lifecycle;
  final String synchronization;
  final String conversationUse;
  final String planningUse;
}

final class MemoryLibrarySnapshot {
  const MemoryLibrarySnapshot({
    required this.memories,
    required this.pendingIds,
    required this.conflictIds,
    required this.conflicts,
    required this.syncStatus,
    required this.policy,
  });

  final List<RevisionedMemory> memories;
  final Set<String> pendingIds;
  final Set<String> conflictIds;
  final List<MemorySyncConflict> conflicts;
  final MemorySyncStatus syncStatus;
  final MemoryPolicy policy;

  Iterable<RevisionedMemory> filtered(MemoryLibraryFilter filter) {
    final visible = memories.where((memory) => !memory.tombstone);
    return switch (filter) {
      MemoryLibraryFilter.all => visible,
      MemoryLibraryFilter.preference =>
        visible.where((memory) => memory.category == 'preference'),
      MemoryLibraryFilter.habit =>
        visible.where((memory) => memory.category == 'habit'),
      MemoryLibraryFilter.goal =>
        visible.where((memory) => memory.category == 'goal'),
      MemoryLibraryFilter.constraint =>
        visible.where((memory) => memory.category == 'constraint'),
      MemoryLibraryFilter.instruction =>
        visible.where((memory) => memory.category == 'instruction'),
      MemoryLibraryFilter.personalFact =>
        visible.where((memory) => memory.category == 'personalFact'),
      MemoryLibraryFilter.health => visible.where((memory) => memory.isHealth),
      MemoryLibraryFilter.historical => visible.where(
          (memory) =>
              memory.lifecycleStatus == MemoryLifecycleState.archived ||
              memory.lifecycleStatus == MemoryLifecycleState.expired ||
              memory.lifecycleStatus == MemoryLifecycleState.rejected ||
              memory.lifecycleStatus == MemoryLifecycleState.obsolete,
        ),
    };
  }
}

final class MemoryLibraryActionResult {
  const MemoryLibraryActionResult(this.status, {this.nextCursor});
  final MemoryLibraryActionStatus status;
  final String? nextCursor;
}

final class MemoryLibraryService {
  MemoryLibraryService({
    required MemorySyncService sync,
    required String? Function() currentScope,
    this.now = DateTime.now,
    UuidV7EntityIdGenerator idGenerator = const UuidV7EntityIdGenerator(),
  })  : _sync = sync,
        _currentScope = currentScope,
        _idGenerator = idGenerator;

  static const deleteAllConfirmation = 'SUPPRIMER MA MÉMOIRE';
  static const deleteAllPageSize = 20;

  final MemorySyncService _sync;
  final String? Function() _currentScope;
  final DateTime Function() now;
  final UuidV7EntityIdGenerator _idGenerator;

  static Future<MemoryLibraryService> production() async {
    final preferences = await SharedPreferences.getInstance();
    return MemoryLibraryService(
      sync: MemorySyncService(
        local: MemorySyncLocalRepository(preferences),
        cloud: FirestoreMemorySyncRepository(
          firestore: FirebaseFirestore.instance,
          currentUid: () => AuthService.currentUserId,
        ),
        currentScope: () => AuthService.currentUserId,
      ),
      currentScope: () => AuthService.currentUserId,
    );
  }

  Future<MemoryLibrarySnapshot> load() async {
    final result = await _sync.bootstrap();
    final state = await _sync.materializeExpirations();
    final policy = state.policy?.policy ??
        MemoryPolicy.restrictiveDefault(
          accountScopeId: _scope(),
          changedAt: now().toUtc(),
        );
    final memories = [...state.memories]..sort((left, right) {
        final proposed = _rank(left).compareTo(_rank(right));
        if (proposed != 0) return proposed;
        final date = right.updatedAt.compareTo(left.updatedAt);
        return date != 0 ? date : left.memoryId.compareTo(right.memoryId);
      });
    return MemoryLibrarySnapshot(
      memories: List.unmodifiable(memories),
      pendingIds: Set.unmodifiable(
        state.mutations
            .where((mutation) =>
                mutation.state != MemoryMutationState.completed &&
                mutation.state != MemoryMutationState.abandoned)
            .map((mutation) => mutation.targetId),
      ),
      conflictIds: Set.unmodifiable(
          state.conflicts.map((conflict) => conflict.targetId)),
      conflicts: List.unmodifiable(state.conflicts),
      syncStatus: result.state.syncStatus == MemorySyncStatus.unavailable
          ? MemorySyncStatus.unavailable
          : state.syncStatus,
      policy: policy,
    );
  }

  MemoryExplanation explain(
    RevisionedMemory memory, {
    required MemorySyncStatus syncStatus,
  }) {
    final origin = switch (memory.provenance) {
      LifeContextSourceType.currentInstruction =>
        'Tu as demandé à Zélia de retenir cette information.',
      LifeContextSourceType.profile =>
        'Cette information provient de ton profil.',
      LifeContextSourceType.memory =>
        'Cette information a été proposée dans une conversation.',
      LifeContextSourceType.derived =>
        'Cette information a été proposée automatiquement.',
      _ => 'L’origine exacte de cette information reste à confirmer.',
    };
    return MemoryExplanation(
      origin: origin,
      confirmation:
          memory.confirmationStatus == MemoryConfirmationStatus.confirmed
              ? 'Cette information a été confirmée.'
              : 'Cette information reste à confirmer.',
      lifecycle: switch (memory.lifecycleStatus) {
        MemoryLifecycleState.archived => 'Ce souvenir est archivé.',
        MemoryLifecycleState.expired => 'Ce souvenir a expiré.',
        MemoryLifecycleState.rejected => 'Cette proposition a été rejetée.',
        _ => 'Ce souvenir est actuellement disponible.',
      },
      synchronization: syncStatus == MemorySyncStatus.synced
          ? 'Ce souvenir est synchronisé.'
          : 'La synchronisation de ce souvenir est en attente.',
      conversationUse: _isActive(memory)
          ? 'Il peut être utilisé dans la conversation selon tes réglages.'
          : 'Il n’est pas utilisé comme information active.',
      planningUse:
          'Les souvenirs libres ne sont jamais utilisés directement dans le planning.',
    );
  }

  Future<MemoryLibraryActionResult> correct({
    required String memoryId,
    required String text,
    DateTime? validFrom,
    DateTime? validUntil,
  }) async {
    final normalized = text.trim().toLowerCase();
    if (text.trim().isEmpty ||
        (validFrom != null &&
            validUntil != null &&
            validUntil.isBefore(validFrom))) {
      return const MemoryLibraryActionResult(
        MemoryLibraryActionStatus.invalid,
      );
    }
    return _change(
      memoryId,
      MemoryMutationType.updateMemory,
      (current, mutationId) => current.copyWith(
        memoryRevision: current.memoryRevision + 1,
        text: text.trim(),
        normalizedText: normalized,
        validFrom: validFrom,
        validUntil: validUntil,
        updatedAt: now().toUtc(),
        lastMutationId: mutationId,
        history: _history(current, MemoryHistoryAction.corrected),
      ),
      protectStructuredDomain: true,
    );
  }

  Future<MemoryLibraryActionResult> confirm(String memoryId) => _change(
        memoryId,
        MemoryMutationType.confirmMemory,
        (current, mutationId) => current.copyWith(
          memoryRevision: current.memoryRevision + 1,
          lifecycleStatus: MemoryLifecycleState.active,
          confirmationStatus: MemoryConfirmationStatus.confirmed,
          updatedAt: now().toUtc(),
          lastMutationId: mutationId,
          history: _history(current, MemoryHistoryAction.confirmed),
        ),
      );

  Future<MemoryLibraryActionResult> reject(String memoryId) => _change(
        memoryId,
        MemoryMutationType.rejectMemory,
        (current, mutationId) => current.copyWith(
          memoryRevision: current.memoryRevision + 1,
          lifecycleStatus: MemoryLifecycleState.rejected,
          confirmationStatus: MemoryConfirmationStatus.rejected,
          updatedAt: now().toUtc(),
          lastMutationId: mutationId,
          history: _history(current, MemoryHistoryAction.rejected),
        ),
      );

  Future<MemoryLibraryActionResult> postpone(String memoryId) async {
    final snapshot = await load();
    return snapshot.memories.any((memory) => memory.memoryId == memoryId)
        ? const MemoryLibraryActionResult(MemoryLibraryActionStatus.synced)
        : const MemoryLibraryActionResult(MemoryLibraryActionStatus.notFound);
  }

  Future<MemoryLibraryActionResult> archive(String memoryId) => _change(
        memoryId,
        MemoryMutationType.archiveMemory,
        (current, mutationId) => current.copyWith(
          memoryRevision: current.memoryRevision + 1,
          lifecycleStatus: MemoryLifecycleState.archived,
          updatedAt: now().toUtc(),
          lastMutationId: mutationId,
          history: _history(current, MemoryHistoryAction.archived),
        ),
      );

  Future<MemoryLibraryActionResult> delete(String memoryId) => _change(
        memoryId,
        MemoryMutationType.deleteMemory,
        (current, mutationId) => current.copyWith(
          memoryRevision: current.memoryRevision + 1,
          lifecycleStatus: MemoryLifecycleState.deleted,
          confirmationStatus: MemoryConfirmationStatus.obsolete,
          text: '[supprimé]',
          normalizedText: '[supprime]',
          tombstone: true,
          updatedAt: now().toUtc(),
          lastMutationId: mutationId,
          history: [
            MemoryHistoryEntry(
              action: MemoryHistoryAction.deleted,
              at: now().toUtc(),
              source: LifeContextSourceType.currentInstruction,
            ),
          ],
        ),
        protectStructuredDomain: true,
      );

  Future<MemoryLibraryActionResult> restore(String memoryId) async {
    final snapshot = await load();
    final memory = snapshot.memories
        .where((item) => item.memoryId == memoryId)
        .firstOrNull;
    if (memory == null) {
      return const MemoryLibraryActionResult(
          MemoryLibraryActionStatus.notFound);
    }
    if (memory.tombstone ||
        memory.lifecycleStatus != MemoryLifecycleState.archived) {
      return const MemoryLibraryActionResult(MemoryLibraryActionStatus.invalid);
    }
    if (!_policyAllows(memory, snapshot.policy)) {
      return const MemoryLibraryActionResult(
        MemoryLibraryActionStatus.blockedByPolicy,
      );
    }
    return _change(
      memoryId,
      MemoryMutationType.restoreMemory,
      (current, mutationId) => current.copyWith(
        memoryRevision: current.memoryRevision + 1,
        lifecycleStatus: MemoryLifecycleState.active,
        updatedAt: now().toUtc(),
        lastMutationId: mutationId,
        history: _history(current, MemoryHistoryAction.restored),
      ),
    );
  }

  Future<MemoryLibraryActionResult> deleteAllPage({
    required String confirmation,
    String? afterMemoryId,
  }) async {
    if (confirmation != deleteAllConfirmation) {
      return const MemoryLibraryActionResult(MemoryLibraryActionStatus.invalid);
    }
    final snapshot = await load();
    final targets = snapshot.memories
        .where((memory) =>
            !memory.tombstone &&
            (afterMemoryId == null ||
                memory.memoryId.compareTo(afterMemoryId) > 0))
        .toList()
      ..sort((left, right) => left.memoryId.compareTo(right.memoryId));
    final page = targets.take(deleteAllPageSize).toList();
    var hasPending = false;
    for (final memory in page) {
      var result = await delete(memory.memoryId);
      if (result.status == MemoryLibraryActionStatus.protectedDomain) {
        result = await archive(memory.memoryId);
      }
      hasPending =
          hasPending || result.status == MemoryLibraryActionStatus.pendingSync;
      if (result.status != MemoryLibraryActionStatus.synced &&
          result.status != MemoryLibraryActionStatus.pendingSync) {
        return result;
      }
    }
    return MemoryLibraryActionResult(
      hasPending
          ? MemoryLibraryActionStatus.pendingSync
          : MemoryLibraryActionStatus.synced,
      nextCursor: page.length < deleteAllPageSize ? null : page.last.memoryId,
    );
  }

  Future<MemoryLibraryActionResult> resolveConflict(
    String conflictId,
    MemoryConflictResolution resolution,
  ) async {
    final state = await _sync.resolveConflict(
      conflictId: conflictId,
      resolution: resolution,
    );
    return _status(state);
  }

  Future<MemoryLibraryActionResult> _change(
    String memoryId,
    MemoryMutationType type,
    RevisionedMemory Function(RevisionedMemory, String) transform, {
    bool protectStructuredDomain = false,
  }) async {
    final snapshot = await load();
    final current = snapshot.memories
        .where((item) => item.memoryId == memoryId)
        .firstOrNull;
    if (current == null || current.tombstone) {
      return const MemoryLibraryActionResult(
          MemoryLibraryActionStatus.notFound);
    }
    if (protectStructuredDomain &&
        (current.structuredDomain != null ||
            current.category.toLowerCase() == 'routine')) {
      return const MemoryLibraryActionResult(
        MemoryLibraryActionStatus.protectedDomain,
      );
    }
    if (type != MemoryMutationType.archiveMemory &&
        type != MemoryMutationType.deleteMemory &&
        type != MemoryMutationType.rejectMemory &&
        !_policyAllows(current, snapshot.policy)) {
      return const MemoryLibraryActionResult(
        MemoryLibraryActionStatus.blockedByPolicy,
      );
    }
    final mutationId = _idGenerator.generate();
    final updated = transform(current, mutationId);
    try {
      await _sync.queueMemoryChange(
        current: current,
        updated: updated,
        type: type,
        mutationId: mutationId,
        patch: {'action': type.name},
      );
      return _status(await _sync.synchronize());
    } on MemorySyncException catch (error) {
      return MemoryLibraryActionResult(
        error.code == 'memory_revision_conflict'
            ? MemoryLibraryActionStatus.conflict
            : MemoryLibraryActionStatus.invalid,
      );
    }
  }

  List<MemoryHistoryEntry> _history(
    RevisionedMemory memory,
    MemoryHistoryAction action,
  ) {
    final history = [
      ...memory.history,
      MemoryHistoryEntry(
        action: action,
        at: now().toUtc(),
        source: LifeContextSourceType.currentInstruction,
      ),
    ];
    return history.length <= RevisionedMemory.maxHistoryEntries
        ? history
        : history.sublist(history.length - RevisionedMemory.maxHistoryEntries);
  }

  bool _policyAllows(RevisionedMemory memory, MemoryPolicy policy) =>
      policy.generalMode != MemoryGeneralMode.paused &&
      (!memory.isHealth ||
          (policy.healthMode == MemoryHealthMode.enabled &&
              policy.healthConsentGranted));

  MemoryLibraryActionResult _status(MemorySyncLocalState state) =>
      MemoryLibraryActionResult(
        switch (state.syncStatus) {
          MemorySyncStatus.synced => MemoryLibraryActionStatus.synced,
          MemorySyncStatus.conflict => MemoryLibraryActionStatus.conflict,
          MemorySyncStatus.blockedByPolicy =>
            MemoryLibraryActionStatus.blockedByPolicy,
          _ => MemoryLibraryActionStatus.pendingSync,
        },
      );

  int _rank(RevisionedMemory memory) =>
      memory.lifecycleStatus == MemoryLifecycleState.proposed
          ? 0
          : _isActive(memory)
              ? 1
              : 2;

  bool _isActive(RevisionedMemory memory) =>
      !memory.tombstone &&
      (memory.lifecycleStatus == MemoryLifecycleState.active ||
          memory.lifecycleStatus == MemoryLifecycleState.confirmed);

  String _scope() {
    final scope = _currentScope()?.trim() ?? '';
    if (scope.isEmpty) {
      throw const MemorySyncException('memory_sync_unauthenticated');
    }
    return scope;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
