import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/action_autonomy_policy.dart';
import '../services/action_autonomy_policy_service.dart';

class ActionAutonomySettingsScreen extends StatefulWidget {
  const ActionAutonomySettingsScreen({super.key, this.policyService});

  final ActionAutonomyPolicyService? policyService;

  @override
  State<ActionAutonomySettingsScreen> createState() =>
      _ActionAutonomySettingsScreenState();
}

class _ActionAutonomySettingsScreenState
    extends State<ActionAutonomySettingsScreen> {
  ActionAutonomyPolicyService? _service;
  ActionAutonomyPolicy? _policy;
  ActionAutonomyMode? _selected;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final service = widget.policyService ??
          await ActionAutonomyPolicyService.local(
            currentAccountScopeId: () => FirebaseAuth.instance.currentUser?.uid,
          );
      final policy = await service.load();
      if (!mounted) return;
      setState(() {
        _service = service;
        _policy = policy;
        _selected = policy.mode;
      });
    } on Object {
      if (!mounted) return;
      setState(() => _error = 'Le réglage ne peut pas être chargé.');
    }
  }

  Future<void> _save(ActionAutonomyMode mode) async {
    final service = _service;
    if (service == null || _saving) return;
    setState(() {
      _selected = mode;
      _saving = true;
      _error = null;
    });
    try {
      final policy = await service.saveMode(mode);
      if (!mounted) return;
      setState(() => _policy = policy);
    } on Object {
      if (!mounted) return;
      setState(() => _error = 'Le réglage n’a pas pu être enregistré.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mode d’action')),
      body: SafeArea(
        child: _policy == null && _error == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text(
                    'Choisis comment Zélia gère les modifications que tu lui '
                    'demandes. Les protections sensibles restent actives.',
                  ),
                  const SizedBox(height: 16),
                  _modeTile(
                    ActionAutonomyMode.normal,
                    'Normal',
                    'Zélia peut effectuer les actions que tu lui demandes, '
                        'avec confirmation lorsque c’est nécessaire.',
                  ),
                  _modeTile(
                    ActionAutonomyMode.suggestions,
                    'Suggestions uniquement',
                    'Zélia prépare les actions, mais te demande toujours de '
                        'confirmer avant de modifier quoi que ce soit.',
                  ),
                  _modeTile(
                    ActionAutonomyMode.paused,
                    'Actions en pause',
                    'Zélia continue de répondre, mais ne propose ni '
                        'n’effectue de modification.',
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Le mode Normal ne lance aucune action en arrière-plan. '
                    'La pause ne supprime aucune donnée et un changement de '
                    'mode n’exécute pas les actions en attente. Les réglages '
                    'Mémoire et santé restent indépendants.',
                  ),
                  if (_saving) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _modeTile(
    ActionAutonomyMode mode,
    String title,
    String subtitle,
  ) =>
      ListTile(
        leading: Icon(
          _selected == mode
              ? Icons.radio_button_checked
              : Icons.radio_button_off,
        ),
        onTap: _saving ? null : () => _save(mode),
        title: Text(title),
        subtitle: Text(subtitle),
      );
}
