import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'selector and mutation application have no UI Firestore or Identity access',
      () {
    for (final path in [
      'lib/services/event_target_selector.dart',
      'lib/services/event_conversation_mutation_service.dart',
    ]) {
      final source = File(path).readAsStringSync();
      for (final forbidden in [
        'cloud_firestore',
        'FirebaseFirestore',
        'screens/',
        'IdentityRepository',
        'IdentityReadRepository',
        'IdentityWriteRepository',
        'participantIdentity:',
      ]) {
        expect(source, isNot(contains(forbidden)), reason: '$path: $forbidden');
      }
    }
  });

  test('ChatScreen contains no event mutation parsing or direct persistence',
      () {
    final source = File('lib/screens/chat_screen.dart').readAsStringSync();
    expect(source, isNot(contains('EventTargetSelector')));
    expect(source, isNot(contains('EventMutationService')));
    expect(source, isNot(contains('EventMutationRequest')));
    expect(source, isNot(contains('CloudEventService')));
  });

  test('backend mutation contract exposes no event or Identity identifier', () {
    final source = File(
      'functions/brain/zeliaResponseJsonSchema.js',
    ).readAsStringSync();
    final mutationStart = source.indexOf('const eventMutationTargetSchema');
    final mutationEnd = source.indexOf('const actionSchema');
    final mutationContract = source.substring(mutationStart, mutationEnd);
    expect(mutationContract, isNot(contains('entityId')));
    expect(mutationContract, isNot(contains('eventId')));
    expect(mutationContract, isNot(contains('participantIdentity')));
  });
}
