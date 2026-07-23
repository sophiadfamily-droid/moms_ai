import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('R.3 stays pure, content agnostic, bounded and non-generative', () {
    final files = [
      'lib/models/priority/priority_explanation_models.dart',
      'lib/services/priority/priority_explanation_registry.dart',
      'lib/services/priority/priority_explanation_engine.dart',
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
      'userprofile',
      'memoryservice',
      'taskservice',
      'eventservice',
      'chatbackendrequest',
      'family',
      'famille',
      'child',
      'enfant',
      'partner',
      'conjoint',
      'mother',
      'father',
      'mère',
      'père',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(source, contains('maximumshorttextlength'));
    expect(source, contains('maximumdetailedlength'));
    expect(source, contains('maximumrankingexplanations'));
  });

  test('registry and explanation engine each have one canonical definition',
      () {
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();
    expect(
      dartFiles.where(
        (file) => file
            .readAsStringSync()
            .contains('abstract final class PriorityExplanationRegistry'),
      ),
      hasLength(1),
    );
    expect(
      dartFiles.where(
        (file) => file
            .readAsStringSync()
            .contains('final class PriorityExplanationEngine'),
      ),
      hasLength(1),
    );
  });

  test('presentation widget does not calculate or load priority data', () {
    final source =
        File('lib/widgets/priority_explanation_panel.dart').readAsStringSync();
    for (final forbidden in [
      'PriorityEngine',
      'PriorityExplanationEngine',
      'Repository',
      'Firebase',
      'SharedPreferences',
      'formulaVersion +',
      'contribution *',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(source, contains('required this.explanation'));
  });
}
