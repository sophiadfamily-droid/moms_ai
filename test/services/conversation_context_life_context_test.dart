import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/life_context/memory_context.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/models/memory_lifecycle.dart';
import 'package:moms_ai/models/memory_policy.dart';
import 'package:moms_ai/services/conversation_context_service.dart';
import 'package:moms_ai/services/memory_lifecycle_repository.dart';
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

    expect(
        request.profileContext['identity'], containsPair('firstName', 'User'));
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

  test('explicit non-active proposal is excluded from chat context', () async {
    final provider = DefaultConversationContextProvider(
      loadMemories: () async => [
        {
          'id': 'proposal-1',
          'text': 'Routine proposée le lundi',
          'category': 'routine',
          'importance': 3,
          'lifecycleState': 'proposed',
        },
      ],
      loadEvents: () async => [],
    );

    final request = await provider.buildRequest(
      message: 'Planifie ma journée de lundi',
      profile: _profile(),
    );

    expect(request.memories, isEmpty);
    expect(request.memoryReasoning, isEmpty);
  });

  test('assistant memory output is persisted only as a proposal', () async {
    final repository = _FakeLifecycleRepository();
    final provider = DefaultConversationContextProvider(
      loadMemories: () async => [],
      loadEvents: () async => [],
      memoryLifecycleRepository: repository,
      loadMemoryPolicy: _policy,
    );

    await provider.saveResponseMemory({
      'text': 'Souviens-toi que je préfère les rendez-vous le matin',
      'category': 'preference',
      'importance': 3,
    });

    expect(repository.proposals, hasLength(1));
    expect(repository.proposals.single.id, 'proposal-1');
    expect(repository.mutations.single.newState.name, 'proposed');
    expect(repository.proposals.single.confirmationRequired, isTrue);
  });

  test('memory persistence failure does not break the conversation flow',
      () async {
    final provider = DefaultConversationContextProvider(
      loadMemories: () async => [],
      loadEvents: () async => [],
      memoryLifecycleRepository: _FailingLifecycleRepository(),
      loadMemoryPolicy: _policy,
    );

    await expectLater(
      provider.saveResponseMemory({
        'text': 'Souviens-toi que je préfère le matin',
        'category': 'preference',
        'importance': 3,
      }),
      completes,
    );
  });

  test('pause bloque toute proposition sans effacer les souvenirs', () async {
    final repository = _FakeLifecycleRepository();
    final provider = DefaultConversationContextProvider(
      memoryLifecycleRepository: repository,
      loadMemoryPolicy: () async => _policyWith(
        MemoryGeneralMode.paused,
      ),
    );
    expect(
      await provider.proposeUserMemory(
        'Souviens-toi que je préfère les rendez-vous le matin',
      ),
      isNull,
    );
    expect(repository.proposals, isEmpty);
  });

  test('automatic active une préférence explicite ordinaire', () async {
    final repository = _FakeLifecycleRepository();
    final provider = DefaultConversationContextProvider(
      memoryLifecycleRepository: repository,
      loadMemoryPolicy: () async => _policyWith(
        MemoryGeneralMode.automatic,
      ),
    );
    expect(
      await provider.proposeUserMemory(
        'Souviens-toi que je préfère les rendez-vous le matin',
      ),
      isNull,
    );
    expect(repository.proposals, hasLength(1));
    expect(
      repository.applied.map((mutation) => mutation.newState.name),
      ['confirmed', 'active'],
    );
  });

  test('automatic général ne mémorise pas la santé désactivée', () async {
    final repository = _FakeLifecycleRepository();
    final provider = DefaultConversationContextProvider(
      memoryLifecycleRepository: repository,
      loadMemoryPolicy: () async => _policyWith(
        MemoryGeneralMode.automatic,
      ),
    );
    expect(
      await provider.proposeUserMemory(
        'Souviens-toi de mon allergie médicale',
      ),
      isNull,
    );
    expect(repository.proposals, isEmpty);
  });
}

Future<MemoryPolicy> _policy() async => MemoryPolicy.restrictiveDefault(
      accountScopeId: 'account-test',
      changedAt: DateTime.utc(2026, 7, 23),
    );

MemoryPolicy _policyWith(
  MemoryGeneralMode mode, {
  MemoryHealthMode health = MemoryHealthMode.disabled,
}) =>
    MemoryPolicy(
      accountScopeId: 'account-test',
      generalMode: mode,
      healthMode: health,
      healthConsentGranted: health == MemoryHealthMode.enabled,
      changedAt: DateTime.utc(2026, 7, 23),
      changeSource: MemoryPolicyChangeSource.explicitUserSetting,
    );

UserProfile _profile({String profilePhotoPath = ''}) {
  return UserProfile(
    firstName: 'User',
    familyStatus: '',
    workStatus: '',
    partnerName: '',
    wantsNotifications: true,
    children: const [],
    profilePhotoPath: profilePhotoPath,
  );
}

final class _FakeLifecycleRepository implements MemoryLifecycleRepository {
  final List<MemoryProposal> proposals = [];
  final List<MemoryLifecycleMutation> mutations = [];
  final List<MemoryLifecycleMutation> applied = [];

  @override
  Future<String?> allocateProposalId() async => 'proposal-1';

  @override
  Future<List<LifeMemoryFact>> findCandidates(
    MemoryProposal proposal, {
    int limit = 25,
  }) async =>
      const [];

  @override
  Future<void> createProposal(
    MemoryProposal proposal,
    MemoryLifecycleMutation mutation,
  ) async {
    proposals.add(proposal);
    mutations.add(mutation);
  }

  @override
  Future<LifeMemoryFact?> getById(String memoryId) async => null;

  @override
  Future<void> applyMutations(List<MemoryLifecycleMutation> mutations) async {
    applied.addAll(mutations);
  }
}

final class _FailingLifecycleRepository implements MemoryLifecycleRepository {
  @override
  Future<String?> allocateProposalId() async => 'proposal-failure';

  @override
  Future<List<LifeMemoryFact>> findCandidates(
    MemoryProposal proposal, {
    int limit = 25,
  }) async =>
      const [];

  @override
  Future<LifeMemoryFact?> getById(String memoryId) async => null;

  @override
  Future<void> applyMutations(List<MemoryLifecycleMutation> mutations) async {
    throw StateError('persistence unavailable');
  }

  @override
  Future<void> createProposal(
    MemoryProposal proposal,
    MemoryLifecycleMutation mutation,
  ) async {
    throw StateError('persistence unavailable');
  }
}
