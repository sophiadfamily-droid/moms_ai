import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:moms_ai/models/structured_schedule_import.dart';
import 'package:moms_ai/services/structured_schedule_document_import_service.dart';

void main() {
  late Directory sandbox;
  late Directory originals;
  late Directory temporaryRoot;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('zelia_import_test_');
    originals = await Directory(
      '${sandbox.path}${Platform.pathSeparator}originals',
    ).create();
    temporaryRoot = await Directory(
      '${sandbox.path}${Platform.pathSeparator}app_temp',
    ).create();
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test('la copie temporaire est supprimée sans toucher à l’original', () async {
    final original = await _document(originals, 'planning.pdf');
    String? temporaryPath;
    final service = StructuredScheduleTemporarySourceService(
      temporaryRoot: temporaryRoot,
    );

    final value = await service.withTemporaryCopy(
      selected: StructuredScheduleSelectedDocument(
        kind: StructuredScheduleDocumentKind.pdf,
        sourcePath: original.path,
      ),
      operation: (document) async {
        temporaryPath = document.temporaryPath;
        expect(await File(document.temporaryPath).exists(), isTrue);
        expect(await File(document.temporaryPath).readAsString(), 'planning');
        return 'analysé';
      },
    );

    expect(value, 'analysé');
    expect(await original.exists(), isTrue);
    expect(await original.readAsString(), 'planning');
    expect(await File(temporaryPath!).exists(), isFalse);
    expect(await temporaryRoot.list().toList(), isEmpty);
  });

  test('la copie temporaire est aussi supprimée si l’analyse échoue', () async {
    final original = await _document(originals, 'planning.png');
    String? temporaryPath;
    final service = StructuredScheduleTemporarySourceService(
      temporaryRoot: temporaryRoot,
    );

    await expectLater(
      service.withTemporaryCopy<void>(
        selected: StructuredScheduleSelectedDocument(
          kind: StructuredScheduleDocumentKind.image,
          sourcePath: original.path,
        ),
        operation: (document) async {
          temporaryPath = document.temporaryPath;
          throw StateError('analyse impossible');
        },
      ),
      throwsStateError,
    );

    expect(await original.exists(), isTrue);
    expect(await File(temporaryPath!).exists(), isFalse);
    expect(await temporaryRoot.list().toList(), isEmpty);
  });

  test('la revue est créée après suppression et garde la personne initiatrice',
      () async {
    final original = await _document(originals, 'planning.jpg');
    final analyzer = _RecordingAnalyzer();
    final coordinator = StructuredScheduleDocumentImportCoordinator(
      analyzer: analyzer,
      temporarySources: StructuredScheduleTemporarySourceService(
        temporaryRoot: temporaryRoot,
      ),
      now: () => DateTime.utc(2026, 8, 17, 12),
    );

    final review = await coordinator.prepareReview(
      selected: StructuredScheduleSelectedDocument(
        kind: StructuredScheduleDocumentKind.image,
        sourcePath: original.path,
      ),
      context: const StructuredScheduleImportRequestContext(
        accountScopeId: 'account-1',
        subjectEntityId: 'child-kassim',
        subjectLabel: 'Kassim',
      ),
    );

    expect(analyzer.sawTemporaryFile, isTrue);
    expect(analyzer.context?.subjectEntityId, 'child-kassim');
    expect(review.initiatedForSubjectEntityId, 'child-kassim');
    expect(review.initiatedForSubjectLabel, 'Kassim');
    expect(review.sourceWasDiscarded, isTrue);
    expect(await original.exists(), isTrue);
    expect(await temporaryRoot.list().toList(), isEmpty);
  });

  test('un type incohérent ou un fichier trop lourd est refusé', () async {
    final imageNamedPdf = await _document(originals, 'planning.pdf');
    final largePdf = File(
      '${originals.path}${Platform.pathSeparator}large.pdf',
    );
    await largePdf.writeAsBytes(List.filled(20, 1));
    final service = StructuredScheduleTemporarySourceService(
      temporaryRoot: temporaryRoot,
      maximumBytes: 10,
    );

    await expectLater(
      service.withTemporaryCopy<void>(
        selected: StructuredScheduleSelectedDocument(
          kind: StructuredScheduleDocumentKind.image,
          sourcePath: imageNamedPdf.path,
        ),
        operation: (_) async {},
      ),
      throwsA(_code('unsupported_schedule_document')),
    );
    await expectLater(
      service.withTemporaryCopy<void>(
        selected: StructuredScheduleSelectedDocument(
          kind: StructuredScheduleDocumentKind.pdf,
          sourcePath: largePdf.path,
        ),
        operation: (_) async {},
      ),
      throwsA(_code('invalid_schedule_document_size')),
    );
  });

  test('le sélecteur distingue caméra, photothèque et PDF', () async {
    final calls = <ImageSource>[];
    final picker = DeviceStructuredScheduleDocumentPicker(
      pickImagePath: (source) async {
        calls.add(source);
        return source == ImageSource.camera ? '/camera.jpg' : '/gallery.png';
      },
      pickPdfPath: () async => '/files/planning.pdf',
    );

    final camera = await picker.select(
      StructuredScheduleDocumentSourceAction.camera,
    );
    final gallery = await picker.select(
      StructuredScheduleDocumentSourceAction.photoLibrary,
    );
    final pdf = await picker.select(
      StructuredScheduleDocumentSourceAction.pdf,
    );

    expect(calls, [ImageSource.camera, ImageSource.gallery]);
    expect(camera?.kind, StructuredScheduleDocumentKind.image);
    expect(gallery?.sourcePath, '/gallery.png');
    expect(pdf?.kind, StructuredScheduleDocumentKind.pdf);
  });

  test('l’analyse callable envoie le document avec la personne du profil',
      () async {
    final source = File(
      '${temporaryRoot.path}${Platform.pathSeparator}document.pdf',
    );
    await source.writeAsBytes('%PDF-1.7\nplanning'.codeUnits);
    final calls = <Map<String, dynamic>>[];
    final analyzer = CallableStructuredScheduleDocumentAnalyzer.withInvoker(
      (payload) async {
        calls.add(payload);
        return {
          'schemaVersion': 1,
          'importId': 'import-callable',
          'proposals': [
            {
              'schemaVersion': 1,
              'proposalId': 'proposal-1',
              'target': 'workSchedule',
              'temporalKind': 'recurringWeekly',
              'title': 'Travail',
              'subjectEntityId': 'partner-1',
              'subjectLabel': 'Willy',
              'dateIso': null,
              'weekdays': [1],
              'startTime': '09:00',
              'endTime': '17:00',
              'place': null,
              'confidence': 'high',
              'uncertainties': <String>[],
              'state': 'pendingReview',
            },
          ],
        };
      },
    );

    final result = await analyzer.extract(
      document: StructuredScheduleTransientDocument(
        kind: StructuredScheduleDocumentKind.pdf,
        temporaryPath: source.path,
      ),
      context: const StructuredScheduleImportRequestContext(
        accountScopeId: 'account-1',
        subjectEntityId: 'partner-1',
        subjectLabel: 'Willy',
      ),
    );

    expect(result.importId, 'import-callable');
    expect(result.proposals.single.subjectEntityId, 'partner-1');
    expect(calls.single['documentKind'], 'pdf');
    expect(calls.single['mimeType'], 'application/pdf');
    expect(calls.single['subjectLabel'], 'Willy');
    expect(calls.single.containsKey('accountScopeId'), isFalse);
  });

  test('une analyse vide ne crée aucune donnée inventée', () async {
    final source = await _document(temporaryRoot, 'document.pdf');
    final analyzer = CallableStructuredScheduleDocumentAnalyzer.withInvoker(
      (_) async => {
        'schemaVersion': 1,
        'importId': 'import-empty',
        'proposals': <Object?>[],
      },
    );

    await expectLater(
      analyzer.extract(
        document: StructuredScheduleTransientDocument(
          kind: StructuredScheduleDocumentKind.pdf,
          temporaryPath: source.path,
        ),
        context: const StructuredScheduleImportRequestContext(
          accountScopeId: 'account-1',
          subjectEntityId: 'user-1',
          subjectLabel: 'Sophia',
        ),
      ),
      throwsA(_code('no_schedule_information_found')),
    );
  });
}

Future<File> _document(Directory directory, String name) async {
  final file = File('${directory.path}${Platform.pathSeparator}$name');
  await file.writeAsString('planning');
  return file;
}

final class _RecordingAnalyzer implements StructuredScheduleDocumentAnalyzer {
  bool sawTemporaryFile = false;
  StructuredScheduleImportRequestContext? context;

  @override
  Future<StructuredScheduleExtractionResult> extract({
    required StructuredScheduleTransientDocument document,
    required StructuredScheduleImportRequestContext context,
  }) async {
    this.context = context;
    sawTemporaryFile = await File(document.temporaryPath).exists();
    return StructuredScheduleExtractionResult(
      importId: 'import-1',
      proposals: [
        StructuredScheduleProposal(
          proposalId: 'school-1',
          target: StructuredScheduleTarget.schoolSchedule,
          temporalKind: StructuredScheduleTemporalKind.recurringWeekly,
          title: 'École',
          subjectEntityId: context.subjectEntityId,
          subjectLabel: context.subjectLabel,
          weekdays: const [DateTime.monday],
          startTime: '08:30',
          endTime: '16:30',
          confidence: StructuredScheduleConfidence.high,
        ),
      ],
    );
  }
}

Matcher _code(String code) => isA<StructuredScheduleImportException>().having(
      (error) => error.code,
      'code',
      code,
    );
