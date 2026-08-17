import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:image_picker/image_picker.dart';

import '../models/structured_schedule_import.dart';
import 'auth_service.dart';

enum StructuredScheduleDocumentSourceAction {
  camera,
  photoLibrary,
  pdf,
}

typedef StructuredScheduleImagePathPicker = Future<String?> Function(
  ImageSource source,
);
typedef StructuredSchedulePdfPathPicker = Future<String?> Function();

/// The document chosen by the user.
///
/// This value is intentionally short-lived and must never be persisted in a
/// profile, a review or Firestore.
final class StructuredScheduleSelectedDocument {
  const StructuredScheduleSelectedDocument({
    required this.kind,
    required this.sourcePath,
  });

  final StructuredScheduleDocumentKind kind;
  final String sourcePath;
}

/// The person whose profile initiated the import.
///
/// Extraction starts with this person as the default subject. Every proposal
/// still carries its own subject so the review screen can correct a line that
/// actually concerns another household member.
final class StructuredScheduleImportRequestContext {
  const StructuredScheduleImportRequestContext({
    required this.accountScopeId,
    required this.subjectEntityId,
    required this.subjectLabel,
  });

  final String accountScopeId;
  final String subjectEntityId;
  final String subjectLabel;

  void validate() {
    if (accountScopeId.trim().isEmpty ||
        accountScopeId.length > 160 ||
        subjectEntityId.trim().isEmpty ||
        subjectEntityId.length > 160 ||
        subjectLabel.trim().isEmpty ||
        subjectLabel.length > 160) {
      throw const StructuredScheduleImportException(
        'invalid_import_request_context',
      );
    }
  }
}

/// App-owned copy made available only while a document is being analysed.
final class StructuredScheduleTransientDocument {
  const StructuredScheduleTransientDocument({
    required this.kind,
    required this.temporaryPath,
  });

  final StructuredScheduleDocumentKind kind;
  final String temporaryPath;
}

/// Structured extraction result. It deliberately contains no document path,
/// bytes or raw OCR text.
final class StructuredScheduleExtractionResult {
  StructuredScheduleExtractionResult({
    required this.importId,
    required List<StructuredScheduleProposal> proposals,
  }) : proposals = List.unmodifiable(proposals) {
    if (importId.trim().isEmpty ||
        importId.length > 160 ||
        this.proposals.length >
            StructuredScheduleImportReview.maximumProposals ||
        this.proposals.map((item) => item.proposalId).toSet().length !=
            this.proposals.length) {
      throw const StructuredScheduleImportException(
        'invalid_schedule_extraction_result',
      );
    }
  }

  final String importId;
  final List<StructuredScheduleProposal> proposals;

  factory StructuredScheduleExtractionResult.fromJson(
    Map<String, dynamic> json,
  ) {
    try {
      if (json['schemaVersion'] != 1 || json['proposals'] is! List) {
        throw const FormatException('invalid_schedule_extraction_result');
      }
      return StructuredScheduleExtractionResult(
        importId: json['importId'] as String,
        proposals: (json['proposals'] as List)
            .map(
              (value) => StructuredScheduleProposal.fromJson(
                Map<String, dynamic>.from(value as Map),
              ),
            )
            .toList(),
      );
    } on StructuredScheduleImportException {
      rethrow;
    } on Object catch (error) {
      throw FormatException('invalid_schedule_extraction_result', error);
    }
  }
}

abstract interface class StructuredScheduleDocumentAnalyzer {
  Future<StructuredScheduleExtractionResult> extract({
    required StructuredScheduleTransientDocument document,
    required StructuredScheduleImportRequestContext context,
  });
}

typedef StructuredScheduleCallableInvoker = Future<dynamic> Function(
  Map<String, dynamic> data,
);
typedef StructuredScheduleAuthenticationBootstrap = Future<String> Function();

/// Authenticated production analyser. The source only crosses the protected
/// callable boundary and is never persisted in a profile or Firestore.
final class CallableStructuredScheduleDocumentAnalyzer
    implements StructuredScheduleDocumentAnalyzer {
  CallableStructuredScheduleDocumentAnalyzer({
    FirebaseFunctions? functions,
    Duration timeout = const Duration(seconds: 60),
    StructuredScheduleAuthenticationBootstrap ensureAuthenticatedUid =
        AuthService.ensureAuthenticatedUid,
  })  : _invoke = _firebaseInvoker(functions, timeout),
        _ensureAuthenticatedUid = ensureAuthenticatedUid;

  CallableStructuredScheduleDocumentAnalyzer.withInvoker(
      StructuredScheduleCallableInvoker invoker,
      {StructuredScheduleAuthenticationBootstrap? ensureAuthenticatedUid})
      : _invoke = invoker,
        _ensureAuthenticatedUid =
            ensureAuthenticatedUid ?? (() async => 'test-authenticated-uid');

  static const functionName = 'analyzeStructuredScheduleDocumentCallable';
  static const region = 'us-central1';

  final StructuredScheduleCallableInvoker _invoke;
  final StructuredScheduleAuthenticationBootstrap _ensureAuthenticatedUid;

  static StructuredScheduleCallableInvoker _firebaseInvoker(
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
  Future<StructuredScheduleExtractionResult> extract({
    required StructuredScheduleTransientDocument document,
    required StructuredScheduleImportRequestContext context,
  }) async {
    final bytes = await File(document.temporaryPath).readAsBytes();

    try {
      await _ensureAuthenticatedUid();
      final response = await _invoke({
        'schemaVersion': 1,
        'documentKind': document.kind.name,
        'mimeType': _mimeType(document),
        'fileBase64': base64Encode(bytes),
        'subjectEntityId': context.subjectEntityId,
        'subjectLabel': context.subjectLabel,
      });
      if (response is! Map) {
        throw const StructuredScheduleImportException(
          'invalid_schedule_analysis_response',
        );
      }
      final result = StructuredScheduleExtractionResult.fromJson(
        Map<String, dynamic>.from(response),
      );
      if (result.proposals.isEmpty) {
        throw const StructuredScheduleImportException(
          'no_schedule_information_found',
        );
      }
      return result;
    } on StructuredScheduleImportException {
      rethrow;
    } on FirebaseFunctionsException catch (error) {
      throw StructuredScheduleImportException(
        switch (error.code) {
          'unauthenticated' => 'schedule_analysis_authentication_required',
          'failed-precondition' => 'schedule_analysis_app_check_required',
          'resource-exhausted' => 'schedule_analysis_quota_exceeded',
          'invalid-argument' => 'invalid_schedule_document',
          _ => 'schedule_analysis_unavailable',
        },
      );
    } on Object {
      throw const StructuredScheduleImportException(
        'invalid_schedule_analysis_response',
      );
    }
  }

  String _mimeType(StructuredScheduleTransientDocument document) {
    if (document.kind == StructuredScheduleDocumentKind.pdf) {
      return 'application/pdf';
    }
    final extension = document.temporaryPath.split('.').last.toLowerCase();
    return switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => throw const StructuredScheduleImportException(
          'unsupported_schedule_document',
        ),
    };
  }
}

/// Native document picker used by the future person-scoped import entry.
///
/// Callers choose whether the source is the camera, the photo library or a PDF
/// from Files. The picker itself performs no analysis and keeps no path.
final class DeviceStructuredScheduleDocumentPicker {
  DeviceStructuredScheduleDocumentPicker({
    StructuredScheduleImagePathPicker? pickImagePath,
    StructuredSchedulePdfPathPicker? pickPdfPath,
  })  : _pickImagePath = pickImagePath ?? _defaultImagePicker(),
        _pickPdfPath = pickPdfPath ?? _defaultPdfPicker;

  final StructuredScheduleImagePathPicker _pickImagePath;
  final StructuredSchedulePdfPathPicker _pickPdfPath;

  Future<StructuredScheduleSelectedDocument?> select(
    StructuredScheduleDocumentSourceAction action,
  ) async {
    switch (action) {
      case StructuredScheduleDocumentSourceAction.camera:
        return _imageSelection(await _pickImagePath(ImageSource.camera));
      case StructuredScheduleDocumentSourceAction.photoLibrary:
        return _imageSelection(await _pickImagePath(ImageSource.gallery));
      case StructuredScheduleDocumentSourceAction.pdf:
        final path = await _pickPdfPath();
        if (path == null) return null;
        return StructuredScheduleSelectedDocument(
          kind: StructuredScheduleDocumentKind.pdf,
          sourcePath: path,
        );
    }
  }

  StructuredScheduleSelectedDocument? _imageSelection(String? path) {
    if (path == null) return null;
    return StructuredScheduleSelectedDocument(
      kind: StructuredScheduleDocumentKind.image,
      sourcePath: path,
    );
  }

  static StructuredScheduleImagePathPicker _defaultImagePicker() {
    final picker = ImagePicker();
    return (source) async => (await picker.pickImage(
          source: source,
          imageQuality: 90,
        ))
            ?.path;
  }

  static Future<String?> _defaultPdfPicker() async {
    const pdfTypes = file_selector.XTypeGroup(
      label: 'PDF',
      extensions: ['pdf'],
      uniformTypeIdentifiers: ['com.adobe.pdf'],
      mimeTypes: ['application/pdf'],
    );
    return (await file_selector.openFile(
      acceptedTypeGroups: const [pdfTypes],
      confirmButtonText: 'Importer',
    ))
        ?.path;
  }
}

/// Gives the analyser an app-owned temporary copy, then always deletes it.
///
/// The original selected file is never edited or deleted, including when the
/// analyser fails. Only the unique directory created by this service is
/// removed.
final class StructuredScheduleTemporarySourceService {
  StructuredScheduleTemporarySourceService({
    Directory? temporaryRoot,
    this.maximumBytes = 20 * 1024 * 1024,
  }) : _temporaryRoot = temporaryRoot ?? Directory.systemTemp;

  static const Set<String> _imageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
  };

  final Directory _temporaryRoot;
  final int maximumBytes;

  Future<T> withTemporaryCopy<T>({
    required StructuredScheduleSelectedDocument selected,
    required Future<T> Function(StructuredScheduleTransientDocument document)
        operation,
  }) async {
    if (maximumBytes <= 0 || selected.sourcePath.trim().isEmpty) {
      throw const StructuredScheduleImportException(
        'invalid_selected_document',
      );
    }

    final source = File(selected.sourcePath);
    final extension = _extensionOf(selected.sourcePath);
    if (!_isAllowed(selected.kind, extension)) {
      throw const StructuredScheduleImportException(
        'unsupported_schedule_document',
      );
    }
    if (!await source.exists()) {
      throw const StructuredScheduleImportException(
        'schedule_document_not_found',
      );
    }
    final sourceLength = await source.length();
    if (sourceLength <= 0 || sourceLength > maximumBytes) {
      throw const StructuredScheduleImportException(
        'invalid_schedule_document_size',
      );
    }

    await _temporaryRoot.create(recursive: true);
    final temporaryDirectory = await _temporaryRoot.createTemp(
      'zelia_schedule_import_',
    );
    final temporaryFile = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}document.$extension',
    );

    try {
      await source.copy(temporaryFile.path);
      return await operation(
        StructuredScheduleTransientDocument(
          kind: selected.kind,
          temporaryPath: temporaryFile.path,
        ),
      );
    } finally {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    }
  }

  bool _isAllowed(StructuredScheduleDocumentKind kind, String extension) =>
      switch (kind) {
        StructuredScheduleDocumentKind.image =>
          _imageExtensions.contains(extension),
        StructuredScheduleDocumentKind.pdf => extension == 'pdf',
      };

  String _extensionOf(String path) {
    final fileName = path.split(RegExp(r'[/\\]')).last;
    final dot = fileName.lastIndexOf('.');
    return dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  }
}

/// Coordinates selection output, temporary analysis and review creation.
///
/// The returned review can only exist after [withTemporaryCopy] has completed,
/// which means the app-owned source copy has already been discarded.
final class StructuredScheduleDocumentImportCoordinator {
  StructuredScheduleDocumentImportCoordinator({
    required StructuredScheduleDocumentAnalyzer analyzer,
    StructuredScheduleTemporarySourceService? temporarySources,
    DateTime Function()? now,
  })  : _analyzer = analyzer,
        _temporarySources =
            temporarySources ?? StructuredScheduleTemporarySourceService(),
        _now = now ?? DateTime.now;

  final StructuredScheduleDocumentAnalyzer _analyzer;
  final StructuredScheduleTemporarySourceService _temporarySources;
  final DateTime Function() _now;

  Future<StructuredScheduleImportReview> prepareReview({
    required StructuredScheduleSelectedDocument selected,
    required StructuredScheduleImportRequestContext context,
  }) async {
    context.validate();
    final result = await _temporarySources.withTemporaryCopy(
      selected: selected,
      operation: (document) => _analyzer.extract(
        document: document,
        context: context,
      ),
    );

    return StructuredScheduleImportReview(
      importId: result.importId,
      accountScopeId: context.accountScopeId,
      initiatedForSubjectEntityId: context.subjectEntityId,
      initiatedForSubjectLabel: context.subjectLabel,
      documentKind: selected.kind,
      createdAt: _now().toUtc(),
      sourceWasDiscarded: true,
      proposals: result.proposals,
    );
  }
}
