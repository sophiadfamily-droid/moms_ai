import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Identity creation orchestration has no direct infrastructure access',
      () {
    final root = _repositoryRoot();
    final service = File(
      '${root.path}/lib/services/identity/identity_creation_service.dart',
    ).readAsStringSync();
    final coordinator = File(
      '${root.path}/lib/services/conversation_coordinator.dart',
    ).readAsStringSync();

    for (final forbidden in const [
      'cloud_firestore',
      'FirebaseFirestore',
      'FirebaseAuth',
      'firestore_identity_write_repository',
      'openai',
      'screens/',
      'event_model',
      'task_model',
      'shopping_item_model',
      'memory_service',
      'planning',
    ]) {
      expect(service, isNot(contains(forbidden)));
    }
    expect(coordinator, isNot(contains('IdentityWriteRepository')));
    expect(coordinator, isNot(contains('FirestoreIdentityWriteRepository')));
  });

  test('Firestore Identity writing remains absent from production roots', () {
    final root = _repositoryRoot();
    for (final path in [
      '${root.path}/lib/main.dart',
      '${root.path}/lib/screens',
    ]) {
      final target =
          FileSystemEntity.typeSync(path) == FileSystemEntityType.file
              ? [File(path)]
              : Directory(path)
                  .listSync(recursive: true)
                  .whereType<File>()
                  .where((file) => file.path.endsWith('.dart'));
      for (final file in target) {
        final source = file.readAsStringSync();
        expect(source, isNot(contains('IdentityWriteRepository')));
        expect(source, isNot(contains('FirestoreIdentityWriteRepository')));
        expect(source, isNot(contains('IdentityCreationService')));
      }
    }
  });
}

Directory _repositoryRoot() {
  var current = Directory.current.absolute;
  while (current.parent.path != current.path) {
    if (File('${current.path}/pubspec.yaml').existsSync()) return current;
    current = current.parent;
  }
  throw StateError('Unable to locate repository root.');
}
