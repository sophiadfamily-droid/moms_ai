import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production Dart files do not print raw errors or stack traces', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final violations = <String>[];
    for (final file in files) {
      final source = file.readAsStringSync();
      if (file.path.endsWith('app_diagnostics.dart')) continue;
      if (RegExp(r'\b(?:print|debugPrint)\s*\(').hasMatch(source) ||
          RegExp(r'\$(?:error|stackTrace)\b').hasMatch(source) ||
          source.contains('error.toString()')) {
        violations.add(file.path);
      }
    }
    expect(violations, isEmpty);
  });

  test('chat UI does not interpolate unknown failures', () {
    final source = File('lib/screens/chat_screen.dart').readAsStringSync();
    expect(RegExp(r'\$(?:e|error)(?![A-Za-z])').hasMatch(source), isFalse);
    expect(source, isNot(contains('error.toString()')));
  });
}
