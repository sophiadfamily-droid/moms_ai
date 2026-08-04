import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('V1-PR.1 remains a pure non-persisting correction boundary', () {
    final source = [
      'lib/models/profile/profile_patch_models.dart',
      'lib/services/profile/profile_patch_engine.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');
    for (final forbidden in <String>[
      'firebase_',
      'CloudProfileService',
      'SharedPreferences',
      'AuthService',
      '.saveProfile(',
      '.updateRevisioned(',
      '.set(',
      '.update(',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });
}
