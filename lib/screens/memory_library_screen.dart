import 'package:flutter/material.dart';

import '../models/memory_lifecycle_state.dart';
import '../models/memory_sync.dart';
import '../services/memory_library_service.dart';

final class MemoryLibraryScreen extends StatefulWidget {
  const MemoryLibraryScreen({
    super.key,
    this.service,
    this.initialSnapshot,
  });

  final MemoryLibraryService? service;
  final MemoryLibrarySnapshot? initialSnapshot;

  @override
  State<MemoryLibraryScreen> createState() => _MemoryLibraryScreenState();
}

final class _MemoryLibraryScreenState extends State<MemoryLibraryScreen> {
  MemoryLibraryService? _service;
  MemoryLibrarySnapshot? _snapshot;
  MemoryLibraryFilter _filter = MemoryLibraryFilter.all;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialSnapshot != null) {
      _snapshot = widget.initialSnapshot;
      _loading = false;
      return;
    }
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = widget.service ?? await MemoryLibraryService.production();
      final snapshot = await service.load();
      if (!mounted) return;
      setState(() {
        _service = service;
        _snapshot = snapshot;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'La mémoire est momentanément indisponible.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ce que Zélia retient'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(message: _error!, retry: _refresh)
                : snapshot == null
                    ? const SizedBox.shrink()
                    : _content(snapshot),
      ),
    );
  }

  Widget _content(MemoryLibrarySnapshot snapshot) {
    final memories = snapshot.filtered(_filter).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (snapshot.syncStatus != MemorySyncStatus.synced)
          _StatusBanner(
            text: snapshot.syncStatus == MemorySyncStatus.conflict
                ? 'Certaines informations ont changé sur un autre appareil.'
                : 'Certains changements seront synchronisés lorsque la connexion reviendra.',
          ),
        Semantics(
          label: 'Filtres de la bibliothèque de mémoire',
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: MemoryLibraryFilter.values
                  .where((filter) =>
                      filter != MemoryLibraryFilter.health ||
                      snapshot.policy.healthConsentGranted)
                  .map(
                    (filter) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(_filterLabel(filter)),
                        selected: _filter == filter,
                        onSelected: (_) => setState(() => _filter = filter),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (memories.isEmpty)
          const _EmptyState()
        else
          ..._sections(memories, snapshot),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () => _confirmDeleteAll(snapshot),
          icon: const Icon(Icons.delete_sweep_outlined),
          label: const Text('Supprimer toute ma mémoire'),
        ),
      ],
    );
  }

  List<Widget> _sections(
    List<RevisionedMemory> memories,
    MemoryLibrarySnapshot snapshot,
  ) {
    final proposed = memories
        .where(
            (memory) => memory.lifecycleStatus == MemoryLifecycleState.proposed)
        .toList();
    final active = memories.where(_active).toList();
    final historical = memories
        .where((memory) => !_active(memory) && !proposed.contains(memory))
        .toList();
    return [
      _section(
          'À confirmer', proposed, snapshot, 'Aucune information à confirmer.'),
      _section('Souvenirs actifs', active, snapshot,
          'Zélia n’a encore rien mémorisé ici.'),
      _section('Expirés ou archivés', historical, snapshot,
          'Aucun souvenir historique.'),
      if (snapshot.conflictIds.isNotEmpty)
        const _StatusBanner(
          text:
              'Cette information a changé sur un autre appareil. Vérifie la version actuelle avant de continuer.',
        ),
    ];
  }

  Widget _section(
    String title,
    List<RevisionedMemory> memories,
    MemoryLibrarySnapshot snapshot,
    String empty,
  ) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (memories.isEmpty)
                Text(empty)
              else
                ...memories.map(
                  (memory) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      memory.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      snapshot.pendingIds.contains(memory.memoryId)
                          ? 'En attente de synchronisation'
                          : _categoryLabel(memory.category),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showDetail(memory, snapshot),
                  ),
                ),
            ],
          ),
        ),
      );

  Future<void> _showDetail(
    RevisionedMemory memory,
    MemoryLibrarySnapshot snapshot,
  ) async {
    final service = _service!;
    final explanation =
        service.explain(memory, syncStatus: snapshot.syncStatus);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(memory.text,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                Text(_categoryLabel(memory.category)),
                Text(explanation.origin),
                Text(explanation.confirmation),
                Text(explanation.lifecycle),
                Text(explanation.synchronization),
                Text(explanation.conversationUse),
                Text(explanation.planningUse),
                if (snapshot.conflictIds.contains(memory.memoryId)) ...[
                  const SizedBox(height: 12),
                  const _StatusBanner(
                    text:
                        'Cette information a changé sur un autre appareil. Vérifie la version actuelle avant de continuer.',
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () {
                          final conflict = snapshot.conflicts.firstWhere(
                              (item) => item.targetId == memory.memoryId);
                          _run(
                            () => service.resolveConflict(
                              conflict.id,
                              MemoryConflictResolution.keepRemote,
                            ),
                            sheetContext,
                          );
                        },
                        child: const Text('Garder la version actuelle'),
                      ),
                      TextButton(
                        onPressed: () {
                          final conflict = snapshot.conflicts.firstWhere(
                              (item) => item.targetId == memory.memoryId);
                          _run(
                            () => service.resolveConflict(
                              conflict.id,
                              MemoryConflictResolution.discardLocalMutation,
                            ),
                            sheetContext,
                          );
                        },
                        child: const Text('Abandonner ma modification'),
                      ),
                    ],
                  ),
                ],
                if (memory.history.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Historique',
                      style: Theme.of(context).textTheme.titleMedium),
                  ...memory.history.reversed.take(10).map(
                        (entry) => Text(_historyLabel(entry.action)),
                      ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (memory.lifecycleStatus ==
                        MemoryLifecycleState.proposed) ...[
                      FilledButton(
                        onPressed: () => _run(
                          () => service.confirm(memory.memoryId),
                          sheetContext,
                        ),
                        child: const Text('Confirmer'),
                      ),
                      OutlinedButton(
                        onPressed: () => _run(
                          () => service.reject(memory.memoryId),
                          sheetContext,
                        ),
                        child: const Text('Rejeter'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text('Décider plus tard'),
                      ),
                    ] else ...[
                      OutlinedButton(
                        onPressed: () => _edit(memory, sheetContext),
                        child: const Text('Corriger'),
                      ),
                      if (memory.lifecycleStatus ==
                          MemoryLifecycleState.archived)
                        OutlinedButton(
                          onPressed: () => _run(
                            () => service.restore(memory.memoryId),
                            sheetContext,
                          ),
                          child: const Text('Restaurer'),
                        )
                      else
                        OutlinedButton(
                          onPressed: () => _run(
                            () => service.archive(memory.memoryId),
                            sheetContext,
                          ),
                          child: const Text('Archiver'),
                        ),
                      TextButton(
                        onPressed: () => _confirmDelete(memory, sheetContext),
                        child: const Text('Supprimer'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _edit(
    RevisionedMemory memory,
    BuildContext sheetContext,
  ) async {
    final controller = TextEditingController(text: memory.text);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Corriger ce souvenir'),
        content: TextField(
          controller: controller,
          maxLength: 4000,
          minLines: 2,
          maxLines: 6,
          decoration: const InputDecoration(labelText: 'Information'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (accepted == true && sheetContext.mounted) {
      await _run(
        () => _service!.correct(
          memoryId: memory.memoryId,
          text: controller.text,
        ),
        sheetContext,
      );
    }
    controller.dispose();
  }

  Future<void> _confirmDelete(
    RevisionedMemory memory,
    BuildContext sheetContext,
  ) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer ce souvenir ?'),
        content: const Text(
          'Il ne sera plus utilisé. Les événements, tâches, routines, profils et personnes ne seront pas supprimés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (accepted == true && sheetContext.mounted) {
      await _run(() => _service!.delete(memory.memoryId), sheetContext);
    }
  }

  Future<void> _confirmDeleteAll(MemoryLibrarySnapshot snapshot) async {
    final controller = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer toute ma mémoire'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Seuls les souvenirs seront supprimés. Ton compte, ton profil, les personnes, événements, tâches et routines resteront intacts.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Écris SUPPRIMER MA MÉMOIRE',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirmer la suppression'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) {
      var result = await _deleteAll(controller.text);
      while (result.status == MemoryLibraryActionStatus.synced &&
          result.nextCursor != null &&
          mounted) {
        result = await _deleteAll(
          controller.text,
          cursor: result.nextCursor,
        );
      }
    }
    controller.dispose();
  }

  Future<MemoryLibraryActionResult> _deleteAll(
    String confirmation, {
    String? cursor,
  }) async {
    final result = await _service!.deleteAllPage(
      confirmation: confirmation,
      afterMemoryId: cursor,
    );
    await _showResult(result);
    return result;
  }

  Future<void> _run(
    Future<MemoryLibraryActionResult> Function() action,
    BuildContext sheetContext,
  ) async {
    final result = await action();
    if (sheetContext.mounted) Navigator.pop(sheetContext);
    await _showResult(result);
  }

  Future<void> _showResult(MemoryLibraryActionResult result) async {
    await _refresh();
    if (!mounted) return;
    final message = switch (result.status) {
      MemoryLibraryActionStatus.synced => 'Modification enregistrée.',
      MemoryLibraryActionStatus.pendingSync =>
        'Modification enregistrée sur cet appareil, en attente de synchronisation.',
      MemoryLibraryActionStatus.conflict =>
        'Cette information a changé sur un autre appareil. Recharge-la avant de continuer.',
      MemoryLibraryActionStatus.blockedByPolicy =>
        'Tes réglages de mémoire ne permettent pas cette action.',
      MemoryLibraryActionStatus.protectedDomain =>
        'Cette information dépend d’un autre espace de Zélia et ne peut pas être modifiée ici.',
      _ => 'Cette modification n’a pas pu être enregistrée.',
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  bool _active(RevisionedMemory memory) =>
      memory.lifecycleStatus == MemoryLifecycleState.active ||
      memory.lifecycleStatus == MemoryLifecycleState.confirmed;

  String _filterLabel(MemoryLibraryFilter filter) => switch (filter) {
        MemoryLibraryFilter.all => 'Tout',
        MemoryLibraryFilter.preference => 'Préférences',
        MemoryLibraryFilter.habit => 'Habitudes',
        MemoryLibraryFilter.goal => 'Objectifs',
        MemoryLibraryFilter.constraint => 'Contraintes',
        MemoryLibraryFilter.instruction => 'Instructions',
        MemoryLibraryFilter.personalFact => 'Informations personnelles',
        MemoryLibraryFilter.health => 'Santé',
        MemoryLibraryFilter.historical => 'Archivés ou expirés',
      };

  String _categoryLabel(String category) => switch (category) {
        'preference' => 'Préférence',
        'habit' => 'Habitude',
        'goal' => 'Objectif',
        'constraint' => 'Contrainte',
        'instruction' => 'Instruction',
        'personalFact' => 'Information personnelle',
        'health' => 'Santé',
        _ => 'Autre information',
      };

  String _historyLabel(MemoryHistoryAction action) => switch (action) {
        MemoryHistoryAction.created => 'Création',
        MemoryHistoryAction.corrected => 'Correction',
        MemoryHistoryAction.confirmed => 'Confirmation',
        MemoryHistoryAction.rejected => 'Rejet',
        MemoryHistoryAction.postponed => 'Décision reportée',
        MemoryHistoryAction.archived => 'Archivage',
        MemoryHistoryAction.expired => 'Expiration',
        MemoryHistoryAction.deleted => 'Suppression',
        MemoryHistoryAction.restored => 'Restauration',
        MemoryHistoryAction.synchronized => 'Synchronisation',
        MemoryHistoryAction.conflict => 'Conflit de synchronisation',
      };
}

final class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Card(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(text),
          ),
        ),
      );
}

final class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text('Zélia n’a encore rien mémorisé ici.'),
        ),
      );
}

final class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message),
              const SizedBox(height: 12),
              FilledButton(onPressed: retry, child: const Text('Réessayer')),
            ],
          ),
        ),
      );
}
