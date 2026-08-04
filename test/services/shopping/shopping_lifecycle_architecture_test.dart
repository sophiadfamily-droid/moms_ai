import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('V1-SH.1 remains a pure non-persisting item boundary', () {
    final model = File(
      'lib/models/shopping/shopping_lifecycle_models.dart',
    ).readAsStringSync();
    final engine = File(
      'lib/services/shopping/shopping_lifecycle_engine.dart',
    ).readAsStringSync();
    final source = '$model\n$engine';

    for (final forbidden in <String>[
      'firebase_',
      'SharedPreferences',
      'ShoppingService',
      'CloudShoppingService',
      'AuthService',
      '.addItem(',
      '.saveItems(',
      '.updateItems(',
      '.set(',
      '.update(',
      '.delete(',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });
}
