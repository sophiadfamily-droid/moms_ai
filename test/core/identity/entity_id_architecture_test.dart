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

    for (final file in files) {
      final imports = _importsIn(file.readAsStringSync());

      expect(
        imports,
        everyElement(
          anyOf(
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

  test('models and screens do not use the identity foundation directly', () {
    for (final relativeDirectory in ['lib/models', 'lib/screens']) {
      final directory = Directory('${repositoryRoot.path}/$relativeDirectory');

      for (final file in directory
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))) {
        expect(
          file.readAsStringSync(),
          isNot(contains('core/identity/')),
          reason: '${file.path} must not depend on the identity foundation.',
        );
      }
    }
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
