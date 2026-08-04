import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('V1-T.1 remains a pure non-persisting transition boundary', () {
    final model = File(
      'lib/models/task/task_lifecycle_models.dart',
    ).readAsStringSync();
    final engine = File(
      'lib/services/task/task_lifecycle_engine.dart',
    ).readAsStringSync();
    final source = '$model\n$engine';

    for (final forbidden in <String>[
      'firebase_',
      'SharedPreferences',
      'TaskService',
      'CloudTaskService',
      'AuthService',
      '.addTask(',
      '.saveTasks(',
      '.updateTasks(',
      '.set(',
      '.update(',
      '.delete(',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });
}
