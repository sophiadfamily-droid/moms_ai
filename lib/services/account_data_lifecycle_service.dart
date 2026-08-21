import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';

typedef AccountDataCallableInvoker = Future<dynamic> Function(
  Map<String, dynamic> data,
);
typedef AccountAuthenticationBootstrap = Future<String> Function();
typedef AccountLocalDataCleaner = Future<void> Function(String accountScopeId);

final class AccountDataLifecycleException implements Exception {
  const AccountDataLifecycleException(this.code);

  final String code;

  @override
  String toString() => 'AccountDataLifecycleException($code)';
}

final class AccountDataExportFile {
  const AccountDataExportFile({
    required this.bytes,
    required this.fileName,
    this.mimeType = 'application/octet-stream',
    this.additionalFiles = const [],
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  final List<AccountDataExportFile> additionalFiles;
}

abstract interface class AccountDataLifecycleGateway {
  Future<AccountDataExportFile> prepareExport();

  Future<void> deleteAllData();
}

abstract interface class AccountDataExportPresenter {
  Future<void> present(AccountDataExportFile file);
}

final class SharePlusAccountDataExportPresenter
    implements AccountDataExportPresenter {
  const SharePlusAccountDataExportPresenter();

  @override
  Future<void> present(AccountDataExportFile file) async {
    final files = [file, ...file.additionalFiles];
    await SharePlus.instance.share(
      ShareParams(
        files: [
          for (final item in files)
            XFile.fromData(item.bytes, mimeType: item.mimeType),
        ],
        fileNameOverrides: [for (final item in files) item.fileName],
        subject: 'Mes données Zelia',
      ),
    );
  }
}

/// Removes only preferences whose colon-delimited scope is the deleted UID.
/// Global settings and data belonging to another account remain untouched.
final class AccountScopedLocalDataCleaner {
  const AccountScopedLocalDataCleaner();

  Future<void> clear(String accountScopeId) async {
    final scope = accountScopeId.trim();
    if (scope.isEmpty || scope == 'guest') {
      throw const AccountDataLifecycleException('invalid_account_scope');
    }
    final preferences = await SharedPreferences.getInstance();
    final scopedKeys = preferences.getKeys().where((key) {
      return key.split(':').contains(scope);
    }).toList(growable: false);
    for (final key in scopedKeys) {
      await preferences.remove(key);
    }
  }
}

/// Authenticated account export/deletion gateway. The client never sends a
/// UID: the callable binds every operation to the verified Firebase session.
final class CallableAccountDataLifecycleService
    implements AccountDataLifecycleGateway {
  CallableAccountDataLifecycleService({
    FirebaseFunctions? functions,
    Duration timeout = const Duration(seconds: 120),
    AccountAuthenticationBootstrap ensureAuthenticatedUid =
        AuthService.ensureAuthenticatedUid,
    AccountLocalDataCleaner? clearLocalData,
  })  : _invoke = _firebaseInvoker(functions, timeout),
        _ensureAuthenticatedUid = ensureAuthenticatedUid,
        _clearLocalData =
            clearLocalData ?? const AccountScopedLocalDataCleaner().clear;

  CallableAccountDataLifecycleService.withInvoker(
    AccountDataCallableInvoker invoker, {
    AccountAuthenticationBootstrap? ensureAuthenticatedUid,
    AccountLocalDataCleaner? clearLocalData,
  })  : _invoke = invoker,
        _ensureAuthenticatedUid =
            ensureAuthenticatedUid ?? (() async => 'test-account'),
        _clearLocalData = clearLocalData ?? ((_) async {});

  static const functionName = 'manageAccountDataCallable';
  static const region = 'us-central1';

  final AccountDataCallableInvoker _invoke;
  final AccountAuthenticationBootstrap _ensureAuthenticatedUid;
  final AccountLocalDataCleaner _clearLocalData;

  static AccountDataCallableInvoker _firebaseInvoker(
    FirebaseFunctions? functions,
    Duration timeout,
  ) {
    final callable =
        (functions ?? FirebaseFunctions.instanceFor(region: region))
            .httpsCallable(
      functionName,
      options: HttpsCallableOptions(timeout: timeout),
    );
    return (data) async => (await callable.call<dynamic>(data)).data;
  }

  @override
  Future<AccountDataExportFile> prepareExport() async {
    await _ensureAuthenticatedUid();
    final response = await _call({
      'schemaVersion': 1,
      'operation': 'export',
    });
    if (response['operation'] != 'export' || response['export'] is! Map) {
      throw const AccountDataLifecycleException('invalid_export_response');
    }
    final export = Map<String, dynamic>.from(response['export'] as Map);
    if (export['schemaVersion'] != 1 || export['account'] is! Map) {
      throw const AccountDataLifecycleException('invalid_export_response');
    }
    final bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(export)),
    );
    final readableBytes = await AccountDataReadablePdfBuilder().build(export);
    final now = DateTime.now();
    final date = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    return AccountDataExportFile(
      bytes: readableBytes,
      fileName: 'zelia-mes-informations-$date.pdf',
      mimeType: 'application/pdf',
      additionalFiles: [
        AccountDataExportFile(
          bytes: bytes,
          fileName: 'zelia-donnees-completes-$date.json',
          mimeType: 'application/json',
        ),
      ],
    );
  }

  @override
  Future<void> deleteAllData() async {
    final accountScopeId = await _ensureAuthenticatedUid();
    final response = await _call({
      'schemaVersion': 1,
      'operation': 'delete',
      'confirmation': 'SUPPRIMER',
    });
    if (response['operation'] != 'delete' || response['deleted'] != true) {
      throw const AccountDataLifecycleException('invalid_delete_response');
    }
    await _clearLocalData(accountScopeId);
  }

  Future<Map<String, dynamic>> _call(Map<String, dynamic> request) async {
    try {
      final response = await _invoke(request);
      if (response is! Map) {
        throw const AccountDataLifecycleException('invalid_response');
      }
      return Map<String, dynamic>.from(response);
    } on AccountDataLifecycleException {
      rethrow;
    } on FirebaseFunctionsException catch (error) {
      throw AccountDataLifecycleException(
        switch (error.code) {
          'unauthenticated' => 'authentication_required',
          'failed-precondition' => 'app_check_required',
          'resource-exhausted' => 'export_too_large',
          _ => 'operation_unavailable',
        },
      );
    } on Object {
      throw const AccountDataLifecycleException('operation_unavailable');
    }
  }
}

/// Creates a deliberately simple document for the account owner. The JSON
/// companion remains the exhaustive machine-readable source of truth.
final class AccountDataReadablePdfBuilder {
  static const _ignoredKeys = {
    'schemaVersion',
    'accountScopeId',
    'logicalRequestId',
    'mutationId',
    'lastMutationId',
    'sourceRevision',
    'materialFingerprint',
  };

  Future<Uint8List> build(Map<String, dynamic> export) async {
    final regular = await _loadFont(
      'assets/fonts/nunito/Nunito[wght].ttf',
      fallback: pw.Font.helvetica(),
    );
    final titleFont = await _loadFont(
      'assets/fonts/playfair_display/PlayfairDisplay[wght].ttf',
      fallback: pw.Font.times(),
    );
    final sections = _sections(export);
    final generatedAt = _friendlyDate(export['generatedAt']);
    final account = export['account'] is Map
        ? Map<String, dynamic>.from(export['account'] as Map)
        : const <String, dynamic>{};
    final email = account['email']?.toString().trim();
    final document = pw.Document(
      title: 'Mes informations Zelia',
      author: 'Zelia',
    );
    final accent = PdfColor.fromHex('#E95D5D');
    final soft = PdfColor.fromHex('#8B6F67');
    final background = PdfColor.fromHex('#F8EFEA');

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(38, 40, 38, 42),
        maxPages: 400,
        theme: pw.ThemeData.withFont(base: regular, bold: regular),
        header: (context) => context.pageNumber == 1
            ? pw.SizedBox()
            : pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 12),
                child: pw.Text(
                  'Mes informations Zelia',
                  style: pw.TextStyle(color: soft, fontSize: 9),
                ),
              ),
        footer: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 12),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Export personnel - à conserver dans un endroit sûr',
                style: pw.TextStyle(color: soft, fontSize: 8),
              ),
              pw.Text(
                'Page ${context.pageNumber}/${context.pagesCount}',
                style: pw.TextStyle(color: soft, fontSize: 8),
              ),
            ],
          ),
        ),
        build: (context) => [
          pw.Text(
            'Mes informations Zelia',
            style: pw.TextStyle(
              font: titleFont,
              fontSize: 30,
              color: PdfColor.fromHex('#3B211C'),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Une version claire des informations enregistrées pour mieux '
            't’accompagner au quotidien.',
            style: pw.TextStyle(color: soft, fontSize: 12, lineSpacing: 3),
          ),
          pw.SizedBox(height: 16),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: background,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (email != null && email.isNotEmpty)
                  _line('Compte', email, soft),
                _line('Export préparé le', generatedAt, soft),
                _line(
                  'Informations regroupées',
                  '${sections.values.fold<int>(0, (sum, items) => sum + items.length)}',
                  soft,
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          for (final section in sections.entries) ...[
            pw.Text(
              section.key,
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: accent,
              ),
            ),
            pw.SizedBox(height: 8),
            for (final item in section.value) _record(item, soft, background),
            pw.SizedBox(height: 14),
          ],
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: accent, width: 0.7),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
            ),
            child: pw.Text(
              'Le fichier JSON joint contient la copie technique complète de '
              'tes données. Il est utile pour une restauration ou un transfert.',
              style: pw.TextStyle(color: soft, fontSize: 10, lineSpacing: 2),
            ),
          ),
        ],
      ),
    );
    return document.save();
  }

  Future<pw.Font> _loadFont(String asset, {required pw.Font fallback}) async {
    try {
      final data = await rootBundle.load(asset);
      return pw.Font.ttf(data);
    } on Object {
      return fallback;
    }
  }

  pw.Widget _line(String label, String value, PdfColor color) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.RichText(
          text: pw.TextSpan(
            children: [
              pw.TextSpan(
                text: '$label : ',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.TextSpan(text: value, style: pw.TextStyle(color: color)),
            ],
          ),
        ),
      );

  pw.Widget _record(
    _ReadableAccountRecord record,
    PdfColor soft,
    PdfColor background,
  ) =>
      pw.Container(
        width: double.infinity,
        margin: const pw.EdgeInsets.only(bottom: 8),
        padding: const pw.EdgeInsets.all(11),
        decoration: pw.BoxDecoration(
          color: background,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(9)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              record.title,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
            ),
            if (record.fields.isEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 4),
                child: pw.Text(
                  'Information enregistrée (détails dans le fichier JSON).',
                  style: pw.TextStyle(color: soft, fontSize: 9),
                ),
              ),
            for (final field in record.fields.take(20))
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 3),
                child: pw.RichText(
                  text: pw.TextSpan(
                    children: [
                      pw.TextSpan(
                        text: '${field.label} : ',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                      pw.TextSpan(
                        text: field.value,
                        style: pw.TextStyle(color: soft),
                      ),
                    ],
                  ),
                ),
              ),
            if (record.fields.length > 20)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 4),
                child: pw.Text(
                  'Les autres détails sont disponibles dans le fichier JSON.',
                  style: pw.TextStyle(color: soft, fontSize: 9),
                ),
              ),
          ],
        ),
      );

  Map<String, List<_ReadableAccountRecord>> _sections(
    Map<String, dynamic> export,
  ) {
    final grouped = <String, List<_ReadableAccountRecord>>{};
    final rawDocuments = export['documents'];
    if (rawDocuments is! List) return grouped;
    for (final raw in rawDocuments.whereType<Map>()) {
      final document = Map<String, dynamic>.from(raw);
      final path = document['path']?.toString() ?? '';
      final data = document['data'] is Map
          ? Map<String, dynamic>.from(document['data'] as Map)
          : const <String, dynamic>{};
      final section = _sectionForPath(path);
      grouped.putIfAbsent(section, () => []).add(
            _ReadableAccountRecord(
              title: _recordTitle(path, data),
              fields: _fields(data),
            ),
          );
    }
    const order = [
      'Profil et foyer',
      'Agenda',
      'Tâches',
      'Courses',
      'Mémoire',
      'Routines et plannings',
      'Conversations',
      'Autres informations',
    ];
    return {
      for (final name in order)
        if (grouped[name]?.isNotEmpty == true) name: grouped[name]!,
    };
  }

  String _sectionForPath(String path) {
    final value = path.toLowerCase();
    if (_containsAny(value, [
      'profile',
      'profil',
      'human',
      'person',
      'family',
      'foyer',
      'household'
    ])) {
      return 'Profil et foyer';
    }
    if (_containsAny(value, ['event', 'agenda', 'calendar'])) return 'Agenda';
    if (value.contains('task')) return 'Tâches';
    if (_containsAny(value, ['shopping', 'course'])) return 'Courses';
    if (value.contains('memory')) return 'Mémoire';
    if (_containsAny(
        value, ['routine', 'activity', 'schedule', 'work', 'school'])) {
      return 'Routines et plannings';
    }
    if (_containsAny(value, ['conversation', 'chat', 'message'])) {
      return 'Conversations';
    }
    return 'Autres informations';
  }

  bool _containsAny(String value, List<String> terms) =>
      terms.any(value.contains);

  String _recordTitle(String path, Map<String, dynamic> data) {
    for (final key in const ['title', 'name', 'firstName', 'label']) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    if (path == '.' || path.isEmpty) return 'Profil principal';
    final leaf = path.split('/').last;
    return _friendlyLabel(leaf);
  }

  List<_ReadableAccountField> _fields(Map<String, dynamic> data) {
    final fields = <_ReadableAccountField>[];
    void visit(String prefix, Object? value, int depth) {
      if (value == null || depth > 2) return;
      if (value is Map) {
        for (final entry in value.entries) {
          final key = entry.key.toString();
          if (_isTechnicalKey(key)) continue;
          visit(prefix.isEmpty ? key : '$prefix.$key', entry.value, depth + 1);
        }
        return;
      }
      if (value is List) {
        final simple = value
            .where((item) => item is String || item is num || item is bool)
            .map(_friendlyValue)
            .where((item) => item.isNotEmpty)
            .take(12)
            .join(', ');
        if (simple.isNotEmpty) {
          fields.add(_ReadableAccountField(_friendlyLabel(prefix), simple));
        }
        return;
      }
      final text = _friendlyValue(value);
      if (text.isNotEmpty) {
        fields.add(
          _ReadableAccountField(
            _friendlyLabel(prefix),
            text.length > 500 ? '${text.substring(0, 500)}…' : text,
          ),
        );
      }
    }

    for (final entry in data.entries) {
      if (_isTechnicalKey(entry.key)) continue;
      visit(entry.key, entry.value, 0);
    }
    return fields;
  }

  bool _isTechnicalKey(String key) {
    if (_ignoredKeys.contains(key)) return true;
    final value = key.toLowerCase();
    return value.endsWith('revision') ||
        value.endsWith('fingerprint') ||
        value.contains('diagnostic') ||
        value.contains('technical');
  }

  String _friendlyLabel(String raw) {
    final leaf = raw.split('.').last;
    const labels = {
      'firstName': 'Prénom',
      'lastName': 'Nom',
      'birthDate': 'Date de naissance',
      'dateOfBirth': 'Date de naissance',
      'email': 'Adresse e-mail',
      'title': 'Titre',
      'name': 'Nom',
      'notes': 'Notes',
      'date': 'Date',
      'time': 'Heure',
      'startTime': 'Début',
      'endTime': 'Fin',
      'durationMinutes': 'Durée',
      'location': 'Lieu',
      'address': 'Adresse',
      'category': 'Catégorie',
      'completed': 'Terminé',
      'urgent': 'Urgent',
      'quantity': 'Quantité',
      'text': 'Information',
      'relationship': 'Lien',
      'familySituation': 'Situation familiale',
      'professionalStatus': 'Situation professionnelle',
    };
    final known = labels[leaf];
    if (known != null) return known;
    final spaced = leaf
        .replaceAllMapped(
            RegExp(r'([a-z0-9])([A-Z])'), (match) => '${match[1]} ${match[2]}')
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .trim();
    if (spaced.isEmpty) return 'Information';
    return '${spaced[0].toUpperCase()}${spaced.substring(1)}';
  }

  String _friendlyValue(Object? value) {
    if (value is bool) return value ? 'Oui' : 'Non';
    if (value is num) return value.toString();
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return '';
    final parsed = DateTime.tryParse(text);
    return parsed == null ? text : _formatDate(parsed);
  }

  String _friendlyDate(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed == null
        ? 'Date non disponible'
        : _formatDate(parsed.toLocal());
  }

  String _formatDate(DateTime value) {
    final date = '${value.day.toString().padLeft(2, '0')}/'
        '${value.month.toString().padLeft(2, '0')}/${value.year}';
    if (value.hour == 0 && value.minute == 0 && value.second == 0) return date;
    return '$date à ${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }
}

final class _ReadableAccountRecord {
  const _ReadableAccountRecord({required this.title, required this.fields});

  final String title;
  final List<_ReadableAccountField> fields;
}

final class _ReadableAccountField {
  const _ReadableAccountField(this.label, this.value);

  final String label;
  final String value;
}
