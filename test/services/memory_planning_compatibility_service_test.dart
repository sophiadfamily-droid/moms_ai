import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/services/memory_planning_compatibility_service.dart';

void main() {
  test('le Planning conserve uniquement les routines mémoire legacy', () async {
    final reasoning = await MemoryPlanningCompatibilityService.build(
      profile: _profile(),
      generatedAt: DateTime.utc(2026, 7, 23),
      loadMemories: () async => [
        {
          'id': 'routine-1',
          'text': 'Tous les lundis de 18h à 19h yoga',
          'category': 'routine',
          'source': 'user',
          'confirmationStatus': 'confirmed',
          'lifecycleState': 'active',
        },
        {
          'id': 'preference-1',
          'text': 'Je préfère partir tôt',
          'category': 'preference',
          'source': 'user',
          'confirmationStatus': 'confirmed',
          'lifecycleState': 'active',
        },
        {
          'id': 'routine-chat',
          'text': 'Tous les mardis de 18h à 19h course',
          'normalizedText': 'tous les mardis de 18h à 19h course',
          'category': 'routine',
          'importance': 2,
          'createdAt': DateTime.utc(2026, 7, 1),
          'updatedAt': DateTime.utc(2026, 7, 1),
          'source': 'chat',
        },
      ],
    );

    expect(
      reasoning.where((item) => item['source'] == 'Je préfère partir tôt'),
      isEmpty,
    );
    expect(
      reasoning.where(
        (item) => item['source'] == 'Tous les lundis de 18h à 19h yoga',
      ),
      isNotEmpty,
    );
    expect(
      reasoning.where(
        (item) => item['source'] == 'Tous les mardis de 18h à 19h course',
      ),
      isEmpty,
    );
  });
}

UserProfile _profile() => UserProfile(
      firstName: '',
      familyStatus: '',
      workStatus: '',
      partnerName: '',
      wantsNotifications: false,
      children: const [],
    );
