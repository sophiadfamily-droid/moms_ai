import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Task Shopping and Profile cloud writes require revisions', () {
    final task =
        File('lib/services/cloud_task_service.dart').readAsStringSync();
    final shopping =
        File('lib/services/cloud_shopping_service.dart').readAsStringSync();
    final profile =
        File('lib/services/cloud_profile_service.dart').readAsStringSync();

    for (final source in [task, shopping, profile]) {
      expect(source, contains('runTransaction'));
      expect(source, contains('lastMutationId'));
      expect(source, contains('revisionConflict'));
      expect(source, isNot(contains('SetOptions(merge: true)')));
    }
    expect(task, contains('expectedRevision'));
    expect(shopping, contains('expectedRevision'));
    expect(profile, contains('expectedRevision'));
    expect(task, isNot(contains('batch.delete')));
    expect(shopping, isNot(contains('batch.delete')));
  });

  test('journals and retries are centrally bounded and account scoped', () {
    final journal = File(
      'lib/services/revisioned_offline_journal.dart',
    ).readAsStringSync();
    final service = File(
      'lib/services/revisioned_domain_sync_service.dart',
    ).readAsStringSync();

    expect(journal, contains('maxMutations = 200'));
    expect(journal, contains('maxReceipts = 200'));
    expect(journal, contains('maxConflicts = 100'));
    expect(journal, contains('maxAttempts = 5'));
    expect(journal, contains('accountScopeId'));
    expect(service, contains('RevisionedActionRetryGuard'));
    expect(service, contains('mutation.attempt + 1'));
  });

  test('Profile refuses HumanModel canonical ownership', () {
    final models =
        File('lib/models/revisioned_domain_models.dart').readAsStringSync();
    expect(models, contains('ProfileFieldOwnership'));
    expect(models, contains('profile_canonical_ownership_conflict'));
    expect(models, contains('ownedPayload'));
    expect(models, contains("'children'"));
  });

  test('screens own no Y.1 repositories, journal, or conflict engine', () {
    for (final entity in Directory('lib/screens').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final forbidden in [
        'RevisionedDomainLocalRepository',
        'RevisionedOfflineJournal',
        'RevisionedTaskCloudRepository',
        'RevisionedShoppingCloudRepository',
        'RevisionedProfileCloudRepository',
        'RevisionedConflictResolution',
      ]) {
        expect(source, isNot(contains(forbidden)), reason: entity.path);
      }
    }
  });

  test('Y.1 creates neither ledger nor undo infrastructure', () {
    final paths = [
      'lib/models/revisioned_sync_protocol.dart',
      'lib/models/revisioned_domain_models.dart',
      'lib/services/revisioned_domain_sync_service.dart',
      'lib/services/revisioned_offline_journal.dart',
    ];
    for (final path in paths) {
      final source = File(path).readAsStringSync().toLowerCase();
      expect(source, isNot(contains('actionledger')), reason: path);
      expect(source, isNot(contains('undoservice')), reason: path);
      expect(source, isNot(contains('replayservice')), reason: path);
    }
  });

  test('Firestore rules reject physical deletion and exact increments', () {
    final rules = File('firestore.rules').readAsStringSync();
    expect(rules, contains('next.revision == previous.revision + 1'));
    expect(
      rules,
      contains(
        'request.resource.data.profileRevision == '
        'resource.data.profileRevision + 1',
      ),
    );
    expect(rules, contains("match /tasks/{taskId}"));
    expect(rules, contains("match /shopping_items/{itemId}"));
    expect(rules, contains('allow delete: if false;'));
    expect(rules, contains('!previous.isTombstone || next.isTombstone'));
  });
}
