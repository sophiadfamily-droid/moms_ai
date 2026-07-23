import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('application flow uses only the high-level participant Identity seam',
      () {
    final screen = File('lib/screens/chat_screen.dart').readAsStringSync();
    final executor =
        File('lib/services/conversation_legacy_action_executor.dart')
            .readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    expect(screen, isNot(contains('beginIdentityActionBinding')));
    expect(screen, isNot(contains('beginEventParticipantIdentity')));
    expect(executor, contains('beginEventParticipantIdentity'));
    expect(executor, isNot(contains('beginIdentityActionBinding')));
    expect(screen, isNot(contains('FirestoreIdentity')));
    expect(main, isNot(contains('FirestoreIdentity')));
    expect(screen, isNot(contains('FirebaseFirestore')));
  });

  test('EventModel uses only the minimal typed participant Identity link', () {
    final eventModel = File('lib/models/event_model.dart').readAsStringSync();

    expect(eventModel, contains('EventParticipantIdentityLink'));
    expect(eventModel, isNot(contains('PersistedIdentityLink')));
    expect(eventModel, isNot(contains('LifeEntity')));
    expect(eventModel, isNot(contains('IdentityRepository')));
  });
}
