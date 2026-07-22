import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('event mutation boundary stays independent from Identity infrastructure',
      () {
    final source = File(
      'lib/services/event_mutation_service.dart',
    ).readAsStringSync();
    for (final forbidden in [
      'cloud_firestore',
      'FirebaseFirestore',
      'IdentityRepository',
      'IdentityReadRepository',
      'IdentityWriteRepository',
      'screens/',
      'memory',
      'task_model',
      'shopping_item_model',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test('cloud mutations are transactional and rewrites cannot overwrite', () {
    final source = File(
      'lib/services/cloud_event_service.dart',
    ).readAsStringSync();
    expect(source, contains('runTransaction'));
    expect(source, contains('transaction.get(document)'));
    expect(source, contains('transaction.update(document, data)'));
    expect(source, contains('transaction.set(document, data)'));
    expect(source, contains('transaction.delete(document)'));
    expect(source, contains('event_mutation_revision_required'));
    expect(source, contains('event_deletion_precondition_required'));
  });

  test('screens do not access Identity repositories directly', () {
    for (final entity in Directory('lib/screens').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      expect(source, isNot(contains('IdentityReadRepository')),
          reason: entity.path);
      expect(source, isNot(contains('IdentityWriteRepository')),
          reason: entity.path);
      expect(source, isNot(contains('FirestoreIdentity')), reason: entity.path);
    }
  });
}
