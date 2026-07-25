import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/life_context/life_context_provenance.dart';
import 'package:moms_ai/models/life_context/memory_context.dart';
import 'package:moms_ai/models/memory_lifecycle.dart';
import 'package:moms_ai/models/memory_lifecycle_state.dart';
import 'package:moms_ai/models/memory_evidence.dart';
import 'package:moms_ai/models/memory_semantic_identity.dart';
import 'package:moms_ai/services/memory_lifecycle_engine.dart';
import 'package:moms_ai/services/memory_lifecycle_repository.dart';
import 'package:moms_ai/services/memory_proposal_factory.dart';
import 'package:moms_ai/services/memory_semantic_identity_service.dart';

void main() {
  const engine = MemoryLifecycleEngine();
  final now = DateTime.utc(2026, 7, 21, 10);

  group('MemoryLifecycleEngine proposals', () {
    test('a new durable memory becomes an unconfirmed proposal', () {
      final proposal = _proposal(id: 'p1');
      final result = engine.evaluateProposal(
        proposal: proposal,
        existingMemories: const [],
        referenceDate: now,
      );

      expect(result.type, MemoryLifecycleDecisionType.createProposal);
      expect(result.mutations.single.newState, MemoryLifecycleState.proposed);
      expect(result.confirmationRequest?.proposalId, 'p1');
    });

    test('sensitive inferred data always requires confirmation', () {
      final result = engine.evaluateProposal(
        proposal: _proposal(
          id: 'health',
          sensitivity: LifeContextSensitivity.sensitive,
          confirmationRequired: false,
        ),
        existingMemories: const [],
        referenceDate: now,
      );

      expect(result.confirmationRequest, isNotNull);
      expect(result.risks, contains(MemoryLifecycleSignal.sensitiveData));
      expect(result.mutations.single.newState, MemoryLifecycleState.proposed);
    });

    test('an exact typed duplicate creates no new memory', () {
      final result = engine.evaluateProposal(
        proposal: _proposal(id: 'p2'),
        existingMemories: [_fact(id: 'existing')],
        referenceDate: now,
      );

      expect(result.type, MemoryLifecycleDecisionType.noChange);
      expect(result.memoryIds, ['existing']);
      expect(result.hasMutations, isFalse);
    });

    test('an exact duplicate proposal can be confirmed instead', () {
      final result = engine.evaluateProposal(
        proposal: _proposal(id: 'p2'),
        existingMemories: [
          _fact(id: 'existing', state: MemoryLifecycleState.proposed),
        ],
        referenceDate: now,
      );

      expect(
        result.type,
        MemoryLifecycleDecisionType.confirmExistingProposal,
      );
    });

    test('a logically deleted memory does not block a new proposal', () {
      final result = engine.evaluateProposal(
        proposal: _proposal(id: 'new-after-deletion'),
        existingMemories: [
          _fact(
            id: 'deleted',
            state: MemoryLifecycleState.deleted,
            lifecycleStateIsExplicit: true,
          ),
        ],
        referenceDate: now,
      );

      expect(result.type, MemoryLifecycleDecisionType.createProposal);
    });

    test('a potential contradiction remains separate and asks confirmation',
        () {
      final result = engine.evaluateProposal(
        proposal: _proposal(
          id: 'thursday',
          text: 'The child attends the activity on Thursday',
        ),
        existingMemories: [
          _fact(
            id: 'wednesday',
            text: 'The child attends the activity on Wednesday',
          ),
        ],
        referenceDate: now,
      );

      expect(
        result.type,
        MemoryLifecycleDecisionType.needsUserConfirmation,
      );
      expect(result.memoryIds, ['wednesday', 'thursday']);
      expect(result.hasMutations, isFalse);
      expect(result.risks, contains(MemoryLifecycleSignal.possibleConflict));
    });

    test('profile precedence prevents a silent memory replacement', () {
      final result = engine.evaluateProposal(
        proposal: _proposal(id: 'profile-conflict'),
        existingMemories: const [],
        referenceDate: now,
        conflictingProfileField: 'identity.firstName',
      );

      expect(
        result.type,
        MemoryLifecycleDecisionType.needsUserConfirmation,
      );
      expect(result.hasMutations, isFalse);
      expect(result.risks, contains(MemoryLifecycleSignal.profileConflict));
    });

    test('temporary memory preserves explicit dates', () {
      final validFrom = DateTime.utc(2026, 7, 21);
      final validUntil = DateTime.utc(2026, 7, 25);
      final proposal = _proposal(
        id: 'temporary',
        semanticType: LifeMemorySemanticType.temporary,
        validFrom: validFrom,
        validUntil: validUntil,
      );
      final result = engine.evaluateProposal(
        proposal: proposal,
        existingMemories: const [],
        referenceDate: now,
      );

      expect(result.proposal?.validFrom, validFrom);
      expect(result.proposal?.validUntil, validUntil);
      expect(result.mutations.single.expiresAt, validUntil);
    });

    test('temporary memory without an end never invents expiration', () {
      final result = engine.evaluateProposal(
        proposal: _proposal(
          id: 'ambiguous-temporary',
          semanticType: LifeMemorySemanticType.temporary,
        ),
        existingMemories: const [],
        referenceDate: now,
      );

      expect(
        result.type,
        MemoryLifecycleDecisionType.needsUserConfirmation,
      );
      expect(result.hasMutations, isFalse);
      expect(result.proposal?.validUntil, isNull);
    });

    test('explicit temporary wording is typed without inventing an end date',
        () {
      final proposal = const MemoryProposalFactory().fromHistoricalPayload(
        id: 'temporary-wording',
        payload: const {
          'text': 'Exceptionnellement cette semaine je travaille au bureau',
          'category': 'personal',
          'importance': 2,
        },
        source: 'chat',
        proposedAt: now,
      );

      expect(proposal?.semanticType, LifeMemorySemanticType.temporary);
      expect(proposal?.validUntil, isNull);
      expect(proposal?.expiresAt, isNull);
      expect(proposal?.semanticIdentity, isNotNull);
      expect(proposal?.semanticIdentity?.subjectScope,
          MemorySemanticSubjectScope.unknown);
      expect(proposal?.semanticIdentity?.eligibleForAutomaticContradiction,
          isFalse);
    });

    test('invalid dates are ambiguous and produce no mutation', () {
      final result = engine.evaluateProposal(
        proposal: _proposal(
          id: 'bad-dates',
          validFrom: DateTime.utc(2026, 7, 25),
          validUntil: DateTime.utc(2026, 7, 21),
        ),
        existingMemories: const [],
        referenceDate: now,
      );

      expect(result.type, MemoryLifecycleDecisionType.ambiguous);
      expect(result.hasMutations, isFalse);
    });

    test('same inputs and reference date are deterministic', () {
      final proposal = _proposal(id: 'stable');
      final first = engine.evaluateProposal(
        proposal: proposal,
        existingMemories: const [],
        referenceDate: now,
      );
      final second = engine.evaluateProposal(
        proposal: proposal,
        existingMemories: const [],
        referenceDate: now,
      );

      expect(first.type, second.type);
      expect(first.reasons, second.reasons);
      expect(
        first.mutations.single.record.toJson(),
        second.mutations.single.record.toJson(),
      );
    });
  });

  group('MemoryLifecycleEngine transitions', () {
    test('an explicitly confirmed proposal can become active', () {
      final confirmed = engine.evaluate(_command(
        action: MemoryLifecycleAction.confirm,
        target: _fact(id: 'p', state: MemoryLifecycleState.proposed),
        state: MemoryLifecycleState.proposed,
        now: now,
      ));
      final active = engine.evaluate(_command(
        action: MemoryLifecycleAction.activate,
        target: _fact(id: 'p', state: MemoryLifecycleState.confirmed),
        state: MemoryLifecycleState.confirmed,
        now: now,
      ));

      expect(
        confirmed.mutations.single.newState,
        MemoryLifecycleState.confirmed,
      );
      expect(active.mutations.single.newState, MemoryLifecycleState.active);
    });

    test('a proposal can be rejected and cannot activate automatically', () {
      final rejected = engine.evaluate(_command(
        action: MemoryLifecycleAction.reject,
        target: _fact(id: 'p', state: MemoryLifecycleState.proposed),
        state: MemoryLifecycleState.proposed,
        now: now,
      ));
      final activation = engine.evaluate(_command(
        action: MemoryLifecycleAction.activate,
        target: _fact(id: 'p', state: MemoryLifecycleState.rejected),
        state: MemoryLifecycleState.rejected,
        now: now,
      ));

      expect(rejected.type, MemoryLifecycleDecisionType.rejectProposal);
      expect(
        activation.type,
        MemoryLifecycleDecisionType.invalidTransition,
      );
    });

    test('assistant cannot confirm sensitive memory', () {
      final result = engine.evaluate(MemoryLifecycleCommand(
        action: MemoryLifecycleAction.confirm,
        target: _fact(
          id: 'sensitive',
          state: MemoryLifecycleState.proposed,
          sensitivity: LifeContextSensitivity.sensitive,
        ),
        targetState: MemoryLifecycleState.proposed,
        referenceDate: now,
        actor: MemoryLifecycleActor.assistant,
        source: 'assistant',
      ));

      expect(
        result.type,
        MemoryLifecycleDecisionType.needsUserConfirmation,
      );
      expect(result.hasMutations, isFalse);
    });

    test('active memory can become obsolete without deletion', () {
      final result = engine.evaluate(_command(
        action: MemoryLifecycleAction.markObsolete,
        target: _fact(id: 'old-job'),
        state: MemoryLifecycleState.active,
        now: now,
      ));

      expect(
        result.type,
        MemoryLifecycleDecisionType.markExistingObsolete,
      );
      expect(result.mutations.single.newState, MemoryLifecycleState.obsolete);
    });

    test('logical deletion retains actor, date and reason', () {
      final result = engine.evaluate(_command(
        action: MemoryLifecycleAction.delete,
        target: _fact(id: 'delete-me'),
        state: MemoryLifecycleState.active,
        now: now,
        reason: 'user_requested_forget',
      ));
      final mutation = result.mutations.single;

      expect(result.type, MemoryLifecycleDecisionType.deleteExistingMemory);
      expect(mutation.memoryId, 'delete-me');
      expect(mutation.deletedAt, now);
      expect(mutation.record.actor, MemoryLifecycleActor.user);
      expect(mutation.record.reason, 'user_requested_forget');
    });

    test('assistant deletion requests confirmation and mutates nothing', () {
      final result = engine.evaluate(MemoryLifecycleCommand(
        action: MemoryLifecycleAction.delete,
        target: _fact(id: 'protected'),
        targetState: MemoryLifecycleState.active,
        referenceDate: now,
        actor: MemoryLifecycleActor.assistant,
        source: 'assistant',
      ));

      expect(
        result.type,
        MemoryLifecycleDecisionType.needsUserConfirmation,
      );
      expect(result.hasMutations, isFalse);
    });

    test('second confirmation and second deletion are idempotent', () {
      final confirmed = engine.evaluate(_command(
        action: MemoryLifecycleAction.confirm,
        target: _fact(id: 'confirmed', state: MemoryLifecycleState.confirmed),
        state: MemoryLifecycleState.confirmed,
        now: now,
      ));
      final deleted = engine.evaluate(_command(
        action: MemoryLifecycleAction.delete,
        target: _fact(id: 'deleted', state: MemoryLifecycleState.deleted),
        state: MemoryLifecycleState.deleted,
        now: now,
      ));

      expect(confirmed.type, MemoryLifecycleDecisionType.noChange);
      expect(deleted.type, MemoryLifecycleDecisionType.noChange);
      expect(confirmed.hasMutations, isFalse);
      expect(deleted.hasMutations, isFalse);
    });

    test('repeated history record does not duplicate audit', () {
      final first = engine.evaluate(_command(
        action: MemoryLifecycleAction.delete,
        target: _fact(id: 'memory'),
        state: MemoryLifecycleState.active,
        now: now,
      ));
      final second = engine.evaluate(MemoryLifecycleCommand(
        action: MemoryLifecycleAction.delete,
        target: _fact(id: 'memory'),
        targetState: MemoryLifecycleState.active,
        referenceDate: now,
        actor: MemoryLifecycleActor.user,
        source: 'chat',
        history: [first.mutations.single.record],
      ));

      expect(second.type, MemoryLifecycleDecisionType.noChange);
      expect(second.hasMutations, isFalse);
    });

    test('expired state uses only the injected date', () {
      final before = engine.evaluate(_command(
        action: MemoryLifecycleAction.expire,
        target: _fact(
          id: 'temp',
          validUntil: DateTime.utc(2026, 7, 22),
        ),
        state: MemoryLifecycleState.active,
        now: DateTime.utc(2026, 7, 22),
      ));
      final after = engine.evaluate(_command(
        action: MemoryLifecycleAction.expire,
        target: _fact(
          id: 'temp',
          validUntil: DateTime.utc(2026, 7, 22),
        ),
        state: MemoryLifecycleState.active,
        now: DateTime.utc(2026, 7, 23),
      ));

      expect(before.type, MemoryLifecycleDecisionType.noChange);
      expect(after.mutations.single.newState, MemoryLifecycleState.expired);
    });

    test('replacement keeps both stable linked identifiers', () {
      final result = engine.evaluate(MemoryLifecycleCommand(
        action: MemoryLifecycleAction.replace,
        target: _fact(id: 'old'),
        replacement: _fact(
          id: 'new',
          state: MemoryLifecycleState.confirmed,
          text: 'Football jeudi',
        ),
        targetState: MemoryLifecycleState.active,
        referenceDate: now,
        actor: MemoryLifecycleActor.user,
        source: 'chat_confirmation',
      ));

      expect(
        result.type,
        MemoryLifecycleDecisionType.replaceExistingMemory,
      );
      expect(result.memoryIds, ['old', 'new']);
      expect(result.mutations.first.replacedByMemoryId, 'new');
      expect(result.mutations.last.supersedesMemoryId, 'old');
    });

    test('assistant replacement asks confirmation and mutates nothing', () {
      final result = engine.evaluate(MemoryLifecycleCommand(
        action: MemoryLifecycleAction.replace,
        target: _fact(id: 'old'),
        replacement: _fact(id: 'new', text: 'Football jeudi'),
        targetState: MemoryLifecycleState.active,
        referenceDate: now,
        actor: MemoryLifecycleActor.assistant,
        source: 'assistant',
      ));

      expect(
        result.type,
        MemoryLifecycleDecisionType.needsUserConfirmation,
      );
      expect(result.hasMutations, isFalse);
      expect(result.confirmationRequest?.memoryId, 'old');
      expect(result.confirmationRequest?.proposalId, 'new');
    });

    test('memory cannot replace itself', () {
      final result = engine.evaluate(MemoryLifecycleCommand(
        action: MemoryLifecycleAction.replace,
        target: _fact(id: 'same'),
        replacement: _fact(id: 'same'),
        targetState: MemoryLifecycleState.active,
        referenceDate: now,
        actor: MemoryLifecycleActor.user,
        source: 'chat',
      ));

      expect(
        result.type,
        MemoryLifecycleDecisionType.invalidTransition,
      );
      expect(result.hasMutations, isFalse);
    });

    test('missing stable identifier is refused cleanly', () {
      final result = engine.evaluate(_command(
        action: MemoryLifecycleAction.delete,
        target: _fact(id: ''),
        state: MemoryLifecycleState.active,
        now: now,
      ));

      expect(
        result.type,
        MemoryLifecycleDecisionType.invalidTransition,
      );
      expect(result.hasMutations, isFalse);
    });
  });

  group('immutability and persistence boundary', () {
    test('nested audit metadata is deeply immutable', () {
      final source = <String, Object?>{
        'nested': <String, Object?>{
          'items': <String>['one'],
        },
      };
      final record = MemoryLifecycleRecord(
        action: MemoryLifecycleAction.propose,
        previousState: null,
        newState: MemoryLifecycleState.proposed,
        occurredAt: now,
        source: 'test',
        actor: MemoryLifecycleActor.system,
        memoryId: 'm1',
        metadata: source,
      );
      (source['nested'] as Map<String, Object?>)['changed'] = true;
      final nested = record.metadata['nested'] as Map;
      final items = nested['items'] as List;

      expect(nested.containsKey('changed'), isFalse);
      expect(() => nested['x'] = true, throwsUnsupportedError);
      expect(() => items.add('two'), throwsUnsupportedError);
    });

    test('Firestore proposal serialization is additive and compatible', () {
      final proposal = _proposal(
        id: 'persisted',
        evidenceClassification: MemoryEvidenceClassification.correction,
        evidenceSubjectType: MemoryEvidenceSubjectType.structuredEntity,
        subjectEntityId: 'person-42',
        evidenceRisks: const {MemoryEvidenceRisk.negation},
        isCorrection: true,
        semanticIdentity: MemorySemanticIdentity(
          domain: MemorySemanticDomain.planning,
          attribute: MemorySemanticAttribute.preferredAppointmentPeriod,
          subjectScope: MemorySemanticSubjectScope.structuredEntity,
          subjectFingerprint: MemorySemanticIdentityService.fingerprint(
            namespace: 'zelia-memory-subject-v1',
            scope: 'structured_entity',
            exactId: 'person-42',
          ),
          contextType: MemorySemanticContextType.personalAppointments,
          contextFingerprint: null,
          canonicalKey: MemorySemanticIdentity.buildCanonicalKey(
            domain: MemorySemanticDomain.planning,
            attribute: MemorySemanticAttribute.preferredAppointmentPeriod,
            subjectScope: MemorySemanticSubjectScope.structuredEntity,
            subjectFingerprint: MemorySemanticIdentityService.fingerprint(
              namespace: 'zelia-memory-subject-v1',
              scope: 'structured_entity',
              exactId: 'person-42',
            ),
            contextType: MemorySemanticContextType.personalAppointments,
            contextFingerprint: null,
          ),
          eligibleForAutomaticContradiction: true,
        ),
        semanticValue: 'morning',
      );
      final decision = engine.evaluateProposal(
        proposal: proposal,
        existingMemories: const [],
        referenceDate: now,
      );
      final json = MemoryLifecycleFirestoreSerializer.proposal(
        proposal,
        decision.mutations.single,
      );

      expect(json['text'], proposal.text);
      expect(json['normalizedText'], proposal.normalizedText);
      expect(json['category'], proposal.category);
      expect(json['importance'], proposal.importance);
      expect(json['confirmationStatus'], 'unconfirmed');
      expect(json['lifecycleState'], 'proposed');
      expect(json['lifecycleHistory'], isA<List>());
      expect(json['evidenceClassification'], 'correction');
      expect(json['evidenceSubjectType'], 'structuredEntity');
      expect(json['subjectEntityId'], 'person-42');
      expect(json['evidenceRisks'], ['negation']);
      expect(json['isCorrection'], isTrue);
      expect(json['canonicalKey'], proposal.semanticIdentity?.canonicalKey);
      expect(json['semanticValue'], 'morning');
      expect(json['eligibleForAutomaticContradiction'], isTrue);
      expect(json['semanticIdentity'], isA<Map<String, Object?>>());
      final restored = MemorySemanticIdentity.fromJson(
        json['semanticIdentity'],
      );
      expect(restored.toJson(), proposal.semanticIdentity?.toJson());
    });

    test('Firestore consolidates confirmation and activation atomically', () {
      final target = _fact(
        id: 'proposal-1',
        state: MemoryLifecycleState.proposed,
        lifecycleStateIsExplicit: true,
      );
      final confirmation = engine.evaluate(
        _command(
          action: MemoryLifecycleAction.confirm,
          target: target,
          state: MemoryLifecycleState.proposed,
          now: now,
        ),
      );
      final activation = engine.evaluate(
        _command(
          action: MemoryLifecycleAction.activate,
          target: target,
          state: MemoryLifecycleState.confirmed,
          now: now,
        ),
      );

      final json = MemoryLifecycleFirestoreSerializer.mutations([
        ...confirmation.mutations,
        ...activation.mutations,
      ]);

      expect(json['lifecycleState'], 'active');
      expect(json['confirmationStatus'], 'confirmed');
      expect(json['confirmedAt'], now);
      expect(json['lifecycleHistory'], isNotNull);
    });

    test('repository contract can be replaced by a fake', () async {
      final fake = _FakeMemoryLifecycleRepository();
      final proposal = _proposal(id: 'fake-id');
      final decision = engine.evaluateProposal(
        proposal: proposal,
        existingMemories: const [],
        referenceDate: now,
      );

      await fake.createProposal(proposal, decision.mutations.single);

      expect(await fake.allocateProposalId(), 'fake-id');
      expect(fake.proposals.single.id, 'fake-id');
    });

    test('pure engine source has no Firebase dependency', () async {
      final source = await File(
        'lib/services/memory_lifecycle_engine.dart',
      ).readAsString();

      expect(source, isNot(contains('cloud_firestore')));
      expect(source, isNot(contains('Firebase')));
    });
  });
}

MemoryProposal _proposal({
  required String id,
  String text = 'The child attends the activity on Wednesday',
  LifeMemorySemanticType semanticType = LifeMemorySemanticType.routine,
  LifeContextSensitivity sensitivity = LifeContextSensitivity.standard,
  bool confirmationRequired = true,
  DateTime? validFrom,
  DateTime? validUntil,
  MemoryEvidenceClassification evidenceClassification =
      MemoryEvidenceClassification.unknown,
  MemoryEvidenceSubjectType evidenceSubjectType =
      MemoryEvidenceSubjectType.unknown,
  String? subjectEntityId,
  Set<MemoryEvidenceRisk> evidenceRisks = const {},
  bool isCorrection = false,
  MemorySemanticIdentity? semanticIdentity,
  String? semanticValue,
}) {
  return MemoryProposal(
    id: id,
    text: text,
    normalizedText: text.toLowerCase(),
    semanticType: semanticType,
    category: 'routine',
    importance: 2,
    sensitivity: sensitivity,
    source: 'test',
    proposedAt: DateTime.utc(2026, 7, 21),
    confirmationRequired: confirmationRequired,
    validFrom: validFrom,
    validUntil: validUntil,
    evidenceClassification: evidenceClassification,
    evidenceSubjectType: evidenceSubjectType,
    subjectEntityId: subjectEntityId,
    evidenceRisks: evidenceRisks.toList(),
    isCorrection: isCorrection,
    semanticIdentity: semanticIdentity,
    semanticValue: semanticValue,
  );
}

LifeMemoryFact _fact({
  required String id,
  String text = 'The child attends the activity on Wednesday',
  MemoryLifecycleState state = MemoryLifecycleState.active,
  DateTime? validUntil,
  LifeContextSensitivity sensitivity = LifeContextSensitivity.standard,
  bool lifecycleStateIsExplicit = false,
}) {
  return LifeMemoryFact(
    id: id,
    text: text,
    normalizedText: text.toLowerCase(),
    semanticType: LifeMemorySemanticType.routine,
    category: 'routine',
    importance: 2,
    sourceType: LifeContextSourceType.memory,
    confirmationStatus: state == MemoryLifecycleState.proposed
        ? MemoryConfirmationStatus.unconfirmed
        : MemoryConfirmationStatus.confirmed,
    lifecycleState: state,
    lifecycleStateIsExplicit: lifecycleStateIsExplicit,
    sensitivity: sensitivity,
    evidenceType: LifeContextEvidenceType.explicit,
    validUntil: validUntil,
  );
}

MemoryLifecycleCommand _command({
  required MemoryLifecycleAction action,
  required LifeMemoryFact target,
  required MemoryLifecycleState state,
  required DateTime now,
  String? reason,
}) {
  return MemoryLifecycleCommand(
    action: action,
    target: target,
    targetState: state,
    referenceDate: now,
    actor: MemoryLifecycleActor.user,
    source: 'chat',
    reason: reason,
  );
}

final class _FakeMemoryLifecycleRepository
    implements MemoryLifecycleRepository {
  final List<MemoryProposal> proposals = [];

  @override
  Future<String?> allocateProposalId() async => 'fake-id';

  @override
  Future<List<LifeMemoryFact>> findCandidates(
    MemoryProposal proposal, {
    int limit = 25,
  }) async =>
      const [];

  @override
  Future<LifeMemoryFact?> getById(String memoryId) async => null;

  @override
  Future<void> applyMutations(List<MemoryLifecycleMutation> mutations) async {}

  @override
  Future<void> createProposal(
    MemoryProposal proposal,
    MemoryLifecycleMutation mutation,
  ) async {
    proposals.add(proposal);
  }
}
