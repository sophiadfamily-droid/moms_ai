import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/account_data_lifecycle_service.dart';
import '../services/auth_service.dart';

typedef AccountDataDeleted = Future<void> Function();

class PrivacyDataScreen extends StatefulWidget {
  const PrivacyDataScreen({
    super.key,
    this.accountDataLifecycleGateway,
    this.accountDataExportPresenter,
    this.onAccountDataDeleted,
  });

  final AccountDataLifecycleGateway? accountDataLifecycleGateway;
  final AccountDataExportPresenter? accountDataExportPresenter;
  final AccountDataDeleted? onAccountDataDeleted;

  @override
  State<PrivacyDataScreen> createState() => _PrivacyDataScreenState();
}

class _PrivacyDataScreenState extends State<PrivacyDataScreen> {
  static const _background = Color(0xFFF8EFEA);
  static const _accent = Color(0xFFE95D5D);
  static const _soft = Color(0xFF8B6F67);

  Map<String, PermissionStatus> _statuses = const {};
  bool _exportingData = false;
  bool _deletingData = false;

  AccountDataLifecycleGateway get _accountDataLifecycle =>
      widget.accountDataLifecycleGateway ??
      CallableAccountDataLifecycleService();

  AccountDataExportPresenter get _exportPresenter =>
      widget.accountDataExportPresenter ??
      const SharePlusAccountDataExportPresenter();

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

  Future<void> _exportAccountData() async {
    if (_exportingData || _deletingData) return;
    setState(() => _exportingData = true);
    try {
      final file = await _accountDataLifecycle.prepareExport();
      if (!mounted) return;
      await _exportPresenter.present(file);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ton export est prêt.')),
        );
      }
    } on AccountDataLifecycleException catch (error) {
      if (mounted) _showAccountDataError(error);
    } on Object {
      if (mounted) _showAccountDataError();
    } finally {
      if (mounted) setState(() => _exportingData = false);
    }
  }

  void _showAccountDataError([AccountDataLifecycleException? error]) {
    final message = error?.code == 'export_too_large'
        ? 'Ton export est trop volumineux pour être préparé ici.'
        : 'Je n’ai pas pu terminer cette demande. Réessaie dans un instant.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showExportInProgressMessage() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Je prépare déjà ton export. La fenêtre de partage va s’ouvrir.',
          ),
        ),
      );
  }

  Future<void> _confirmAccountDataDeletion() async {
    if (_exportingData || _deletingData) return;
    var confirmed = false;
    final shouldDelete = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              24,
              18,
              24,
              24 + MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
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
                  'Supprimer mes données',
                  style: TextStyle(
                    fontFamily: 'PlayfairDisplay',
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Cette action efface définitivement ton profil, ton '
                  'agenda, tes tâches, tes courses, ta mémoire, tes routines '
                  'et tes conversations. Ton compte de connexion reste '
                  'disponible.',
                  style: TextStyle(color: _soft, height: 1.5),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Écris SUPPRIMER pour confirmer.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                TextField(
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    hintText: 'SUPPRIMER',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(18)),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (value) {
                    final next = value.trim() == 'SUPPRIMER';
                    if (next != confirmed) {
                      setSheetState(() => confirmed = next);
                    }
                  },
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _accent),
                    onPressed: confirmed
                        ? () => Navigator.pop(sheetContext, true)
                        : null,
                    child: const Text('Supprimer définitivement'),
                  ),
                ),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(sheetContext, false),
                    child: const Text('Garder mes données'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (shouldDelete == true && mounted) await _deleteAccountData();
  }

  Future<void> _deleteAccountData() async {
    setState(() => _deletingData = true);
    try {
      await _accountDataLifecycle.deleteAllData();
      if (widget.onAccountDataDeleted != null) {
        await widget.onAccountDataDeleted!.call();
      } else {
        await AuthService.signOut();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Tes données Zelia ont été supprimées.')),
        );
        Navigator.of(context).maybePop();
      }
    } on AccountDataLifecycleException catch (error) {
      if (mounted) _showAccountDataError(error);
    } on Object {
      if (mounted) _showAccountDataError();
    } finally {
      if (mounted) setState(() => _deletingData = false);
    }
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
                subtitle: _exportingData
                    ? const Text(
                        'Préparation en cours…',
                        style: TextStyle(color: _soft, fontSize: 13),
                      )
                    : null,
                trailing: _exportingData
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right, color: _soft),
                onTap: _deletingData
                    ? null
                    : _exportingData
                        ? _showExportInProgressMessage
                        : _exportAccountData,
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
                trailing: _deletingData
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right, color: _soft),
                onTap: _deletingData
                    ? null
                    : _exportingData
                        ? _showExportInProgressMessage
                        : _confirmAccountDataDeletion,
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
