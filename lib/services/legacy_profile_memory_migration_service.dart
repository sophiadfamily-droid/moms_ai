import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/life_context/life_context_provenance.dart';
import '../models/life_context/memory_context.dart';
import '../models/memory_evidence.dart';
import '../models/memory_lifecycle.dart';
import '../models/memory_lifecycle_state.dart';
import '../models/memory_semantic_identity.dart';
import '../models/user_profile.dart';
import 'memory_lifecycle_engine.dart';
import 'memory_lifecycle_repository.dart';
import 'memory_proposal_factory.dart';

enum LegacyProfileMemoryMigrationStatus {
  created,
  duplicate,
  conflict,
  skipped,
}

final class LegacyProfileMemoryMigrationItemResult {
  const LegacyProfileMemoryMigrationItemResult({
    required this.field,
    required this.status,
    this.memoryId,
  });

  final String field;
  final LegacyProfileMemoryMigrationStatus status;
  final String? memoryId;
}

final class LegacyProfileMemoryMigrationResult {
  LegacyProfileMemoryMigrationResult(
      Iterable<LegacyProfileMemoryMigrationItemResult> items)
      : items = List.unmodifiable(items);

  final List<LegacyProfileMemoryMigrationItemResult> items;

  int get createdCount => items
      .where(
          (item) => item.status == LegacyProfileMemoryMigrationStatus.created)
      .length;

  int get conflictCount => items
      .where(
          (item) => item.status == LegacyProfileMemoryMigrationStatus.conflict)
      .length;
}

/// Moves the safe, user-authored free-text fields from the historical profile
/// bridge to the canonical memory lifecycle.
///
/// Personal, administrative and budget notes are intentionally excluded: they
/// need a dedicated privacy contract before they can become conversational
/// memories.
final class LegacyProfileMemoryMigrationService {
  const LegacyProfileMemoryMigrationService({
    MemoryProposalFactory proposalFactory = const MemoryProposalFactory(),
    MemoryLifecycleEngine lifecycleEngine = const MemoryLifecycleEngine(),
  })  : _proposalFactory = proposalFactory,
        _lifecycleEngine = lifecycleEngine;

  final MemoryProposalFactory _proposalFactory;
  final MemoryLifecycleEngine _lifecycleEngine;

  Future<LegacyProfileMemoryMigrationResult> migrate({
    required String accountScopeId,
    required UserProfile profile,
    required MemoryLifecycleRepository repository,
    required DateTime referenceDate,
  }) async {
    if (accountScopeId.trim().isEmpty ||
        repository is! MemoryLifecycleDirectActivationRepository) {
      return LegacyProfileMemoryMigrationResult(const []);
    }
    final directRepository =
        repository as MemoryLifecycleDirectActivationRepository;

    final results = <LegacyProfileMemoryMigrationItemResult>[];
    final seen = <String>{};
    for (final seed in _seeds(profile)) {
      final text = seed.text.trim();
      final normalized = _normalize(text);
      if (normalized.isEmpty || !seen.add('${seed.category}:$normalized')) {
        results.add(
          LegacyProfileMemoryMigrationItemResult(
            field: seed.field,
            status: LegacyProfileMemoryMigrationStatus.skipped,
          ),
        );
        continue;
      }

      final memoryId = _stableMemoryId(accountScopeId, seed.field);
      final proposal = _proposalFactory.fromHistoricalPayload(
        id: memoryId,
        payload: {
          'text': text,
          'category': seed.category,
          'importance': seed.importance,
          'sourceId': 'legacy_profile_migration',
        },
        source: 'legacy_profile_migration',
        proposedAt: referenceDate.toUtc(),
        confirmationRequired: false,
        evidenceQualification: MemoryEvidenceQualification(
          classification: MemoryEvidenceClassification.directExplicit,
          subjectType: MemoryEvidenceSubjectType.user,
          canConfirmImmediately: true,
          isCorrection: false,
          statementForMemory: text,
          reasonCodes: const ['legacy_profile_explicit_field'],
        ),
        semanticSubjectScope: MemorySemanticSubjectScope.authenticatedUser,
      );
      if (proposal == null) {
        results.add(
          LegacyProfileMemoryMigrationItemResult(
            field: seed.field,
            status: LegacyProfileMemoryMigrationStatus.skipped,
          ),
        );
        continue;
      }

      final stableExisting = await repository.getById(memoryId);
      if (stableExisting != null) {
        results.add(
          LegacyProfileMemoryMigrationItemResult(
            field: seed.field,
            status: stableExisting.normalizedText == proposal.normalizedText &&
                    _isUsable(stableExisting)
                ? LegacyProfileMemoryMigrationStatus.duplicate
                : LegacyProfileMemoryMigrationStatus.conflict,
            memoryId: memoryId,
          ),
        );
        continue;
      }

      final candidates = await repository.findCandidates(proposal);
      final decision = _lifecycleEngine.evaluateProposal(
        proposal: proposal,
        existingMemories: candidates,
        referenceDate: referenceDate.toUtc(),
        accountScopeId: accountScopeId,
      );
      if (decision.type == MemoryLifecycleDecisionType.noChange) {
        results.add(
          LegacyProfileMemoryMigrationItemResult(
            field: seed.field,
            status: LegacyProfileMemoryMigrationStatus.duplicate,
            memoryId: decision.memoryIds.firstOrNull,
          ),
        );
        continue;
      }
      if (decision.type != MemoryLifecycleDecisionType.createProposal ||
          decision.mutations.length != 1) {
        results.add(
          LegacyProfileMemoryMigrationItemResult(
            field: seed.field,
            status: LegacyProfileMemoryMigrationStatus.conflict,
            memoryId: memoryId,
          ),
        );
        continue;
      }

      final activationMutations = _activationMutations(
        proposal,
        referenceDate.toUtc(),
      );
      if (activationMutations == null) {
        results.add(
          LegacyProfileMemoryMigrationItemResult(
            field: seed.field,
            status: LegacyProfileMemoryMigrationStatus.skipped,
            memoryId: memoryId,
          ),
        );
        continue;
      }
      await directRepository.createActiveMemory(
        proposal,
        decision.mutations.single,
        activationMutations,
      );
      results.add(
        LegacyProfileMemoryMigrationItemResult(
          field: seed.field,
          status: LegacyProfileMemoryMigrationStatus.created,
          memoryId: memoryId,
        ),
      );
    }
    return LegacyProfileMemoryMigrationResult(results);
  }

  static String profileFingerprint(UserProfile profile) {
    final safeValues = _seeds(profile)
        .map((seed) => '${seed.field}:${_normalize(seed.text)}')
        .join('|');
    return sha256.convert(utf8.encode(safeValues)).toString();
  }

  List<MemoryLifecycleMutation>? _activationMutations(
    MemoryProposal proposal,
    DateTime referenceDate,
  ) {
    final confirmed = _lifecycleEngine.evaluate(
      MemoryLifecycleCommand(
        action: MemoryLifecycleAction.confirm,
        referenceDate: referenceDate,
        actor: MemoryLifecycleActor.user,
        source: 'legacy_profile_migration',
        target: _fact(proposal, MemoryLifecycleState.proposed),
      ),
    );
    if (!confirmed.hasMutations) return null;
    final active = _lifecycleEngine.evaluate(
      MemoryLifecycleCommand(
        action: MemoryLifecycleAction.activate,
        referenceDate: referenceDate,
        actor: MemoryLifecycleActor.user,
        source: 'legacy_profile_migration',
        target: _fact(proposal, MemoryLifecycleState.confirmed),
      ),
    );
    if (!active.hasMutations) return null;
    return [...confirmed.mutations, ...active.mutations];
  }

  LifeMemoryFact _fact(MemoryProposal proposal, MemoryLifecycleState state) =>
      LifeMemoryFact(
        id: proposal.id,
        text: proposal.text,
        normalizedText: proposal.normalizedText,
        semanticType: proposal.semanticType,
        category: proposal.category,
        importance: proposal.importance,
        sourceType: LifeContextSourceType.memory,
        sourceId: proposal.source,
        createdAt: proposal.proposedAt,
        validFrom: proposal.validFrom,
        validUntil: proposal.validUntil,
        confirmationStatus: state == MemoryLifecycleState.confirmed
            ? MemoryConfirmationStatus.confirmed
            : MemoryConfirmationStatus.unconfirmed,
        sensitivity: proposal.sensitivity,
        evidenceType: LifeContextEvidenceType.explicit,
        lifecycleState: state,
        lifecycleStateIsExplicit: true,
        confidence: proposal.confidence,
      );

  static bool _isUsable(LifeMemoryFact fact) => const {
        MemoryLifecycleState.confirmed,
        MemoryLifecycleState.active,
      }.contains(fact.lifecycleState);

  static String _stableMemoryId(String accountScopeId, String field) {
    final scope = sha256
        .convert(utf8.encode('zelia-profile-memory-scope-v1|$accountScopeId'))
        .toString();
    return sha256
        .convert(utf8.encode('zelia-profile-memory-v1|$scope|$field'))
        .toString();
  }

  static String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static List<_LegacyProfileMemorySeed> _seeds(UserProfile profile) => [
        _LegacyProfileMemorySeed('habits', profile.habits, 'habit', 3),
        _LegacyProfileMemorySeed(
          'preferences',
          profile.preferences,
          'preference',
          3,
        ),
        _LegacyProfileMemorySeed('goals', profile.goals, 'goal', 4),
        _LegacyProfileMemorySeed(
          'mainLifePriority',
          profile.mainLifePriority,
          'goal',
          5,
        ),
        _LegacyProfileMemorySeed(
          'personalGoals',
          profile.personalGoals,
          'goal',
          4,
        ),
        _LegacyProfileMemorySeed(
          'businessGoals',
          profile.businessGoals,
          'goal',
          4,
        ),
        _LegacyProfileMemorySeed(
          'familyGoals',
          profile.familyGoals,
          'goal',
          4,
        ),
        _LegacyProfileMemorySeed(
          'foodPreferences',
          profile.foodPreferences,
          'preference',
          3,
        ),
      ];
}

final class _LegacyProfileMemorySeed {
  const _LegacyProfileMemorySeed(
    this.field,
    this.text,
    this.category,
    this.importance,
  );

  final String field;
  final String text;
  final String category;
  final int importance;
}
