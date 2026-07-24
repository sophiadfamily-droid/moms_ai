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
      'package:openai',
      'openai_service',
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
          file.path.endsWith('life_context_engine.dart') ||
          file.path.endsWith('conversation_context_service.dart') ||
          // N.2 is an explicit read-only canonical consumer. It adapts one
          // validated snapshot and never persists or sends it.
          file.path.endsWith('proactive_detection_production.dart')) {
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

  test('LC.2 is a pure snapshot-only, bounded, closed-rule projection', () {
    final relationEngine =
        File('lib/services/life_context/life_context_relation_engine.dart')
            .readAsStringSync();
    final graphModel = File('lib/models/life_context/life_context_graph.dart')
        .readAsStringSync();

    for (final forbidden in [
      'cloud_firestore',
      'firebase',
      'SharedPreferences',
      'package:openai',
      'openai_service',
      'EventService',
      'TaskService',
      'HumanModelService',
      'Repository',
      'ChatScreen',
      'write(',
      'save(',
      'delete(',
      'set(',
      'update(',
    ]) {
      expect(
        relationEngine,
        isNot(contains(forbidden)),
        reason: 'LC.2 contains forbidden dependency $forbidden.',
      );
    }
    expect(
      relationEngine,
      contains('LifeContextGraph build(LifeContextSnapshot snapshot)'),
    );
    expect(relationEngine, contains('maxDepth'));
    expect(relationEngine, contains('maxVisitedNodes'));
    expect(relationEngine, contains('LifeContextDerivationRules.require'));
    expect(graphModel, isNot(contains('title')));
    expect(graphModel, isNot(contains('displayName')));
    expect(graphModel, isNot(contains('medical')));
    expect(graphModel, isNot(contains('address')));
  });

  test('LC.2 has one canonical builder and is not persisted or sent to UI', () {
    final productionFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();
    final builders = productionFiles.where(
      (file) => file.readAsStringSync().contains(
            'LifeContextGraph build(LifeContextSnapshot snapshot)',
          ),
    );
    expect(builders, hasLength(1));

    for (final file in productionFiles.where(
      (file) =>
          file.path.contains('/screens/') ||
          file.path.contains('/repositories/') ||
          file.path.contains('chat_backend'),
    )) {
      expect(
        file.readAsStringSync(),
        isNot(contains('LifeContextRelationEngine')),
        reason: '${file.path} must not construct or persist LC.2.',
      );
    }
  });

  test('LC.3 has one bounded snapshot-and-graph projection boundary', () {
    final productionFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();
    final builders = productionFiles.where(
      (file) => file.readAsStringSync().contains(
            'LifeContextProjection build({',
          ),
    );
    expect(builders, hasLength(1));
    expect(
      builders.single.path,
      endsWith(
        'services/life_context/life_context_projection_engine.dart',
      ),
    );

    final projectionEngine = builders.single.readAsStringSync();
    for (final forbidden in [
      'cloud_firestore',
      'firebase',
      'SharedPreferences',
      'package:openai',
      'openai_service',
      'EventService',
      'TaskService',
      'HumanModelService',
      'Repository',
      'ChatScreen',
      'write(',
      'save(',
      'delete(',
      'set(',
      'update(',
      'LifeContextSnapshot.toJson',
      'LifeContextGraph.toJson',
      'UserProfile.toJson',
    ]) {
      expect(
        projectionEngine,
        isNot(contains(forbidden)),
        reason: 'LC.3 contains forbidden dependency $forbidden.',
      );
    }
    expect(projectionEngine, contains('required LifeContextSnapshot snapshot'));
    expect(
      projectionEngine,
      contains('required LifeContextConsumerContract contract'),
    );
    expect(projectionEngine, contains('LifeContextGraph? graph'));
    expect(projectionEngine, contains('globalBudget'));
    expect(projectionEngine, contains('sectionBudgets'));
  });

  test('LC.3 contracts are closed, sensitive by default, and not persisted',
      () {
    final projectionModel =
        File('lib/models/life_context/life_context_projection.dart')
            .readAsStringSync();
    final compatibility = File(
      'lib/services/life_context/'
      'life_context_projection_compatibility.dart',
    ).readAsStringSync();

    expect(projectionModel, contains('LifeContextConsumerPurpose'));
    expect(projectionModel, contains('highlySensitive'));
    expect(projectionModel, contains('globalBudget'));
    expect(projectionModel, contains('sectionBudgets'));
    expect(projectionModel, isNot(contains('ConsumerPurpose.custom')));
    expect(projectionModel, isNot(contains('unlimited')));
    expect(compatibility, isNot(contains('snapshot.toJson')));
    expect(compatibility, isNot(contains('graph.toJson')));
    expect(compatibility, isNot(contains('UserProfile')));

    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) =>
            file.path.contains('/repositories/') ||
            file.path.contains('/screens/'))) {
      expect(
        file.readAsStringSync(),
        isNot(contains('LifeContextProjectionEngine')),
        reason: '${file.path} must not construct or persist LC.3.',
      );
    }
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
