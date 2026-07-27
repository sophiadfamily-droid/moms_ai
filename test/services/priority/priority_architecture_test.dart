import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('R.1 is pure, centralized, bounded and content agnostic', () {
    final engine =
        File('lib/services/priority/priority_engine.dart').readAsStringSync();
    final adapter =
        File('lib/services/priority/priority_candidate_adapter.dart')
            .readAsStringSync();
    final formula =
        File('lib/services/priority/priority_formula.dart').readAsStringSync();
    final combined = '$engine\n$adapter\n$formula'.toLowerCase();

    for (final forbidden in [
      'firebase',
      'sharedpreferences',
      'openai',
      'memoryservice',
      'humanmodelservice',
      'title',
      'notes',
      'keyword',
      'family',
      'famille',
      'child',
      'enfant',
      'partner',
      'conjoint',
      'mother',
      'father',
      'workkeywords',
      'healthkeywords',
    ]) {
      expect(combined, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(formula, contains('maximumRankingSize'));
    expect(formula, contains('maximumDirectImpacts'));
    expect(engine, contains('impact.depth != 1'));
    expect(engine, contains('required DateTime evaluatedAt'));
    expect(engine, isNot(contains('sourceDomain.index')));
    expect(formula, contains('domainTieBreakOrderV2'));
    expect(combined, isNot(contains("import '../task_service.dart'")));
    expect(combined, isNot(contains("import '../event_service.dart'")));
    expect(combined, isNot(contains("import '../memory_service.dart'")));
  });

  test('formula weights exist in one canonical file', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => file.readAsStringSync().contains(
              'Map<PriorityDimension, double> weights',
            ))
        .toList();
    expect(files.map((file) => file.path), [
      endsWith('lib/services/priority/priority_formula.dart'),
    ]);
  });

  test('R.4 suggestion projection is read-only and has no delivery boundary',
      () {
    final builder =
        File('lib/services/priority/priority_suggestion_builder.dart')
            .readAsStringSync()
            .toLowerCase();
    final conversation = File(
      'lib/services/priority/priority_suggestion_conversation_context.dart',
    ).readAsStringSync().toLowerCase();
    final combined = '$builder\n$conversation';
    for (final forbidden in [
      'firebase',
      'firestore',
      'sharedpreferences',
      'notificationservice',
      'localnotificationscheduler',
      'planningservice',
      'eventservice',
      'taskservice',
      'routineservice',
      'chatbackendclient',
      'openai',
    ]) {
      expect(combined, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(builder, contains('maximumsuggestions'));
    expect(builder, contains('required datetime referencedate'));
    expect(conversation, contains('local read-only presentation boundary'));
  });
}
