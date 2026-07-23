import 'package:flutter/material.dart';

import '../models/memory_policy.dart';
import '../services/auth_service.dart';
import '../services/memory_policy_engine.dart';
import '../services/memory_policy_service.dart';

final class MemorySettingsScreen extends StatefulWidget {
  const MemorySettingsScreen({
    super.key,
    this.policyService,
  });

  final MemoryPolicyService? policyService;

  @override
  State<MemorySettingsScreen> createState() => _MemorySettingsScreenState();
}

final class _MemorySettingsScreenState extends State<MemorySettingsScreen> {
  MemoryPolicyService? _service;
  MemoryPolicy? _policy;
  MemoryGeneralMode _generalMode = MemoryGeneralMode.askEveryTime;
  MemoryHealthMode _healthMode = MemoryHealthMode.disabled;
  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final service = widget.policyService ??
          await MemoryPolicyService.local(
            currentAccountScopeId: () => AuthService.currentUserId,
          );
      final policy = await service.load();
      if (!mounted) return;
      setState(() {
        _service = service;
        _policy = policy;
        _generalMode = policy.generalMode;
        _healthMode = policy.healthMode;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage =
            'Les réglages de mémoire sont momentanément indisponibles.';
      });
    }
  }

  Future<void> _save() async {
    final policy = _policy;
    final service = _service;
    if (policy == null || service == null || _saving) return;
    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    try {
      final transition = const MemoryPolicyEngine().transition(
        current: policy,
        generalMode: _generalMode,
        healthMode: _healthMode,
        explicitHealthConsent: _healthMode == MemoryHealthMode.enabled,
        changedAt: DateTime.now(),
      );
      await service.save(transition.current);
      if (!mounted) return;
      setState(() {
        _policy = transition.current;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Réglages de mémoire enregistrés.')),
      );
    } on Object {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage =
            'Impossible d’enregistrer pour le moment. Tes choix sont conservés à l’écran.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mémoire Zélia')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text(
                    'Mémoire générale',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Le mode automatique ne mémorise pas tout. En pause, aucun nouveau souvenir n’est créé et les souvenirs existants restent conservés.',
                  ),
                  ...MemoryGeneralMode.values.map(
                    (mode) => ListTile(
                      title: Text(_generalLabel(mode)),
                      leading: Icon(
                        _generalMode == mode
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                      ),
                      onTap: _saving
                          ? null
                          : () => setState(() => _generalMode = mode),
                    ),
                  ),
                  const Divider(height: 32),
                  const Text(
                    'Informations de santé',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'La santé possède un réglage séparé. Zélia mémorise seulement ce que tu autorises et ne fournit aucun diagnostic médical.',
                  ),
                  ...MemoryHealthMode.values.map(
                    (mode) => ListTile(
                      title: Text(_healthLabel(mode)),
                      leading: Icon(
                        _healthMode == mode
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                      ),
                      onTap: _saving
                          ? null
                          : () => setState(() => _healthMode = mode),
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Enregistrement…' : 'Enregistrer'),
                  ),
                ],
              ),
      ),
    );
  }

  String _generalLabel(MemoryGeneralMode mode) => switch (mode) {
        MemoryGeneralMode.automatic => 'Automatique',
        MemoryGeneralMode.askEveryTime => 'Me demander à chaque fois',
        MemoryGeneralMode.paused => 'En pause',
      };

  String _healthLabel(MemoryHealthMode mode) => switch (mode) {
        MemoryHealthMode.disabled => 'Ne pas mémoriser',
        MemoryHealthMode.askEveryTime => 'Me demander à chaque fois',
        MemoryHealthMode.enabled => 'Autoriser la mémorisation',
      };
}
