import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('R.2 stays pure, bounded, content agnostic and dependency-only', () {
    final files = [
      'lib/models/priority/priority_propagation_models.dart',
      'lib/services/priority/priority_propagation_formula.dart',
      'lib/services/priority/priority_graph_candidate_adapter.dart',
      'lib/services/priority/priority_propagation_engine.dart',
    ];
    final source = files
        .map((path) => File(path).readAsStringSync())
        .join('\n')
        .toLowerCase();

    for (final forbidden in [
      'firebase',
      'sharedpreferences',
      'openai',
      'repository',
      'title',
      'description',
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
      'health',
      'memoryservice',
      'taskservice',
      'eventservice',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(source, isNot(contains('graph.relations')));
    expect(source, contains('graph.dependencies'));
    expect(source, contains('maximumdepth'));
    expect(source, contains('maximumcontributionpercandidate'));
    expect(source, contains('current.nodepath.contains(prerequisite)'));
  });

  test('propagation formula and engine each have one canonical definition', () {
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();
    final formulas = dartFiles
        .where((file) => file
            .readAsStringSync()
            .contains('abstract final class PriorityPropagationFormula'))
        .toList();
    final engines = dartFiles
        .where((file) => file
            .readAsStringSync()
            .contains('final class PriorityPropagationEngine'))
        .toList();
    expect(formulas, hasLength(1));
    expect(engines, hasLength(1));
  });
}
