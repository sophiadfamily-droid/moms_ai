import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Firestore Identity repository remains read-only and isolated', () {
    final source = File(
      'lib/repositories/identity/firestore_identity_read_repository.dart',
    ).readAsStringSync();

    for (final forbidden in <String>[
      'firebase_auth',
      'FirebaseAuth',
      'FirebaseFirestore.instance',
      'screens/',
      'conversation_coordinator',
      'event_model',
      'task_model',
      'shopping_item_model',
      'memory',
      'planning',
      'openai',
      '.set(',
      '.update(',
      '.delete(',
      'runTransaction(',
      '.batch(',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test('production composition does not reference Firestore Identity', () {
    for (final path in <String>[
      'lib/main.dart',
      'lib/screens/chat_screen.dart',
      'lib/services/conversation_coordinator.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('FirestoreIdentityReadRepository')));
      expect(source, isNot(contains('firestore_identity_read_repository')));
    }
  });
}
