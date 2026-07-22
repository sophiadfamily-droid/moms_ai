import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('structured participant does not activate Identity in production', () {
    final screen = File('lib/screens/chat_screen.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    expect(screen, isNot(contains('beginIdentityActionBinding')));
    expect(screen, isNot(contains('FirestoreIdentity')));
    expect(main, isNot(contains('FirestoreIdentity')));
  });

  test('EventModel remains free of participant and Identity links', () {
    final eventModel = File('lib/models/event_model.dart').readAsStringSync();

    expect(eventModel, isNot(contains('EventParticipant')));
    expect(eventModel, isNot(contains('PersistedIdentityLink')));
    expect(eventModel, isNot(contains('participantIdentity')));
  });
}
