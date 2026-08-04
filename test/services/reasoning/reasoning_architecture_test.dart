import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('V1-RE.1-4 remain a pure read-only reasoning boundary', () {
    final model =
        File('lib/models/reasoning/reasoning_input.dart').readAsStringSync();
    final engine = File('lib/services/reasoning/reasoning_input_engine.dart')
        .readAsStringSync();
    final observationModel =
        File('lib/models/reasoning/reasoning_observation.dart')
            .readAsStringSync();
    final observationEngine =
        File('lib/services/reasoning/reasoning_observation_engine.dart')
            .readAsStringSync();
    final assessmentModel =
        File('lib/models/reasoning/reasoning_assessment.dart')
            .readAsStringSync();
    final assessmentEngine =
        File('lib/services/reasoning/reasoning_assessment_engine.dart')
            .readAsStringSync();
    final resultModel =
        File('lib/models/reasoning/reasoning_result.dart').readAsStringSync();
    final composedEngine =
        File('lib/services/reasoning/reasoning_engine.dart').readAsStringSync();
    final source = '$model\n$engine\n$observationModel\n$observationEngine\n'
        '$assessmentModel\n$assessmentEngine\n$resultModel\n$composedEngine';

    for (final forbidden in <String>[
      'firebase_',
      'EventService',
      'TaskService',
      'ShoppingService',
      'MemoryService',
      'NotificationService',
      'ConflictEngineService',
      'OpenAI',
      'ChatBackendClient',
      '.addEvent(',
      '.addTask(',
      '.addItem(',
      '.confirm(',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(source, isNot(contains('currentInstruction:')));
    expect(source, isNot(contains('messages:')));
    expect(source, isNot(contains('fact.value')));
  });
}
