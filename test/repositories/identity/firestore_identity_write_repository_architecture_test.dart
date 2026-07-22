import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Firestore write repository is isolated and transaction-only', () {
    final source = File(
      'lib/repositories/identity/firestore_identity_write_repository.dart',
    ).readAsStringSync();
    expect(source, contains('runTransaction'));
    expect(source, contains('transaction.set('));
    for (final forbidden in [
      'FirebaseAuth',
      'firebase_auth',
      'FirebaseFirestore.instance',
      'serverTimestamp',
      'FieldValue',
      '.delete(',
      'mergedIntoEntityId:',
      'screens/',
      'conversation_coordinator',
      'event_model',
      'task_model',
      'shopping_item_model',
      'memory',
      'planning',
      'openai',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test('write repository remains dormant in production composition', () {
    for (final path in [
      'lib/main.dart',
      'lib/screens/chat_screen.dart',
      'lib/services/conversation_coordinator.dart',
      'lib/services/identity/identity_application_service.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('FirestoreIdentityWriteRepository')));
      expect(source, isNot(contains('firestore_identity_write_repository')));
    }
  });
}
