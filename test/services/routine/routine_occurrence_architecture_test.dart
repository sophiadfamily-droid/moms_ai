import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('V1-RO.1 is a pure dated projection and never creates Events', () {
    final source = [
      'lib/models/routine/routine_occurrence_models.dart',
      'lib/services/routine/routine_date_applicability_engine.dart',
      'lib/services/routine/routine_occurrence_engine.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');

    for (final forbidden in <String>[
      'firebase_',
      'RoutineRepository',
      'EventService',
      'NotificationService',
      'SharedPreferences',
      '.addEvent(',
      '.createOrVerify(',
      '.schedule(',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });
}
