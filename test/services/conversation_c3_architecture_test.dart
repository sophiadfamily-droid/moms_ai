import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final policy = File(
    'lib/services/conversation_grounding_policy.dart',
  ).readAsStringSync();
  final controller = File(
    'lib/services/conversation_session_controller.dart',
  ).readAsStringSync();
  final chatScreen = File('lib/screens/chat_screen.dart').readAsStringSync();
  final coordinator =
      File('lib/services/conversation_coordinator.dart').readAsStringSync();
  final prompt = File('functions/brain/systemPrompt.js').readAsStringSync();
  final responseContract = File(
    'functions/services/conversationResponseContract.js',
  ).readAsStringSync();

  test('the canonical C.3 policy is pure and unique', () {
    expect(
      policy,
      isNot(anyOf(
        contains('Firebase'),
        contains('OpenAI'),
        contains('Repository'),
        contains('BuildContext'),
        contains('Widget'),
        contains('save('),
        contains('write('),
      )),
    );
    final production = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');
    expect(
      RegExp(r'final class ConversationGroundingPolicy').allMatches(production),
      hasLength(1),
    );
  });

  test('ChatScreen remains passive for grounding and clarification', () {
    expect(
      chatScreen,
      isNot(anyOf(
        contains('ConversationGroundingPolicy'),
        contains('ConversationMissingInformation'),
        contains('ConversationContradiction'),
        contains('ConversationClarification('),
        contains('epistemicState'),
        contains('groundingReferences'),
      )),
    );
  });

  test('guards execute before the coordinator invokes business actions', () {
    final validation = coordinator.indexOf('ConversationGroundingPolicy()');
    final actionLoop =
        coordinator.indexOf('for (final rawAction in response.actions)');
    expect(validation, greaterThanOrEqualTo(0));
    expect(actionLoop, greaterThan(validation));
    expect(responseContract, contains('response_action_incomplete'));
    expect(responseContract, contains('response_grounding_reference_invalid'));
  });

  test('prompt distinguishes absence, stale data and general knowledge', () {
    expect(prompt, contains('Une donnée absente ne signifie jamais'));
    expect(prompt, contains('indisponible'));
    expect(prompt, contains('donnée stale'));
    expect(prompt, contains('generalKnowledge'));
    expect(prompt, contains('claim structuré'));
  });

  test('clarification loops are bounded outside the UI', () {
    expect(policy, contains('maximumTurns = 3'));
    expect(policy, contains('askedCodes'));
    expect(controller, contains('_clarificationLedger'));
    expect(controller, contains('clarificationLimit'));
  });

  test('C.3 introduces no action mode A.1', () {
    for (final source in [policy, controller, responseContract]) {
      expect(source, isNot(contains('suggestionMode')));
      expect(source, isNot(contains('pauseActions')));
      expect(source, isNot(contains('ActionMode')));
    }
  });
}
