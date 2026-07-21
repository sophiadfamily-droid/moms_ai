import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/services/conversation_context_service.dart';
import 'package:moms_ai/services/smart_planning_service.dart';

void main() {
  test('builds conversation and planning memory from one typed snapshot',
      () async {
    final source = <String, dynamic>{
      'id': 'routine-1',
      'text': 'Tous les lundis de 09h à 10h, routine personnelle.',
      'normalizedText': 'tous les lundis de 09h à 10h, routine personnelle.',
      'category': 'routine',
      'importance': 3,
      'createdAt': '2026-07-01T08:00:00.000Z',
    };
    final provider = DefaultConversationContextProvider(
      loadMemories: () async => [source],
      loadEvents: () async => [],
    );

    final request = await provider.buildRequest(
      message: 'Planifie un créneau lundi dans mon agenda',
      profile: _profile(),
    );

    expect(request.profileContext['identity'],
        containsPair('firstName', 'Sophia'));
    expect(request.memories.single['text'], source['text']);
    expect(
      request.memoryReasoning.where(
        (item) => item['type'] == 'blocked_period',
      ),
      hasLength(1),
    );
    expect(
      SmartPlanningService.overlapsBlockedReasoning(
        start: DateTime(2026, 7, 20, 9, 15),
        end: DateTime(2026, 7, 20, 9, 30),
        reasoning: request.memoryReasoning,
      ),
      isTrue,
    );
    expect(source['id'], 'routine-1');
  });

  test('conversation boundary excludes photo paths from both profile views',
      () async {
    final provider = DefaultConversationContextProvider(
      loadMemories: () async => [],
      loadEvents: () async => [],
    );

    final request = await provider.buildRequest(
      message: 'Bonjour',
      profile: _profile(profilePhotoPath: '/local/private.jpg'),
    );

    expect(request.profile.toString(), isNot(contains('/local/private.jpg')));
    expect(
      request.profileContext.toString(),
      isNot(contains('/local/private.jpg')),
    );
    expect(request.memories, isEmpty);
  });
}

UserProfile _profile({String profilePhotoPath = ''}) {
  return UserProfile(
    firstName: 'Sophia',
    familyStatus: '',
    workStatus: '',
    partnerName: '',
    wantsNotifications: true,
    children: const [],
    profilePhotoPath: profilePhotoPath,
  );
}
