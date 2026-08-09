import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home refreshes only after the latest detection result', () {
    final notifications =
        File('lib/services/notification_service.dart').readAsStringSync();
    final home = File('lib/screens/home_screen.dart').readAsStringSync();

    expect(notifications, contains('detectionsVersion.value++'));
    expect(
      home,
      contains('NotificationService.detectionsVersion.addListener'),
    );
    expect(
      home,
      contains('NotificationService.detectionsVersion.removeListener'),
    );
    expect(home, contains('generation != _dashboardLoadGeneration'));
  });
}
