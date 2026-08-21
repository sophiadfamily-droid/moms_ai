import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/life_context/life_context_provenance.dart';
import 'package:moms_ai/models/life_context/memory_context.dart';
import 'package:moms_ai/models/memory_lifecycle.dart';
import 'package:moms_ai/models/memory_lifecycle_state.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/services/legacy_profile_memory_migration_service.dart';
import 'package:moms_ai/services/memory_lifecycle_repository.dart';

void main() {
  group('LegacyProfileMemoryMigrationService', () {
    const service = LegacyProfileMemoryMigrationService();
    final referenceDate = DateTime.utc(2026, 8, 21, 10);

    test('migre uniquement les préférences habitudes et objectifs sûrs',
        () async {
      final repository = _FakeRepository();
      final result = await service.migrate(
        accountScopeId: 'account-a',
        profile: _profile(
          habits: 'Je prépare mes affaires la veille',
          preferences: 'Je préfère les rendez-vous le matin',
          goals: 'Retrouver un rythme plus calme',
          personalNotes: 'Note privée',
          adminNotes: 'Dossier administratif secret',
          budgetNotes: 'Budget privé',
        ),
        repository: repository,
        referenceDate: referenceDate,
      );

      expect(result.createdCount, 3);
      expect(
          repository.active.values.map((fact) => fact.text),
          containsAll([
            'Je prépare mes affaires la veille',
            'Je préfère les rendez-vous le matin',
            'Retrouver un rythme plus calme',
          ]));
      expect(
        repository.active.values.map((fact) => fact.text).join(' '),
        isNot(contains('privé')),
      );
    });

    test('ne crée pas de doublon quand la migration est rejouée', () async {
      final repository = _FakeRepository();
      final profile = _profile(preferences: 'Je préfère le matin');

      final first = await service.migrate(
        accountScopeId: 'account-a',
        profile: profile,
        repository: repository,
        referenceDate: referenceDate,
      );
      final second = await service.migrate(
        accountScopeId: 'account-a',
        profile: profile,
        repository: repository,
        referenceDate: referenceDate.add(const Duration(minutes: 1)),
      );

      expect(first.createdCount, 1);
      expect(repository.active, hasLength(1));
      expect(
        second.items.singleWhere((item) => item.field == 'preferences').status,
        LegacyProfileMemoryMigrationStatus.duplicate,
      );
    });

    test('signale un conflit sans remplacer une valeur changée', () async {
      final repository = _FakeRepository();
      await service.migrate(
        accountScopeId: 'account-a',
        profile: _profile(preferences: 'Je préfère le matin'),
        repository: repository,
        referenceDate: referenceDate,
      );

      final result = await service.migrate(
        accountScopeId: 'account-a',
        profile: _profile(preferences: 'Je préfère le soir'),
        repository: repository,
        referenceDate: referenceDate.add(const Duration(days: 1)),
      );

      expect(result.conflictCount, 1);
      expect(repository.active, hasLength(1));
      expect(repository.active.values.single.text, 'Je préfère le matin');
    });

    test('isole les identifiants entre deux comptes', () async {
      final firstRepository = _FakeRepository();
      final secondRepository = _FakeRepository();
      final profile = _profile(goals: 'Prendre du temps pour moi');

      await service.migrate(
        accountScopeId: 'account-a',
        profile: profile,
        repository: firstRepository,
        referenceDate: referenceDate,
      );
      await service.migrate(
        accountScopeId: 'account-b',
        profile: profile,
        repository: secondRepository,
        referenceDate: referenceDate,
      );

      expect(
        firstRepository.active.keys.single,
        isNot(secondRepository.active.keys.single),
      );
    });

    test('déduplique deux champs sûrs au contenu identique', () async {
      final repository = _FakeRepository();
      final result = await service.migrate(
        accountScopeId: 'account-a',
        profile: _profile(
          preferences: 'Je mange sans sucre',
          foodPreferences: '  je mange sans sucre  ',
        ),
        repository: repository,
        referenceDate: referenceDate,
      );

      expect(result.createdCount, 1);
      expect(repository.active, hasLength(1));
      expect(
        result.items.last.status,
        LegacyProfileMemoryMigrationStatus.skipped,
      );
    });
  });
}

UserProfile _profile({
  String habits = '',
  String preferences = '',
  String goals = '',
  String personalNotes = '',
  String adminNotes = '',
  String budgetNotes = '',
  String foodPreferences = '',
}) =>
    UserProfile(
      firstName: 'Sophia',
      familyStatus: '',
      workStatus: '',
      partnerName: '',
      wantsNotifications: true,
      children: const [],
      habits: habits,
      preferences: preferences,
      goals: goals,
      personalNotes: personalNotes,
      adminNotes: adminNotes,
      budgetNotes: budgetNotes,
      foodPreferences: foodPreferences,
    );

final class _FakeRepository
    implements
        MemoryLifecycleRepository,
        MemoryLifecycleDirectActivationRepository {
  final Map<String, LifeMemoryFact> active = {};

  @override
  Future<String?> allocateProposalId() async => null;

  @override
  Future<void> applyMutations(List<MemoryLifecycleMutation> mutations) async {}

  @override
  Future<void> createActiveMemory(
    MemoryProposal proposal,
    MemoryLifecycleMutation proposalMutation,
    List<MemoryLifecycleMutation> activationMutations,
  ) async {
    active[proposal.id] = LifeMemoryFact(
      id: proposal.id,
      text: proposal.text,
      normalizedText: proposal.normalizedText,
      semanticType: proposal.semanticType,
      category: proposal.category,
      importance: proposal.importance,
      sourceType: LifeContextSourceType.memory,
      sourceId: proposal.source,
      createdAt: proposal.proposedAt,
      confirmationStatus: MemoryConfirmationStatus.confirmed,
      sensitivity: proposal.sensitivity,
      evidenceType: LifeContextEvidenceType.explicit,
      lifecycleState: MemoryLifecycleState.active,
      lifecycleStateIsExplicit: true,
    );
  }

  @override
  Future<void> createProposal(
    MemoryProposal proposal,
    MemoryLifecycleMutation mutation,
  ) async {}

  @override
  Future<List<LifeMemoryFact>> findCandidates(
    MemoryProposal proposal, {
    int limit = 25,
  }) async =>
      active.values.take(limit).toList(growable: false);

  @override
  Future<LifeMemoryFact?> getById(String memoryId) async => active[memoryId];
}
