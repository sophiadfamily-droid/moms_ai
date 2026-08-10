import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class PrivacyDataScreen extends StatefulWidget {
  const PrivacyDataScreen({super.key});

  @override
  State<PrivacyDataScreen> createState() => _PrivacyDataScreenState();
}

class _PrivacyDataScreenState extends State<PrivacyDataScreen> {
  static const _background = Color(0xFFF8EFEA);
  static const _accent = Color(0xFFE95D5D);
  static const _soft = Color(0xFF8B6F67);

  Map<String, PermissionStatus> _statuses = const {};

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    try {
      final statuses = <String, PermissionStatus>{
        'Localisation': await Permission.locationWhenInUse.status,
        'Photos': await Permission.photos.status,
        'Microphone': await Permission.microphone.status,
        'Notifications': await Permission.notification.status,
      };
      if (mounted) setState(() => _statuses = statuses);
    } on Object {
      if (mounted) setState(() => _statuses = const {});
    }
  }

  String _statusLabel(PermissionStatus? status) {
    if (status == null) return 'Vérification…';
    if (status.isGranted || status.isLimited) return 'Autorisée';
    if (status.isPermanentlyDenied || status.isRestricted) return 'Refusée';
    return 'Non autorisée';
  }

  Future<void> _showFutureConnection(String title, String text) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
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
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'PlayfairDisplay',
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(text, style: const TextStyle(color: _soft, height: 1.45)),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('J’ai compris'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        title: const Text('Confidentialité'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          _sectionTitle('AUTORISATIONS'),
          const SizedBox(height: 8),
          _card(
            children: [
              for (final name in const [
                'Localisation',
                'Photos',
                'Microphone',
                'Notifications',
              ]) ...[
                _permissionRow(name),
                if (name != 'Notifications') const Divider(height: 1),
              ],
              const Divider(height: 1),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                minTileHeight: 58,
                leading: _iconBox(Icons.settings_outlined),
                title: const Text(
                  'Gérer les autorisations',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                trailing: const Icon(Icons.chevron_right, color: _soft),
                onTap: () async {
                  await openAppSettings();
                  await _loadPermissions();
                },
              ),
            ],
          ),
          const SizedBox(height: 26),
          _sectionTitle('MES DONNÉES'),
          const SizedBox(height: 8),
          _card(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                minTileHeight: 64,
                leading: _iconBox(Icons.download_outlined),
                title: const Text(
                  'Exporter mes données',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                trailing: const Icon(Icons.chevron_right, color: _soft),
                onTap: () => _showFutureConnection(
                  'Exporter mes données',
                  'L’espace est prêt. L’export complet sera activé lorsque toutes les données de Zelia seront raccordées au même compte.',
                ),
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                minTileHeight: 64,
                leading: _iconBox(Icons.delete_outline),
                title: const Text(
                  'Supprimer mes données',
                  style: TextStyle(
                    color: _accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right, color: _soft),
                onTap: () => _showFutureConnection(
                  'Supprimer mes données',
                  'Aucune donnée ne sera supprimée tant que la suppression complète et sécurisée de tous les espaces de Zelia ne sera pas raccordée.',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(left: 14),
        child: Text(
          title,
          style: const TextStyle(
            color: _soft,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
          ),
        ),
      );

  Widget _card({required List<Widget> children}) => Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _soft.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: _soft.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );

  Widget _permissionRow(String name) {
    final status = _statuses[name];
    final allowed = status?.isGranted == true || status?.isLimited == true;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      minTileHeight: 58,
      leading: _iconBox(_permissionIcon(name)),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _statusLabel(status),
            style: const TextStyle(color: _soft, fontSize: 14),
          ),
          const SizedBox(width: 8),
          Icon(
            allowed ? Icons.check_circle : Icons.remove_circle_outline,
            color: allowed ? const Color(0xFF5F9D82) : _soft,
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _iconBox(IconData icon) => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: _accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, size: 20, color: _accent),
      );

  IconData _permissionIcon(String name) => switch (name) {
        'Localisation' => Icons.location_on_outlined,
        'Photos' => Icons.photo_outlined,
        'Microphone' => Icons.mic_none,
        _ => Icons.notifications_none,
      };
}
