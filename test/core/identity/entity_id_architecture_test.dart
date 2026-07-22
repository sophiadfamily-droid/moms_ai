import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory repositoryRoot;

  setUpAll(() {
    repositoryRoot = _findRepositoryRoot();
  });

  test('identity foundation depends only on Dart, uuid, and itself', () {
    final identityDirectory = Directory(
      '${repositoryRoot.path}/lib/core/identity',
    );
    final files = identityDirectory
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();

    expect(
      File('${identityDirectory.path}/entity_id_generator.dart').existsSync(),
      isTrue,
    );
    expect(
      File(
        '${identityDirectory.path}/uuid_v7_entity_id_generator.dart',
      ).existsSync(),
      isTrue,
    );
    expect(
      File('${identityDirectory.path}/entity_identity.dart').existsSync(),
      isTrue,
    );
    expect(
      File('${identityDirectory.path}/entity_matcher.dart').existsSync(),
      isTrue,
    );
    for (final domainFile in [
      'entity_types.dart',
      'life_entity.dart',
      'entity_alias.dart',
      'entity_reference.dart',
      'entity_candidate.dart',
      'entity_resolution.dart',
      'entity_normalizer.dart',
      'identity_engine.dart',
      'persisted_identity_link.dart',
    ]) {
      expect(
          File('${identityDirectory.path}/$domainFile').existsSync(), isTrue);
    }

    for (final file in files) {
      final imports = _importsIn(file.readAsStringSync());

      expect(
        imports,
        everyElement(
          anyOf(
            startsWith('dart:'),
            startsWith('package:uuid/'),
            startsWith('package:moms_ai/core/identity/'),
            predicate<String>(
              (value) => !value.contains('/') && !value.contains(':'),
              'a same-directory identity import',
            ),
          ),
        ),
        reason: '${file.path} contains a forbidden dependency.',
      );
    }
  });

  test('only approved typed models use core Identity from application code',
      () {
    for (final relativeDirectory in ['lib/models', 'lib/screens']) {
      final directory = Directory('${repositoryRoot.path}/$relativeDirectory');

      for (final file in directory
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))) {
        final usesIdentity = file.readAsStringSync().contains('core/identity/');
        final isConversationModel =
            file.path.endsWith('/lib/models/conversation_models.dart');
        final isEventIdentityLink = file.path
            .endsWith('/lib/models/event_participant_identity_link.dart');
        expect(usesIdentity, isConversationModel || isEventIdentityLink,
            reason: '${file.path} has an unexpected identity dependency.');
      }
    }
  });

  test('identity domain does not introduce a generic base entity', () {
    final identityDirectory = Directory(
      '${repositoryRoot.path}/lib/core/identity',
    );
    final source = identityDirectory
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');

    expect(source, isNot(contains('class BaseEntity')));
    expect(source, isNot(contains('repositories/identity')));
    expect(source, isNot(contains('identity_repository')));
  });

  test('persisted participant Identity link is limited to events', () {
    final eventSource = File(
      '${repositoryRoot.path}/lib/models/event_model.dart',
    ).readAsStringSync();
    expect(eventSource, contains('participantIdentity'));
    expect(eventSource, isNot(contains('LifeEntity')));
    expect(eventSource, isNot(contains('repositories/identity')));
    expect(eventSource, isNot(contains('services/identity')));

    for (final relativePath in [
      'lib/models/task_model.dart',
      'lib/models/shopping_item_model.dart',
    ]) {
      final source =
          File('${repositoryRoot.path}/$relativePath').readAsStringSync();
      expect(source, isNot(contains('PersistedIdentityLink')));
      expect(source, isNot(contains('participantIdentity')));
    }
  });

  test('pure identity repository boundary has no framework imports', () {
    final repositoryDirectory = Directory(
      '${repositoryRoot.path}/lib/repositories/identity',
    );
    final forbidden = [
      'firebase',
      'cloud_firestore',
      'package:flutter',
      'dart:io',
      'openai',
      'screens/',
      'services/',
    ];

    for (final file in repositoryDirectory
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) =>
            !file.path.split('/').last.startsWith('firestore_identity_'))) {
      final source = file.readAsStringSync();
      for (final dependency in forbidden) {
        expect(source, isNot(contains(dependency)),
            reason: '${file.path} contains $dependency.');
      }
    }
  });

  test('active identity-related copy and rules stay generic', () {
    final planningSource = File(
      '${repositoryRoot.path}/lib/services/smart_planning_service.dart',
    ).readAsStringSync();
    final profileSource = File(
      '${repositoryRoot.path}/lib/screens/profile_screen.dart',
    ).readAsStringSync();
    final homeSource = File(
      '${repositoryRoot.path}/lib/screens/home_screen.dart',
    ).readAsStringSync();
    final promptSource = File(
      '${repositoryRoot.path}/functions/brain/identityPrompt.js',
    ).readAsStringSync();

    expect(
      RegExp(r'value\.contains\("[^" ]+"\)').allMatches(planningSource),
      everyElement(
        predicate<RegExpMatch>(
          (match) => !RegExp(r'contains\("[a-z]+name"\)')
              .hasMatch(match.group(0) ?? ''),
          'a semantic category term rather than a fixture placeholder',
        ),
      ),
    );
    expect(profileSource, contains('hint: "Ex : Prénom"'));
    expect(homeSource, contains('return "toi";'));
    expect(promptSource, contains('développée par son équipe produit'));
  });
}

Iterable<String> _importsIn(String source) sync* {
  final importPattern = RegExp(
    r'''^\s*import\s+['"]([^'"]+)['"]\s*;''',
    multiLine: true,
  );

  for (final match in importPattern.allMatches(source)) {
    yield match.group(1)!;
  }
}

Directory _findRepositoryRoot() {
  final candidates = <Directory>[
    Directory.current.absolute,
    File.fromUri(Platform.script).parent.absolute,
  ];

  for (final candidate in candidates) {
    var current = candidate;

    while (current.parent.path != current.path) {
      if (File('${current.path}/pubspec.yaml').existsSync() &&
          Directory('${current.path}/lib').existsSync()) {
        return current;
      }
      current = current.parent;
    }
  }

  throw StateError('Unable to locate the repository root.');
}
