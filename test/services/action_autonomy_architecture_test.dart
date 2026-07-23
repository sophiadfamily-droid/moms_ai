import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the central engine is pure and A.2 is not introduced', () {
    final source = File('lib/services/action_autonomy_policy_engine.dart')
        .readAsStringSync();
    for (final forbidden in [
      'package:flutter',
      'firebase',
      'openai',
      'SharedPreferences',
      'Repository',
      'ledger',
      'undo',
    ]) {
      expect(source, isNot(contains(forbidden)));
    }
  });

  test('ChatScreen has no autonomy matrix or storage policy', () {
    final source = File('lib/screens/chat_screen.dart').readAsStringSync();
    for (final forbidden in [
      'ActionAutonomyPolicyEngine',
      'ActionAutonomyMode',
      'SharedPreferences',
      'action_autonomy_policy',
    ]) {
      expect(source, isNot(contains(forbidden)));
    }
  });

  test('request exposes only the minimal backend policy summary', () {
    final source =
        File('lib/models/chat_backend_request.dart').readAsStringSync();
    expect(source, contains("'autonomyPolicyVersion'"));
    expect(source, contains("'autonomyMode'"));
    expect(source, isNot(contains("'accountScopeId'")));
    expect(source, isNot(contains("'policyRevision'")));
  });

  test('one typed pending model owns bounded application continuation state',
      () {
    final model =
        File('lib/models/action_autonomy_policy.dart').readAsStringSync();
    expect(
        RegExp(r'final class ActionPending\b').allMatches(model), hasLength(1));
    expect(model, contains('policyModeAtCreation'));
    expect(model, contains('policyVersionAtCreation'));
    expect(model, contains('sessionGeneration'));
    expect(model, contains('riskLevel'));
    final pendingSlice = model.substring(
      model.indexOf('sealed class ActionPendingPayload'),
      model.indexOf('final class ActionAutonomyPolicyException'),
    );
    expect(pendingSlice, isNot(contains('Map<String, dynamic>')));
    expect(pendingSlice, isNot(contains('BuildContext')));
    expect(pendingSlice, isNot(contains('callback')));
  });

  test('Smart Planning and Identity carry and revalidate A.1 metadata', () {
    final planningModel =
        File('lib/models/smart_planning_continuation.dart').readAsStringSync();
    for (final field in [
      'policyModeAtCreation',
      'policyVersionAtCreation',
      'actionType',
      'origin',
      'riskLevel',
      'policyState',
      'mutationId',
    ]) {
      expect(planningModel, contains(field));
    }
    final coordinator =
        File('lib/services/conversation_coordinator.dart').readAsStringSync();
    expect(coordinator,
        contains('_authorizeConfirmed(ActionType.createIdentity)'));
    expect(
        coordinator, contains('_authorizeConfirmed(ActionType.linkIdentity)'));
  });
}
