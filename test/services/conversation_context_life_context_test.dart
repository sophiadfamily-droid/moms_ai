import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/life_context/memory_context.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/models/memory_lifecycle.dart';
import 'package:moms_ai/models/memory_lifecycle_state.dart';
import 'package:moms_ai/models/memory_policy.dart';
import 'package:moms_ai/models/memory_evidence.dart';
import 'package:moms_ai/models/memory_semantic_identity.dart';
import 'package:moms_ai/models/life_context/life_context_domains.dart';
import 'package:moms_ai/models/life_context/life_context_graph.dart';
import 'package:moms_ai/models/life_context/life_context_projection.dart';
import 'package:moms_ai/models/life_context/life_context_provenance.dart';
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
    expect(
      request.context!.sections.map((section) => section.type),
      contains('shopping'),
    );
    final shopping = request.context!.sections.singleWhere(
      (section) => section.type == 'shopping',
    );
    final shoppingFacts = shopping.items.single.facts;
    expect(shoppingFacts['title'], 'Fraises');
    expect(shoppingFacts['createdAt'], '2026-07-23T09:00:00.000Z');
    expect(shoppingFacts['quantity'], '2 barquettes');
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

  for (final command in const [
    'Souviens-toi que je préfère les rendez-vous le matin',
    'Rappelle-toi que je préfère les rendez-vous le matin',
    'Retiens que je préfère les rendez-vous le matin',
    'Mémorise que je préfère les rendez-vous le matin',
    'Garde ça en mémoire : je préfère les rendez-vous le matin',
    'Note bien que je préfère les rendez-vous le matin',
    "N'oublie pas que je préfère les rendez-vous le matin",
    'À partir de maintenant, je préfère les rendez-vous le matin',
    'Dorénavant, je préfère les rendez-vous le matin',
  ]) {
    test('une commande mémoire explicite est son propre accord : $command',
        () async {
      final repository = _FakeLifecycleRepository();
      final provider = DefaultConversationContextProvider(
        memoryLifecycleRepository: repository,
        loadMemoryPolicy: () async => _policyWith(
          MemoryGeneralMode.askEveryTime,
        ),
      );

      final request = await provider.proposeUserMemory(command);

      expect(request, isNull);
      expect(provider.lastMemoryProposalWasActivated, isTrue);
      expect(repository.proposals, hasLength(1));
      expect(
        repository.applied.map((mutation) => mutation.newState.name),
        ['confirmed', 'active'],
      );
      expect(
        repository.applied.every(
          (mutation) => mutation.record.actor == MemoryLifecycleActor.user,
        ),
        isTrue,
      );
      expect(
        repository.proposals.single.evidenceClassification,
        anyOf(
          MemoryEvidenceClassification.directExplicit,
          MemoryEvidenceClassification.correction,
        ),
      );
      expect(repository.proposals.single.semanticIdentity?.domain,
          MemorySemanticDomain.planning);
      expect(repository.proposals.single.semanticIdentity?.attribute,
          MemorySemanticAttribute.preferredAppointmentPeriod);
      expect(repository.proposals.single.semanticValue, 'morning');
    });
  }

  test('une préférence sans commande explicite demande encore un accord',
      () async {
    final repository = _FakeLifecycleRepository();
    final provider = DefaultConversationContextProvider(
      memoryLifecycleRepository: repository,
      loadMemoryPolicy: () async => _policyWith(
        MemoryGeneralMode.askEveryTime,
      ),
    );

    final request = await provider.proposeUserMemory(
      'Je préfère les rendez-vous le matin',
    );

    expect(request, isNotNull);
    expect(provider.lastMemoryProposalWasActivated, isFalse);
    expect(repository.applied, isEmpty);
  });

  test('une commande explicite avec j’aime est activée sans second accord',
      () async {
    final repository = _FakeLifecycleRepository();
    final provider = DefaultConversationContextProvider(
      memoryLifecycleRepository: repository,
      loadMemoryPolicy: () async => _policyWith(
        MemoryGeneralMode.askEveryTime,
      ),
    );

    final request = await provider.proposeUserMemory(
      'Souviens-toi que j’aime préparer mes affaires la veille',
    );

    expect(request, isNull);
    expect(provider.lastMemoryProposalWasActivated, isTrue);
    expect(repository.proposals, hasLength(1));
    expect(
      repository.applied.map((mutation) => mutation.newState.name),
      ['confirmed', 'active'],
    );
  });

  test('une commande explicite utilise un seul enregistrement actif', () async {
    final repository = _DirectLifecycleRepository();
    final provider = DefaultConversationContextProvider(
      memoryLifecycleRepository: repository,
      loadMemoryPolicy: () async => _policyWith(
        MemoryGeneralMode.askEveryTime,
      ),
    );

    final request = await provider.proposeUserMemory(
      'Souviens-toi que j’aime préparer mes affaires la veille',
    );

    expect(request, isNull);
    expect(provider.lastMemoryProposalWasPersistedOrPending, isTrue);
    expect(provider.lastMemoryProposalWasActivated, isTrue);
    expect(repository.directActivations, hasLength(1));
    expect(repository.proposals, isEmpty);
    expect(repository.applied, isEmpty);
    expect(
      repository.directActivations.single.activationMutations
          .map((mutation) => mutation.newState.name),
      ['confirmed', 'active'],
    );
  });

  test('une commande explicite déjà active réussit sans créer de doublon',
      () async {
    final repository = _FakeLifecycleRepository();
    final provider = DefaultConversationContextProvider(
      memoryLifecycleRepository: repository,
      loadMemoryPolicy: () async => _policyWith(
        MemoryGeneralMode.askEveryTime,
      ),
    );
    const command = 'Souviens-toi que j’aime préparer mes affaires la veille';

    expect(await provider.proposeUserMemory(command), isNull);
    final originalProposal = repository.proposals.single;
    repository.candidates.add(
      LifeMemoryFact(
        id: originalProposal.id,
        text: originalProposal.text,
        normalizedText: originalProposal.normalizedText,
        semanticType: originalProposal.semanticType,
        category: originalProposal.category,
        importance: originalProposal.importance,
        sourceType: LifeContextSourceType.memory,
        confirmationStatus: MemoryConfirmationStatus.confirmed,
        sensitivity: originalProposal.sensitivity,
        evidenceType: LifeContextEvidenceType.explicit,
        lifecycleState: MemoryLifecycleState.active,
        lifecycleStateIsExplicit: true,
      ),
    );

    final duplicateRequest = await provider.proposeUserMemory(command);

    expect(duplicateRequest, isNull);
    expect(provider.lastMemoryProposalWasAttempted, isTrue);
    expect(provider.lastMemoryProposalWasPersistedOrPending, isTrue);
    expect(provider.lastMemoryProposalWasActivated, isTrue);
    expect(repository.proposals, hasLength(1));
    expect(repository.applied, hasLength(2));
  });

  test('une commande explicite ambiguë demande encore un accord', () async {
    final repository = _FakeLifecycleRepository();
    final provider = DefaultConversationContextProvider(
      memoryLifecycleRepository: repository,
      loadMemoryPolicy: () async => _policyWith(
        MemoryGeneralMode.askEveryTime,
      ),
    );

    final request = await provider.proposeUserMemory(
      'Souviens-toi que je crois que je préfère les rendez-vous le matin',
    );

    expect(request, isNotNull);
    expect(provider.lastMemoryProposalWasActivated, isFalse);
    expect(repository.applied, isEmpty);
  });

  test('automatic active une préférence ordinaire sans commande mémoire',
      () async {
    final repository = _FakeLifecycleRepository();
    final provider = DefaultConversationContextProvider(
      memoryLifecycleRepository: repository,
      loadMemoryPolicy: () async => _policyWith(
        MemoryGeneralMode.automatic,
      ),
    );

    expect(
      await provider.proposeUserMemory(
        'Je préfère les rendez-vous le matin',
      ),
      isNull,
    );
    expect(repository.proposals, hasLength(1));
    expect(
      repository.applied.map((mutation) => mutation.newState.name),
      ['confirmed', 'active'],
    );
  });

  test('automatic accepte une contrainte négative claire et durable', () async {
    final repository = _FakeLifecycleRepository();
    final provider = DefaultConversationContextProvider(
      memoryLifecycleRepository: repository,
      loadMemoryPolicy: () async => _policyWith(
        MemoryGeneralMode.automatic,
      ),
    );

    await provider.proposeUserMemory(
      'Je ne suis jamais disponible le mardi après 18 h',
    );

    expect(repository.proposals, hasLength(1));
    expect(repository.proposals.single.category, 'constraint');
    expect(repository.proposals.single.evidenceRisks,
        contains(MemoryEvidenceRisk.negation));
    expect(repository.applied, hasLength(2));
  });

  test('automatic garde une préférence ambiguë comme proposition', () async {
    final repository = _FakeLifecycleRepository();
    final provider = DefaultConversationContextProvider(
      memoryLifecycleRepository: repository,
      loadMemoryPolicy: () async => _policyWith(
        MemoryGeneralMode.automatic,
      ),
    );

    final request = await provider.proposeUserMemory(
      'Je crois que je préfère les rendez-vous le matin',
    );

    expect(request, isNotNull);
    expect(repository.proposals, hasLength(1));
    expect(repository.proposals.single.evidenceClassification,
        MemoryEvidenceClassification.ambiguous);
    expect(repository.applied, isEmpty);
  });

  for (final message in const [
    'Il est possible que je préfère les rendez-vous le matin',
    'Je ne crois pas que je préfère les rendez-vous le matin',
  ]) {
    test('automatic garde proposed: $message', () async {
      final repository = _FakeLifecycleRepository();
      final provider = DefaultConversationContextProvider(
        memoryLifecycleRepository: repository,
        loadMemoryPolicy: () async => _policyWith(
          MemoryGeneralMode.automatic,
        ),
      );

      final request = await provider.proposeUserMemory(message);

      expect(request, isNotNull);
      expect(repository.proposals, hasLength(1));
      expect(repository.proposals.single.evidenceClassification,
          isNot(MemoryEvidenceClassification.directExplicit));
      expect(repository.applied, isEmpty);
    });
  }

  test('automatic ne confirme jamais un candidat assistant', () async {
    final repository = _FakeLifecycleRepository();
    final provider = DefaultConversationContextProvider(
      memoryLifecycleRepository: repository,
      loadMemoryPolicy: () async => _policyWith(
        MemoryGeneralMode.automatic,
      ),
    );

    await provider.proposeResponseMemory({
      'text': 'Souviens-toi que je préfère les rendez-vous le matin',
      'category': 'preference',
      'importance': 3,
    });

    expect(repository.proposals, hasLength(1));
    expect(repository.proposals.single.evidenceClassification,
        MemoryEvidenceClassification.unknown);
    expect(repository.applied, isEmpty);
  });

  test('une correction est marquée sans supersession automatique', () async {
    final repository = _FakeLifecycleRepository();
    final provider = DefaultConversationContextProvider(
      memoryLifecycleRepository: repository,
      loadMemoryPolicy: () async => _policyWith(
        MemoryGeneralMode.automatic,
      ),
    );

    await provider.proposeUserMemory(
      'Finalement, je préfère les rendez-vous l’après-midi',
    );

    expect(repository.proposals, hasLength(1));
    expect(repository.proposals.single.isCorrection, isTrue);
    expect(repository.proposals.single.evidenceClassification,
        MemoryEvidenceClassification.correction);
    expect(repository.proposals.single.semanticValue, 'afternoon');
    expect(repository.applied, hasLength(2));
  });

  test('une correction composée ne persiste que la valeur actuelle', () async {
    final repository = _FakeLifecycleRepository();
    final provider = DefaultConversationContextProvider(
      memoryLifecycleRepository: repository,
      loadMemoryPolicy: () async => _policyWith(
        MemoryGeneralMode.automatic,
      ),
    );

    await provider.proposeUserMemory(
      'Avant je préférais le matin, mais maintenant je préfère l’après-midi',
    );

    expect(repository.proposals, hasLength(1));
    expect(repository.proposals.single.text, 'je préfère l’après-midi');
    expect(repository.proposals.single.isCorrection, isTrue);
    expect(repository.proposals.single.evidenceClassification,
        MemoryEvidenceClassification.correction);
    expect(repository.applied, hasLength(2));
  });

  test('une correction composée ambiguë reste proposed', () async {
    final repository = _FakeLifecycleRepository();
    final provider = DefaultConversationContextProvider(
      memoryLifecycleRepository: repository,
      loadMemoryPolicy: () async => _policyWith(
        MemoryGeneralMode.automatic,
      ),
    );

    final request = await provider.proposeUserMemory(
      'Avant je préférais le matin, mais maintenant je crois que je préfère '
      'l’après-midi',
    );

    expect(request, isNotNull);
    expect(repository.proposals.single.text,
        'je crois que je préfère l’après-midi');
    expect(repository.proposals.single.isCorrection, isTrue);
    expect(repository.proposals.single.evidenceClassification,
        MemoryEvidenceClassification.ambiguous);
    expect(repository.applied, isEmpty);
  });

  test('un tiers non résolu reste proposé même en mode automatique', () async {
    final repository = _FakeLifecycleRepository();
    final provider = DefaultConversationContextProvider(
      memoryLifecycleRepository: repository,
      loadMemoryPolicy: () async => _policyWith(
        MemoryGeneralMode.automatic,
      ),
    );

    final request = await provider.proposeUserMemory(
      'Souviens-toi que ma sœur préfère les rendez-vous le matin',
    );

    expect(request, isNotNull);
    expect(repository.proposals.single.evidenceSubjectType,
        MemoryEvidenceSubjectType.unresolvedThirdParty);
    expect(repository.applied, isEmpty);
  });

  test('une commande explicite sur une personne résolue est enregistrée',
      () async {
    final repository = _FakeLifecycleRepository();
    final provider = DefaultConversationContextProvider(
      memoryLifecycleRepository: repository,
      loadMemoryPolicy: () async => _policyWith(
        MemoryGeneralMode.automatic,
      ),
    );

    final request = await provider.proposeUserMemory(
      'Souviens-toi que ma sœur préfère les rendez-vous le matin',
      resolvedSubjectEntityId: 'person-42',
    );

    expect(request, isNull);
    expect(provider.lastMemoryProposalWasActivated, isTrue);
    expect(repository.proposals.single.subjectEntityId, 'person-42');
    expect(repository.proposals.single.evidenceSubjectType,
        MemoryEvidenceSubjectType.structuredEntity);
    expect(
      repository.applied.map((mutation) => mutation.newState),
      [MemoryLifecycleState.confirmed, MemoryLifecycleState.active],
    );
    expect(
      repository.applied.every(
        (mutation) => mutation.record.actor == MemoryLifecycleActor.user,
      ),
      isTrue,
    );
  });

  test('un foyer explicite conserve son scope sans foyer par défaut', () async {
    final repository = _FakeLifecycleRepository();
    final provider = DefaultConversationContextProvider(
      memoryLifecycleRepository: repository,
      loadMemoryPolicy: () async => _policyWith(
        MemoryGeneralMode.automatic,
      ),
    );

    await provider.proposeUserMemory(
      'Souviens-toi que ce foyer préfère les rendez-vous le matin',
      resolvedSubjectEntityId: 'household-b',
      semanticSubjectScope: MemorySemanticSubjectScope.household,
      semanticContextType: MemorySemanticContextType.household,
      semanticContextEntityId: 'calendar-shared',
    );

    expect(repository.proposals, hasLength(1));
    expect(repository.proposals.single.semanticIdentity?.subjectScope,
        MemorySemanticSubjectScope.household);
    expect(repository.proposals.single.semanticIdentity?.subjectFingerprint,
        isNot(contains('household-b')));
    expect(repository.proposals.single.semanticIdentity?.contextType,
        MemorySemanticContextType.household);
    expect(repository.proposals.single.semanticIdentity?.contextFingerprint,
        isNot(contains('calendar-shared')));
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
      budgetUsed: 4,
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
        LifeContextProjectionSection(
          type: LifeContextProjectionSectionType.shopping,
          availability: LifeContextAvailability.available,
          freshness: LifeContextFreshness.current,
          items: [
            LifeContextProjectionItem(
              id: 'shopping-1',
              domain: LifeContextDomain.shopping,
              type: 'shoppingItem',
              facts: [
                LifeContextProjectionFact(
                  key: LifeContextProjectionFactKeys.title,
                  value: 'Fraises',
                  sensitivity: LifeContextSensitivityLevel.publicTechnical,
                ),
                LifeContextProjectionFact(
                  key: LifeContextProjectionFactKeys.urgency,
                  value: '1',
                  sensitivity: LifeContextSensitivityLevel.publicTechnical,
                ),
                LifeContextProjectionFact(
                  key: LifeContextProjectionFactKeys.createdAt,
                  value: '2026-07-23T09:00:00.000Z',
                  sensitivity: LifeContextSensitivityLevel.publicTechnical,
                ),
                LifeContextProjectionFact(
                  key: LifeContextProjectionFactKeys.quantity,
                  value: '2 barquettes',
                  sensitivity: LifeContextSensitivityLevel.ordinaryPersonal,
                ),
              ],
              confirmation: LifeContextConfirmation.confirmed,
              freshness: LifeContextFreshness.current,
              provenance: const LifeContextProjectionProvenance(
                sourceDomain: LifeContextDomain.shopping,
                sourceId: 'shopping-1',
                sourceSnapshotId: 'snapshot-1',
                sourceKind: LifeContextSourceKind.shoppingService,
              ),
            ),
          ],
          budgetLimit: 25,
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
  final List<LifeMemoryFact> candidates = [];

  @override
  Future<String?> allocateProposalId() async => 'proposal-1';

  @override
  Future<List<LifeMemoryFact>> findCandidates(
    MemoryProposal proposal, {
    int limit = 25,
  }) async =>
      candidates.take(limit).toList(growable: false);

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

final class _DirectActivationCall {
  const _DirectActivationCall({
    required this.proposal,
    required this.proposalMutation,
    required this.activationMutations,
  });

  final MemoryProposal proposal;
  final MemoryLifecycleMutation proposalMutation;
  final List<MemoryLifecycleMutation> activationMutations;
}

final class _DirectLifecycleRepository extends _FakeLifecycleRepository
    implements MemoryLifecycleDirectActivationRepository {
  final List<_DirectActivationCall> directActivations = [];

  @override
  Future<void> createActiveMemory(
    MemoryProposal proposal,
    MemoryLifecycleMutation proposalMutation,
    List<MemoryLifecycleMutation> activationMutations,
  ) async {
    directActivations.add(
      _DirectActivationCall(
        proposal: proposal,
        proposalMutation: proposalMutation,
        activationMutations: List.unmodifiable(activationMutations),
      ),
    );
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
