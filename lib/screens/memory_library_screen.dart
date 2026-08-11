import 'package:flutter/material.dart';

import '../models/memory_lifecycle_state.dart';
import '../models/memory_sync.dart';
import '../services/memory_library_service.dart';
import 'memory_settings_screen.dart';

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
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (!mounted) return;
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
    if (widget.initialSnapshot != null) {
      _snapshot = widget.initialSnapshot;
      _loading = false;
      return;
    }
    _refresh();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
      backgroundColor: const Color(0xFFF9EFEB),
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _ErrorState(message: _error!, retry: _refresh)
                      : snapshot == null
                          ? const SizedBox.shrink()
                          : _content(snapshot),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() => SizedBox(
        height: 232,
        child: Stack(
          children: [
            Positioned(
              right: -20,
              top: 8,
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.96,
                  child: Image.asset(
                    'assets/images/zelia_robot.png',
                    width: 205,
                    height: 220,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 18,
              top: 8,
              child: IconButton.filledTonal(
                tooltip: 'Retour',
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.arrow_back_ios_new),
              ),
            ),
            Positioned(
              right: 18,
              top: 8,
              child: IconButton.filledTonal(
                tooltip: 'Gérer ma mémoire',
                onPressed: _openMemoryManagement,
                icon: const Icon(Icons.more_horiz),
              ),
            ),
            const Positioned(
              left: 28,
              top: 88,
              right: 155,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mémoire',
                    style: TextStyle(
                      color: Color(0xFF11181C),
                      fontFamily: 'PlayfairDisplay',
                      fontSize: 44,
                      height: 1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 14),
                  Text(
                    'Ce que Zelia retient pour mieux t’accompagner.',
                    style: TextStyle(
                      color: Color(0xFF8B6F67),
                      fontSize: 15,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _content(MemoryLibrarySnapshot snapshot) {
    final selected = snapshot
        .filtered(_filter)
        .where((memory) =>
            _query.isEmpty || memory.text.toLowerCase().contains(_query))
        .toList();
    final memories = selected
        .where((memory) =>
            _active(memory) ||
            memory.lifecycleStatus == MemoryLifecycleState.proposed)
        .toList();
    final proposed = memories
        .where(
            (memory) => memory.lifecycleStatus == MemoryLifecycleState.proposed)
        .toList();
    final retained = memories.where(_active).toList();
    final activeCount = snapshot.memories.where(_active).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Rechercher dans ma mémoire…',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    onPressed: _searchController.clear,
                    icon: const Icon(Icons.close),
                  ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.9),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(28),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 18),
        if (snapshot.syncStatus != MemorySyncStatus.synced)
          _StatusBanner(
            text: snapshot.syncStatus == MemorySyncStatus.conflict
                ? 'Certaines informations ont changé sur un autre appareil.'
                : 'Certains changements seront synchronisés lorsque la connexion reviendra.',
          ),
        _overviewCard(snapshot, activeCount),
        const SizedBox(height: 18),
        _filters(snapshot),
        const SizedBox(height: 22),
        const Text(
          'Ce que Zelia sait de moi',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        if (proposed.isNotEmpty) ...[
          _memorySection('À vérifier', proposed, snapshot),
          const SizedBox(height: 12),
        ],
        if (retained.isNotEmpty)
          _memorySection(null, retained, snapshot)
        else if (proposed.isEmpty)
          const _EmptyState()
      ],
    );
  }

  BoxDecoration _memoryCardDecoration() => BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE76A5E).withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      );

  Widget _overviewCard(MemoryLibrarySnapshot snapshot, int activeCount) {
    final preferences =
        snapshot.filtered(MemoryLibraryFilter.preference).where(_active).length;
    final habits =
        snapshot.filtered(MemoryLibraryFilter.habit).where(_active).length;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFCFA), Color(0xFFF8E8E1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB77C6C).withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              CircleAvatar(
                backgroundColor: Color(0xFFF6D7CD),
                child: Icon(Icons.auto_awesome, color: Color(0xFFE76A5E)),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ma mémoire avec Zelia',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Des informations utiles pour mieux organiser mon quotidien.',
                      style: TextStyle(
                        color: Color(0xFF8B6F67),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _memoryStat(Icons.psychology_outlined, activeCount, 'retenues'),
              _memoryStat(Icons.favorite_border, preferences, 'préférences'),
              _memoryStat(Icons.repeat, habits, 'habitudes'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _memoryStat(IconData icon, int count, String label) => Expanded(
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFFD47C67), size: 22),
            const SizedBox(height: 5),
            Text(
              '$count',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF8B6F67), fontSize: 11),
            ),
          ],
        ),
      );

  Widget _filters(MemoryLibrarySnapshot snapshot) {
    final filters = <MemoryLibraryFilter>[
      MemoryLibraryFilter.all,
      ...MemoryLibraryFilter.values.where(
        (filter) =>
            filter != MemoryLibraryFilter.all &&
            filter != MemoryLibraryFilter.historical &&
            (filter != MemoryLibraryFilter.health ||
                snapshot.policy.healthConsentGranted) &&
            snapshot.filtered(filter).any(_active),
      ),
    ];
    return Semantics(
      label: 'Filtrer les informations',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters
              .map(
                (filter) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(_filterLabel(filter)),
                    selected: _filter == filter,
                    selectedColor: const Color(0xFFE9957E),
                    onSelected: (_) => setState(() => _filter = filter),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _memorySection(
    String? title,
    List<RevisionedMemory> memories,
    MemoryLibrarySnapshot snapshot,
  ) =>
      Container(
        decoration: _memoryCardDecoration(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
              ...memories.map(
                (memory) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFF8DDD5),
                    child: Icon(
                      _categoryIcon(memory.category),
                      color: const Color(0xFFE76A5E),
                    ),
                  ),
                  title: Text(
                    _displayText(memory.text),
                    maxLines: 3,
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

  Future<void> _openMemoryManagement() async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFFFFFAF7),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Gérer ma mémoire',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Réglages de la mémoire'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const MemorySettingsScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: Color(0xFF7450B8),
                ),
                title: const Text('Supprimer toute ma mémoire'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmDeleteAll(snapshot);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

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
      showDragHandle: true,
      backgroundColor: const Color(0xFFFFFAF7),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
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
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFE76A5E),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => _edit(memory, sheetContext),
                        child: const Text('Modifier'),
                      ),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF7450B8),
                          side: const BorderSide(color: Color(0xFF7450B8)),
                        ),
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
        backgroundColor: const Color(0xFFFFFAF7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Text(
          'Modifier ce souvenir',
          style: TextStyle(
            color: Color(0xFF4A342F),
            fontWeight: FontWeight.w800,
          ),
        ),
        content: TextField(
          controller: controller,
          maxLength: 4000,
          minLines: 2,
          maxLines: 6,
          decoration: InputDecoration(
            labelText: 'Information',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: const BorderSide(color: Color(0xFFF1D8D1)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE76A5E),
            ),
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
        backgroundColor: const Color(0xFFFFFAF7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
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
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF7450B8),
            ),
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
        backgroundColor: const Color(0xFFFFFAF7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
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
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF7450B8),
            ),
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

  String _displayText(String text) {
    var value = text.trim().replaceFirst(
          RegExp(
            r'^(souviens[- ]toi|rappelle[- ]toi|retiens(?: bien)?|mémorise|memorise|note bien)\s+(?:que\s+)?',
            caseSensitive: false,
          ),
          '',
        );
    if (value.isEmpty) return text.trim();
    value = value[0].toUpperCase() + value.substring(1);
    return value.endsWith('.') ? value : '$value.';
  }

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
        'preference' || 'preferences' => 'Préférence',
        'habit' => 'Habitude',
        'goal' => 'Objectif',
        'constraint' => 'Contrainte',
        'instruction' => 'Instruction',
        'personalFact' ||
        'personal' ||
        'personal_fact' =>
          'Information personnelle',
        'health' => 'Santé',
        _ => 'Autre information',
      };

  IconData _categoryIcon(String category) => switch (category) {
        'preference' || 'preferences' => Icons.favorite_border,
        'habit' || 'routine' => Icons.repeat,
        'goal' => Icons.flag_outlined,
        'constraint' => Icons.event_busy_outlined,
        'health' => Icons.health_and_safety_outlined,
        'work' || 'business' => Icons.work_outline,
        'family' || 'children' || 'partner' => Icons.people_outline,
        _ => Icons.person_outline,
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
