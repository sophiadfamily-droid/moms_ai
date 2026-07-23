import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('le moteur de politique reste pur et sans accès infrastructure', () {
    final source =
        File('lib/services/memory_policy_engine.dart').readAsStringSync();
    for (final forbidden in [
      'FirebaseFirestore',
      'SharedPreferences',
      'OpenAI',
      'MemoryService',
      'EventService',
      'TaskService',
      'RoutineService',
      'HumanModelService',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test('ChatScreen ne lit plus directement le repository mémoire', () {
    final source = File('lib/screens/chat_screen.dart').readAsStringSync();
    expect(source, isNot(contains('MemoryService')));
    expect(source, isNot(contains('getMemories')));
    expect(source, isNot(contains('MemoryPlanningCompatibilityService')));
  });

  test('la projection Planning exclut le domaine Memory', () {
    final source = File(
      'lib/models/life_context/life_context_projection.dart',
    ).readAsStringSync();
    final start = source.indexOf('LifeContextConsumerPurpose.planning =>');
    final end = source.indexOf(
      'LifeContextConsumerPurpose.internalTechnical =>',
      start,
    );
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final planningContract = source.substring(start, end);
    expect(
      planningContract,
      isNot(contains('LifeContextProjectionSectionType.memory')),
    );
  });

  test('un seul sérialiseur backend Memory est déclaré', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final declarations = files.map((file) => file.readAsStringSync()).where(
          (source) => source.contains(
            'abstract final class MemoryProjectionBackendSerializer',
          ),
        );
    expect(declarations, hasLength(1));
  });

  test('aucun appel actif ne contourne la politique avec saveMemory', () {
    final callers = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where(
          (file) =>
              !file.path.endsWith('/memory_service.dart') &&
              file.readAsStringSync().contains('MemoryService.saveMemory'),
        );
    expect(callers, isEmpty);
  });
}
