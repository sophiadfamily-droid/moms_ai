import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('A.3 has one canonical model and one coordinator', () {
    final modelFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('action_confirmation.dart'));
    final coordinatorFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) =>
            file.path.endsWith('action_confirmation_coordinator.dart'));
    expect(modelFiles, hasLength(1));
    expect(coordinatorFiles, hasLength(1));
  });

  test('ChatScreen and common dialog contain no confirmation policy', () {
    final chat = File('lib/screens/chat_screen.dart').readAsStringSync();
    final dialog =
        File('lib/widgets/action_confirmation_dialog.dart').readAsStringSync();
    expect(chat, isNot(contains('ActionConfirmationCoordinator')));
    expect(chat, isNot(contains('ActionConfirmationRequirementAggregator')));
    expect(dialog, isNot(contains('Repository')));
    expect(dialog, isNot(contains('Service')));
    expect(dialog, isNot(contains('ActionAutonomyPolicyEngine')));
  });

  test('A.3 introduces neither Routine undo nor third-party dispatch', () {
    final coordinator =
        File('lib/services/action_confirmation_coordinator.dart')
            .readAsStringSync();
    expect(coordinator, contains('third_party_confirmation_unsupported'));
    expect(coordinator, isNot(contains('undoRoutine')));
    expect(coordinator, isNot(contains('ThirdPartyService')));
  });
}
