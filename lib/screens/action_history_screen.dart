import 'package:flutter/material.dart';

import '../models/action_autonomy_policy.dart';
import '../models/action_ledger.dart';
import '../services/action_ledger_service.dart';
import '../services/action_ledger_runtime.dart';
import '../services/action_undo_coordinator.dart';
import '../widgets/action_confirmation_dialog.dart';

final class ActionHistoryScreen extends StatefulWidget {
  const ActionHistoryScreen({
    super.key,
    this.ledgerService,
    this.onUndoRequested,
  });

  final ActionLedgerService? ledgerService;
  final Future<void> Function(ActionLedgerEntry entry)? onUndoRequested;

  @override
  State<ActionHistoryScreen> createState() => _ActionHistoryScreenState();
}

final class _ActionHistoryScreenState extends State<ActionHistoryScreen> {
  ActionLedgerService? _service;
  ActionUndoCoordinator? _undoCoordinator;
  ActionLedgerRuntime? _runtime;
  final List<ActionLedgerEntry> _entries = [];
  String? _cursor;
  bool _hasMore = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(initial: true);
  }

  Future<void> _load({required bool initial}) async {
    if (!initial && (!_hasMore || _loading)) return;
    if (mounted) setState(() => _loading = true);
    try {
      final service = _service ?? widget.ledgerService ?? _productionService();
      final page = initial && widget.ledgerService == null
          ? await (_runtime ??= await ActionLedgerRuntime.production())
              .bootstrap(limit: 20)
          : await service.history(
              limit: 20,
              cursor: initial ? null : _cursor,
            );
      if (!mounted) return;
      setState(() {
        _service = service;
        if (initial) _entries.clear();
        _entries.addAll(page.entries);
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _error = null;
      });
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'L’historique ne peut pas être chargé pour le moment.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  ActionLedgerService _productionService() => ActionLedgerService.production();

  Future<void> _undo(ActionLedgerEntry entry) async {
    if (widget.onUndoRequested != null) {
      await widget.onUndoRequested!(entry);
      await _load(initial: true);
      return;
    }
    try {
      final coordinator =
          _undoCoordinator ??= await ActionUndoCoordinator.production();
      var result = await coordinator.request(
        entry.ledgerEntryId,
      );
      if (!mounted) return;
      if (result.type == ActionUndoResultType.confirmationRequired) {
        final confirmation = coordinator.confirmationFor(entry.ledgerEntryId);
        if (confirmation == null) return;
        final choice = await ActionConfirmationDialog.show(
          context,
          presentation: confirmation.userPresentation,
        );
        if (choice == null) return;
        result = await coordinator.request(
          entry.ledgerEntryId,
          responseChoice: choice,
        );
      }
      if (!mounted) return;
      final message = switch (result.type) {
        ActionUndoResultType.ready => 'L’action a été annulée.',
        ActionUndoResultType.blockedByPolicy =>
          'Les actions sont actuellement en pause.',
        ActionUndoResultType.targetChanged =>
          'Cette action ne peut plus être annulée car la donnée a changé.',
        ActionUndoResultType.conflict => 'Un conflit empêche cette annulation.',
        _ => 'Cette action ne peut pas être annulée.',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      await _load(initial: true);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('L’annulation est indisponible pour le moment.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historique des actions')),
      body: SafeArea(
        child: _loading && _entries.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _entries.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _error ?? 'Aucune action à afficher.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _entries.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _entries.length) {
                        return Center(
                          child: TextButton(
                            onPressed:
                                _loading ? null : () => _load(initial: false),
                            child: const Text('Afficher la suite'),
                          ),
                        );
                      }
                      return _entryCard(_entries[index]);
                    },
                  ),
      ),
    );
  }

  Widget _entryCard(ActionLedgerEntry entry) => Card(
        child: ListTile(
          title: Text(_actionLabel(entry)),
          subtitle: Text(
            '${_domainLabel(entry.actionDomain)} · ${_statusLabel(entry.status)}'
            '\n${_originLabel(entry.actionOrigin)}'
            '${entry.status == ActionLedgerStatus.notUndoable ? '\nAnnulation non disponible.' : ''}',
          ),
          isThreeLine: true,
          trailing: entry.status == ActionLedgerStatus.undoAvailable
              ? TextButton(
                  onPressed: () => _undo(entry),
                  child: const Text('Annuler'),
                )
              : null,
        ),
      );

  static String _actionLabel(ActionLedgerEntry entry) =>
      switch (entry.targetReference.operationType) {
        'createTask' => 'Création d’une tâche',
        'addItem' => 'Ajout à la liste de courses',
        'createEvent' => 'Création d’un événement',
        'updateProfileFields' => 'Modification du profil',
        _ => 'Modification ${_domainLabel(entry.actionDomain).toLowerCase()}',
      };

  static String _domainLabel(ActionLedgerDomain domain) => const [
        'Agenda',
        'Tâches',
        'Courses',
        'Profil',
        'Profil humain',
        'Mémoire',
        'Identité',
        'Routine',
      ][domain.index];

  static String _statusLabel(ActionLedgerStatus status) => switch (status) {
        ActionLedgerStatus.succeeded ||
        ActionLedgerStatus.undoAvailable =>
          'Effectué',
        ActionLedgerStatus.pendingSync ||
        ActionLedgerStatus.dispatching ||
        ActionLedgerStatus.authorized =>
          'En attente',
        ActionLedgerStatus.conflict ||
        ActionLedgerStatus.undoConflict =>
          'Conflit',
        ActionLedgerStatus.undone => 'Annulé',
        ActionLedgerStatus.failed || ActionLedgerStatus.undoFailed => 'Échec',
        ActionLedgerStatus.blockedByPolicy => 'Bloqué',
        _ => 'En préparation',
      };

  static String _originLabel(origin) => switch (origin) {
        ActionOrigin.explicitUserRequest => 'Demandé par toi',
        ActionOrigin.explicitUserConfirmation => 'Confirmé par toi',
        ActionOrigin.assistantSuggestion => 'Suggestion confirmée',
        ActionOrigin.structuredContinuation => 'Continuation',
        _ => 'Action technique',
      };
}
