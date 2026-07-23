import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'lib/repositories/human/firestore_human_model_repository.dart',
  ).readAsStringSync();

  test('HumanModel cloud persistence is centralized and transactional', () {
    expect(source, contains('runTransaction'));
    expect(source, contains(".collection('users')"));
    expect(source, contains(".collection('private')"));
    expect(source, contains(".doc(documentName)"));
    expect(source, contains('expectedRevision'));
    expect(source, contains('modelRevision'));
    expect(source, isNot(contains('transaction.delete')));
  });

  test('screens contain no direct HumanModel Firestore access', () {
    for (final file in Directory('lib/screens')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))) {
      final screen = file.readAsStringSync();
      expect(
        screen,
        isNot(contains('humanModel')),
        reason: '${file.path} bypasses the HumanModel service.',
      );
      expect(
        screen,
        isNot(contains('FirestoreHumanModelRepository')),
        reason: '${file.path} accesses HumanModel persistence directly.',
      );
    }
  });
}
