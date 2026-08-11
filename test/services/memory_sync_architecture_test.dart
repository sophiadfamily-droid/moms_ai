import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  test('cloud writes are revisioned, transactional and idempotent', () {
    final source = read('lib/services/memory_sync_cloud_repository.dart');
    expect(source, contains('runTransaction'));
    expect(source, contains('expectedRevision'));
    expect(source, contains('memoryRevision != expectedRevision + 1'));
    expect(source, contains('lastMutationId'));
    expect(source, contains('FieldValue.serverTimestamp()'));
    expect(source, isNot(contains('SetOptions(merge: true)')));
  });

  test('offline storage and retry policies are explicitly bounded', () {
    final local = read('lib/services/memory_sync_local_repository.dart');
    final sync = read('lib/services/memory_sync_service.dart');
    expect(local, contains('maxMutations = 50'));
    expect(local, contains('maxConflicts = 25'));
    expect(local, contains('maxReceipts = 100'));
    expect(sync, contains('maxAttempts = 5'));
    expect(sync, contains('maximumBootstrapItems = 500'));
    expect(sync, isNot(contains('while (true)')));
  });

  test('sync layer is independent from UI, OpenAI and structured domains', () {
    final files = [
      'lib/models/memory_sync.dart',
      'lib/services/memory_sync_local_repository.dart',
      'lib/services/memory_sync_cloud_repository.dart',
      'lib/services/memory_sync_service.dart',
    ].map(read).join('\n');
    expect(files, isNot(contains('ChatScreen')));
    expect(files, isNot(contains('OpenAI')));
    expect(files, isNot(contains('EventService')));
    expect(files, isNot(contains('HumanModelService')));
    expect(files, isNot(contains('TaskService')));
    expect(files, isNot(contains('RoutineService')));
    expect(files, isNot(contains('similarity')));
  });

  test('conversation and planning never consume queue or conflicts', () {
    final chat = read('lib/screens/chat_screen.dart');
    final projection =
        read('lib/services/life_context/life_context_projection_engine.dart');
    expect(chat, isNot(contains('MemorySync')));
    expect(chat, isNot(contains('MemorySyncLocalRepository')));
    expect(projection, contains('LifeContextConsumerPurpose.planning'));
    expect(projection, contains('LifeContextDomain.memory'));
  });

  test('rules prohibit deletion and enforce exact revision increments', () {
    final rules = read('firestore.rules');
    expect(
        rules, contains('policyRevision == resource.data.policyRevision + 1'));
    expect(
        rules, contains('memoryRevision == resource.data.memoryRevision + 1'));
    expect(
      RegExp(r'match /memories/\{memoryId\}[\s\S]*?allow delete: if false;')
          .hasMatch(rules),
      isTrue,
    );
  });

  test('rules accept the semantic evidence written with memory proposals', () {
    final rules = read('firestore.rules');
    final serializer = read('lib/services/memory_lifecycle_repository.dart');
    const proposalFields = <String>[
      'evidenceClassification',
      'evidenceSubjectType',
      'evidenceRisks',
      'isCorrection',
      'subjectEntityId',
      'semanticIdentity',
      'canonicalKey',
      'semanticValue',
      'eligibleForAutomaticContradiction',
    ];

    for (final field in proposalFields) {
      expect(serializer, contains("'$field'"), reason: field);
      expect(rules, contains("'$field'"), reason: field);
    }
  });
}
