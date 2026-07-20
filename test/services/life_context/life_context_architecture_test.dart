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
