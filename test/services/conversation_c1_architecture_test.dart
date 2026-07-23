import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ChatScreen is a passive presentation and intent layer', () {
    final source = File('lib/screens/chat_screen.dart').readAsStringSync();
    for (final forbidden in [
      'FirebaseFunctions',
      'httpsCallable',
      'ConversationContextService',
      'ChatBackendRequest(',
      'jsonDecode',
      'MemoryService',
      'EventService',
      'TaskService',
      'ShoppingService',
      'RoutineService',
      'StorageService',
      'HumanModelService',
      'LifeContextEngine',
      'LifeContextProjectionEngine',
      'ActionHandlerService',
      'ConversationCoordinator(',
      'SmartPlanningService',
      'pendingSmartPlanning',
      'pendingPlanningProposal',
      'Map<String, dynamic>? pending',
      'buildRequest(',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(source, contains('SubmitConversationText'));
  });

  test('orchestrator contains no widget, navigation or domain repository', () {
    final source = File('lib/services/conversation_session_controller.dart')
        .readAsStringSync();
    for (final forbidden in [
      'BuildContext',
      'Widget',
      'Navigator',
      'showDialog',
      'showModalBottomSheet',
      'FirebaseFunctions',
      'httpsCallable',
      'OpenAI',
      'EventService',
      'TaskService',
      'ShoppingService',
      'RoutineService',
      'Repository',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(source, contains('_isCurrent(requestId, generation)'));
    expect(source, contains('maximumBackendRetries'));
  });

  test('one canonical session orchestrator exists', () {
    final definitions = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where(
          (file) => file
              .readAsStringSync()
              .contains('final class ConversationSessionController'),
        );
    expect(definitions, hasLength(1));
  });

  test('Smart Planning continuation boundary is typed and unique', () {
    final model =
        File('lib/models/smart_planning_continuation.dart').readAsStringSync();
    final coordinator = File(
      'lib/services/smart_planning_continuation_coordinator.dart',
    ).readAsStringSync();
    expect(model, contains('sessionGeneration'));
    expect(model, contains('UnmodifiableListView'));
    expect(model, isNot(contains('Map<String, dynamic>?')));
    expect(coordinator, isNot(contains('BuildContext')));
    expect(coordinator, isNot(contains('Widget')));
    expect(coordinator, contains('SmartPlanningContinuationCoordinator'));

    final definitions = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where(
          (file) => file
              .readAsStringSync()
              .contains('final class SmartPlanningContinuationCoordinator'),
        );
    expect(definitions, hasLength(1));
  });
}
