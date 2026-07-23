import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/life_context/memory_context.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/models/memory_lifecycle.dart';
import 'package:moms_ai/models/memory_policy.dart';
import 'package:moms_ai/models/life_context/life_context_domains.dart';
import 'package:moms_ai/models/life_context/life_context_graph.dart';
import 'package:moms_ai/models/life_context/life_context_projection.dart';
import 'package:moms_ai/services/conversation_context_service.dart';
import 'package:moms_ai/services/memory_lifecycle_repository.dart';

void main() {
  test('builds schema 2 request from one LC.3 conversation projection',
      () async {
    final provider = DefaultConversationContextProvider(
      loadAccountScope: () async => 'account-test',
      loadProjection: (_) async => _projection(),
    );

    final request = await provider.buildRequest(
      message: 'Planifie un créneau lundi dans mon agenda',
      profile: _profile(),
    );

    expect(request.schemaVersion, 2);
    expect(request.context!.state.name, 'complete');
    expect(request.toJson()['conversationContext'], isNotEmpty);
    expect(request.profile, isEmpty);
    expect(request.memories, isEmpty);
    expect(request.memoryReasoning, isEmpty);
  });

  test('conversation boundary serializes no profile or account scope',
      () async {
    final provider = DefaultConversationContextProvider(
      loadAccountScope: () async => 'account-test',
      loadProjection: (_) async => _projection(),
    );

    final request = await provider.buildRequest(
      message: 'Bonjour',
      profile: _profile(profilePhotoPath: '/local/private.jpg'),
    );

    final serialized = request.toJson().toString();
    expect(serialized, isNot(contains('/local/private.jpg')));
    expect(serialized, isNot(contains('account-test')));
  });

  test('projection account mismatch becomes explicit unavailable state',
      () async {
    final provider = DefaultConversationContextProvider(
      loadAccountScope: () async => 'other-account',
      loadProjection: (_) async => _projection(),
    );

    final request = await provider.buildRequest(
      message: 'Planifie ma journée de lundi',
      profile: _profile(),
    );

    expect(request.context!.state.name, 'accountMismatch');
    expect(request.context!.sections, isEmpty);
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

LifeContextProjection _projection() => LifeContextProjection(
      projectionId: 'projection-1',
      sourceSnapshotId: 'snapshot-1',
      accountScopeId: 'account-test',
      purpose: LifeContextConsumerPurpose.conversation,
      generatedAt: DateTime.utc(2026, 7, 23),
      state: LifeContextProjectionState.complete,
      budgetRequested: 245,
      budgetUsed: 2,
      sections: [
        LifeContextProjectionSection(
          type: LifeContextProjectionSectionType.human,
          availability: LifeContextAvailability.available,
          freshness: LifeContextFreshness.current,
          items: [
            LifeContextProjectionItem(
              id: 'person-1',
              domain: LifeContextDomain.human,
              type: 'person',
              facts: [
                LifeContextProjectionFact(
                  key: LifeContextProjectionFactKeys.status,
                  value: 'active',
                  sensitivity: LifeContextSensitivityLevel.publicTechnical,
                ),
              ],
              confirmation: LifeContextConfirmation.confirmed,
              freshness: LifeContextFreshness.current,
              provenance: const LifeContextProjectionProvenance(
                sourceDomain: LifeContextDomain.human,
                sourceId: 'person-1',
                sourceSnapshotId: 'snapshot-1',
                sourceKind: LifeContextSourceKind.humanModelLocal,
              ),
            ),
          ],
          budgetLimit: 55,
          budgetUsed: 2,
          omittedCount: 0,
          truncated: false,
        ),
      ],
      omittedCount: 0,
      warningCodes: const [],
    );

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
