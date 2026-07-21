import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('identity application service has only approved dependencies', () {
    final root = _findRepositoryRoot();
    final directory = Directory('${root.path}/lib/services/identity');
    final files = directory
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    const forbidden = [
      'firebase',
      'cloud_firestore',
      'package:flutter',
      'dart:io',
      'openai',
      'screens/',
      'chat_screen',
      'conversation_coordinator',
      'memory_service',
      'life_context',
      'user_profile',
      'event_model',
      'task_model',
      'shopping_item_model',
    ];

    expect(files, isNotEmpty);
    for (final file in files) {
      final source = file.readAsStringSync();
      for (final dependency in forbidden) {
        expect(
          source,
          isNot(contains(dependency)),
          reason: '${file.path} contains $dependency.',
        );
      }
      expect(source, isNot(contains('.save(')));
      expect(source, isNot(contains('.saveAll(')));
    }
  });
}

Directory _findRepositoryRoot() {
  var current = Directory.current.absolute;
  while (current.parent.path != current.path) {
    if (File('${current.path}/pubspec.yaml').existsSync()) return current;
    current = current.parent;
  }
  throw StateError('Unable to locate the repository root.');
}
