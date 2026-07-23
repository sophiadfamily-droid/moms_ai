import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Life Context production files stay platform and transport independent',
      () {
    final root = _repositoryRoot();
    final directories = [
      Directory('${root.path}/lib/models/life_context'),
      Directory('${root.path}/lib/services/life_context'),
    ];
    final forbiddenImports = RegExp(
      r'''^import\s+['"](?:package:flutter|package:firebase|package:cloud_firestore|dart:io|dart:html|package:http)''',
      multiLine: true,
    );

    final files = directories
        .expand((directory) => directory.listSync())
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();

    expect(files, isNotEmpty);
    for (final file in files) {
      expect(
        forbiddenImports.hasMatch(file.readAsStringSync()),
        isFalse,
        reason: '${file.path} must remain independent of platform services',
      );
    }
  });

  test('canonical multi-domain construction has one read-only boundary', () {
    final root = _repositoryRoot();
    final productionFiles = Directory('${root.path}/lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();
    final canonicalBuilders = productionFiles
        .where(
          (file) => file
              .readAsStringSync()
              .contains('Future<LifeContextSnapshot> buildCanonicalSnapshot'),
        )
        .toList();
    expect(
      canonicalBuilders.map((file) => file.path),
      hasLength(1),
    );
    expect(
      canonicalBuilders.single.path,
      endsWith('services/life_context/life_context_engine.dart'),
    );

    final adapterSource = File(
      '${root.path}/lib/services/life_context/'
      'life_context_domain_adapters.dart',
    ).readAsStringSync();
    for (final forbidden in [
      'FirebaseFirestore',
      'SharedPreferences',
      'OpenAI',
      'saveCanonical',
      'saveEvents',
      'saveTasks',
      'addEvent',
      'addTask',
      'deleteEvent',
      'updateEvents',
      'updateTasks',
    ]) {
      expect(
        adapterSource,
        isNot(contains(forbidden)),
        reason: 'Life Context adapters must not write through $forbidden',
      );
    }
  });

  test('screens and domain models do not orchestrate canonical Life Context',
      () {
    final root = _repositoryRoot();
    final chat =
        File('${root.path}/lib/screens/chat_screen.dart').readAsStringSync();
    expect(chat, isNot(contains('LifeContextProductionFactory')));
    expect(chat, isNot(contains('LifeContextDomainAdapter')));
    expect(chat, isNot(contains('HumanModelService')));
    expect(chat, isNot(contains('TaskService.getTasks')));
    expect(chat, isNot(contains('EventService.getEvents')));

    for (final directory in [
      Directory('${root.path}/lib/models/human'),
      Directory('${root.path}/lib/models'),
    ]) {
      for (final file in directory
          .listSync(recursive: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))) {
        expect(
          file.readAsStringSync(),
          isNot(contains("services/life_context")),
          reason: '${file.path} must not depend on Life Context',
        );
      }
    }
  });

  test('canonical snapshot is not persisted or sent to the backend', () {
    final root = _repositoryRoot();
    final production = Directory('${root.path}/lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in production) {
      final source = file.readAsStringSync();
      if (file.path.endsWith('life_context_snapshot.dart') ||
          file.path.endsWith('life_context_engine.dart')) {
        continue;
      }
      expect(
        source,
        isNot(contains('buildCanonicalSnapshot(')),
        reason: '${file.path} must not create a parallel canonical consumer',
      );
    }
    final request = File('${root.path}/lib/models/chat_backend_request.dart')
        .readAsStringSync();
    expect(request, isNot(contains('LifeContextSnapshot')));
  });
}

Directory _repositoryRoot() {
  var directory = Directory.current.absolute;
  while (true) {
    if (File('${directory.path}/pubspec.yaml').existsSync() &&
        Directory('${directory.path}/lib').existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('Could not locate repository root');
    }
    directory = parent;
  }
}
