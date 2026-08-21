import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/route_travel_time_service.dart';

typedef OrganizationAgendaSettingsSaved = Future<void> Function(
  UserProfile profile,
);

class OrganizationAgendaSettingsScreen extends StatefulWidget {
  const OrganizationAgendaSettingsScreen({
    super.key,
    required this.profile,
    required this.onSave,
    this.travelConsentGateway = const AppleMapsRouteTravelTimeGateway(),
  });

  final UserProfile profile;
  final OrganizationAgendaSettingsSaved onSave;
  final RouteTravelConsentGateway travelConsentGateway;

  @override
  State<OrganizationAgendaSettingsScreen> createState() =>
      _OrganizationAgendaSettingsScreenState();
}

class _OrganizationAgendaSettingsScreenState
    extends State<OrganizationAgendaSettingsScreen> {
  static const _background = Color(0xFFF8EFEA);
  static const _accent = Color(0xFFE95D5D);
  static const _soft = Color(0xFF8B6F67);
  static const _dark = Color(0xFF1F1A18);

  late UserProfile _profile;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
    _refreshTravelAuthorization();
  }

  Future<void> _refreshTravelAuthorization() async {
    final authorized = await widget.travelConsentGateway.isAuthorized();
    if (!mounted || authorized || !_profile.automaticTravelCalculationEnabled) {
      return;
    }
    setState(() {
      _profile = _profile.copyWith(
        automaticTravelCalculationEnabled: false,
      );
    });
  }

  Future<void> _persist(UserProfile updated) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _profile = updated;
    });
    try {
      await widget.onSave(updated);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ce réglage n’a pas pu être enregistré.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changeAutomaticTravel(bool enabled) async {
    if (_saving) return;
    if (enabled) {
      final accepted = await _showTravelExplanation();
      if (accepted != true || !mounted) return;
    }
    try {
      await widget.travelConsentGateway.setAuthorized(enabled);
      await _persist(
        _profile.copyWith(automaticTravelCalculationEnabled: enabled),
      );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ce réglage n’a pas pu être enregistré.')),
      );
    }
  }

  Future<bool?> _showTravelExplanation() => showModalBottomSheet<bool>(
        context: context,
        backgroundColor: _background,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        builder: (sheetContext) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 46,
                    height: 5,
                    decoration: BoxDecoration(
                      color: _soft.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Calcul automatique des trajets',
                  style: TextStyle(
                    fontFamily: 'PlayfairDisplay',
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Zelia utilisera Apple Plans pour estimer les trajets '
                  'avant et après tes rendez-vous. Ta position précise '
                  'n’est pas enregistrée dans ton profil.',
                  style: TextStyle(color: _soft, height: 1.45),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(sheetContext, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Autoriser les calculs'),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(sheetContext, false),
                  child: const Text('Pas maintenant'),
                ),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text(
          'Organisation et agenda',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
        children: [
          const Text(
            'Ton organisation',
            style: TextStyle(
              fontFamily: 'PlayfairDisplay',
              fontSize: 38,
              fontWeight: FontWeight.w700,
              color: _dark,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choisis ce que tu veux voir. Zelia continue de tenir compte '
            'des éléments masqués pour t’aider.',
            style: TextStyle(color: _soft, height: 1.4),
          ),
          const SizedBox(height: 28),
          _sectionTitle('TRAJETS'),
          const SizedBox(height: 8),
          _card([
            _switchTile(
              icon: Icons.route_outlined,
              title: 'Calcul automatique des trajets',
              subtitle: 'Avant et après chaque rendez-vous',
              value: _profile.automaticTravelCalculationEnabled,
              onChanged: _changeAutomaticTravel,
            ),
          ]),
          const SizedBox(height: 24),
          _sectionTitle('MARGE ENTRE DEUX RENDEZ-VOUS'),
          const SizedBox(height: 8),
          _card([
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 18, 18, 12),
              child: Text(
                'Un peu de temps en plus pour éviter de courir.',
                style: TextStyle(color: _soft),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final minutes in const [0, 5, 10, 15])
                    ChoiceChip(
                      label: Text(minutes == 0 ? 'Aucune' : '$minutes min'),
                      selected: _profile.agendaSafetyMarginMinutes == minutes,
                      selectedColor: _accent.withValues(alpha: 0.18),
                      onSelected: _saving
                          ? null
                          : (_) => _persist(
                                _profile.copyWith(
                                  agendaSafetyMarginMinutes: minutes,
                                ),
                              ),
                    ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 24),
          _sectionTitle('AFFICHER DANS MON AGENDA'),
          const SizedBox(height: 8),
          _card([
            _switchTile(
              icon: Icons.self_improvement_outlined,
              title: 'Mes activités',
              value: _profile.showPersonalActivitiesInAgenda,
              onChanged: (value) => _persist(
                _profile.copyWith(showPersonalActivitiesInAgenda: value),
              ),
            ),
            _divider,
            _switchTile(
              icon: Icons.child_care_outlined,
              title: 'Activités de mes enfants',
              value: _profile.showChildActivitiesInAgenda,
              onChanged: (value) => _persist(
                _profile.copyWith(showChildActivitiesInAgenda: value),
              ),
            ),
            _divider,
            _switchTile(
              icon: Icons.work_outline_rounded,
              title: 'Mes horaires de travail',
              value: _profile.showWorkScheduleInAgenda,
              onChanged: (value) => _persist(
                _profile.copyWith(showWorkScheduleInAgenda: value),
              ),
            ),
            _divider,
            _switchTile(
              icon: Icons.school_outlined,
              title: 'Horaires d’école',
              value: _profile.showSchoolScheduleInAgenda,
              onChanged: (value) => _persist(
                _profile.copyWith(showSchoolScheduleInAgenda: value),
              ),
            ),
            _divider,
            _switchTile(
              icon: Icons.autorenew_rounded,
              title: 'Mes routines',
              value: _profile.showRoutinesInAgenda,
              onChanged: (value) => _persist(
                _profile.copyWith(showRoutinesInAgenda: value),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _sectionTitle(String label) => Text(
        label,
        style: const TextStyle(
          color: _soft,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      );

  Widget _card(List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white),
        ),
        child: Column(children: children),
      );

  Widget _switchTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      ListTile(
        minTileHeight: 70,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: _accent),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle,
                style: const TextStyle(color: _soft, fontSize: 13)),
        trailing: Switch.adaptive(
          value: value,
          activeTrackColor: _accent,
          onChanged: _saving ? null : onChanged,
        ),
      );

  Widget get _divider => const Divider(height: 1, indent: 72);
}
