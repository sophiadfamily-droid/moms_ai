import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/screens/chat_screen.dart';
import 'package:moms_ai/screens/tasks_screen.dart';
import 'package:moms_ai/services/priority/proactive_interaction_registry.dart';

void main() {
  test('Priority 2C stays local and uses the canonical pipeline', () {
    final service = File(
      'lib/services/priority/proactive_priority_service.dart',
    ).readAsStringSync();
    final screen = File('lib/screens/tasks_screen.dart').readAsStringSync();
    final production = File(
      'lib/services/priority/proactive_priority_production.dart',
    ).readAsStringSync();
    final lifeContextProduction = File(
      'lib/services/life_context/life_context_production.dart',
    ).readAsStringSync();

    expect(service, contains('PriorityCandidateAdapter'));
    expect(service, contains('PriorityEngine'));
    expect(service, contains('PrioritySuggestionBuilder'));
    expect(service, isNot(contains('OpenAI')));
    expect(service, isNot(contains('ChatBackend')));
    expect(service, isNot(contains('NotificationService')));
    expect(screen, contains("Key('proactive-priority-card')"));
    expect(screen, isNot(contains('quickSuggestion(tasks)')));
    expect(
      screen,
      contains(
        'widget.proactiveInteractionRegistry'
        '.addListener(_handleInteractionChange)',
      ),
    );
    expect(screen, isNot(contains('Timer.periodic')));
    expect(production, contains('LifeContextProductionFactory.production'));
    expect(production, contains('getCurrentProjection'));
    expect(lifeContextProduction, contains('LifeContextRelationEngine'));
    expect(lifeContextProduction, contains('graph: _graph'));
  });

  test('proactive identifiers never depend on presentation text', () {
    final policy = File(
      'lib/services/priority/proactive_suggestion_policy.dart',
    ).readAsStringSync();

    expect(policy, contains('canonicalKey'));
    expect(policy, contains('materialFingerprint'));
    expect(policy, contains('source.primaryCandidateId'));
    expect(policy, contains('sourceRevision'));
  });

  test('production chat and Tasks accept the identical interaction registry',
      () {
    final registry = ProactiveInteractionRegistry();
    final profile = UserProfile(
      firstName: '',
      familyStatus: '',
      workStatus: '',
      partnerName: '',
      wantsNotifications: false,
      children: const [],
    );
    final chat = ChatScreen(
      profile: profile,
      proactiveInteractionRegistry: registry,
    );
    final tasks = TasksScreen(proactiveInteractionRegistry: registry);

    expect(
      identical(
        chat.proactiveInteractionRegistry,
        tasks.proactiveInteractionRegistry,
      ),
      isTrue,
    );

    final navigation =
        File('lib/screens/main_navigation.dart').readAsStringSync();
    expect(
      navigation,
      contains('proactiveInteractionRegistry: _proactiveInteractionRegistry'),
    );
  });
}
