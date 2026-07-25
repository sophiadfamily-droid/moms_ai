import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  test('écrans mémoire ne touchent aucun stockage', () {
    final screens = [
      'lib/screens/memory_library_screen.dart',
      'lib/screens/memory_settings_screen.dart',
    ].map(read).join('\n');
    expect(screens, isNot(contains('FirebaseFirestore')));
    expect(screens, isNot(contains('SharedPreferences')));
    expect(screens, isNot(contains('MemorySyncLocalRepository')));
    expect(screens, isNot(contains('accountScopeId')));
  });

  test('toutes les mutations passent par révision et mutationId', () {
    final service = read('lib/services/memory_library_service.dart');
    final sync = read('lib/services/memory_sync_service.dart');
    expect(service, contains('queueMemoryChange'));
    expect(service, contains('current.memoryRevision + 1'));
    expect(service, contains('_idGenerator.generate()'));
    expect(sync, contains('expectedRevision: current.memoryRevision'));
    expect(sync, contains('updated.lastMutationId != mutationId'));
  });

  test('explication pure sans OpenAI, cascade ou domaine structuré', () {
    final service = read('lib/services/memory_library_service.dart');
    expect(service, isNot(contains('OpenAI')));
    expect(service, isNot(contains('IdentityService')));
    expect(service, isNot(contains('EventService')));
    expect(service, isNot(contains('TaskService')));
    expect(service, isNot(contains('RoutineService')));
    expect(service, isNot(contains('HumanModelService')));
    expect(service, isNot(contains('deleteDoc')));
  });

  test('historique et suppression globale sont bornés', () {
    final model = read('lib/models/memory_sync.dart');
    final service = read('lib/services/memory_library_service.dart');
    expect(model, contains('maxHistoryEntries = 50'));
    expect(service, contains('deleteAllPageSize = 20'));
    expect(service, contains('afterMemoryId'));
    expect(service, isNot(contains('WriteBatch')));
  });

  test('Conversation et Planning ne reçoivent ni tombstone ni mémoire libre',
      () {
    final policy = read('lib/services/memory_consumption_policy.dart');
    final adapter =
        read('lib/services/life_context/life_context_domain_adapters.dart');
    final serializer =
        read('lib/services/life_context/life_context_memory_serializer.dart');
    final projection =
        read('lib/services/life_context/life_context_projection_engine.dart');
    expect(policy, contains('MemoryLifecycleState.active'));
    expect(policy, contains('MemoryConsumptionTrust.modernValid'));
    expect(policy, isNot(contains('AppDiagnostics')));
    expect(policy, isNot(contains('print(')));
    expect(adapter, contains('MemoryConsumptionPolicy.consumable'));
    expect(serializer, contains('MemoryConsumptionPolicy.consumable'));
    expect(projection, contains('LifeContextConsumerPurpose.planning'));
    expect(projection, contains('LifeContextDomain.memory'));
  });
}
