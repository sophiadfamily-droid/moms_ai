import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/life_context/life_context_provenance.dart';
import 'package:moms_ai/models/life_context/memory_context.dart';
import 'package:moms_ai/models/memory_evidence.dart';
import 'package:moms_ai/models/memory_contradiction.dart';
import 'package:moms_ai/models/memory_lifecycle.dart';
import 'package:moms_ai/models/memory_lifecycle_state.dart';
import 'package:moms_ai/models/memory_semantic_identity.dart';
import 'package:moms_ai/services/memory_contradiction_detector.dart';
import 'package:moms_ai/services/memory_lifecycle_engine.dart';
import 'package:moms_ai/services/memory_proposal_factory.dart';

void main() {
  const detector = MemoryContradictionDetector();
  final now = DateTime.utc(2026, 7, 26, 10);

  MemoryProposal proposal({
    String id = 'proposal-2',
    String text = 'Finalement, je préfère mes rendez-vous l’après-midi.',
    MemoryEvidenceClassification classification =
        MemoryEvidenceClassification.correction,
    MemoryEvidenceSubjectType subject = MemoryEvidenceSubjectType.user,
    bool isCorrection = true,
    Set<MemoryEvidenceRisk> risks = const {},
  }) =>
      const MemoryProposalFactory().fromHistoricalPayload(
        id: id,
        payload: {'text': text, 'category': 'preference', 'importance': 2},
        source: 'explicit_user_message',
        proposedAt: now,
        evidenceQualification: MemoryEvidenceQualification(
          classification: classification,
          subjectType: subject,
          canConfirmImmediately: true,
          isCorrection: isCorrection,
          risks: risks,
        ),
      )!;

  LifeMemoryFact existing({
    String id = 'memory-1',
    String value = 'morning',
    MemoryLifecycleState state = MemoryLifecycleState.active,
    MemoryConfirmationStatus confirmation = MemoryConfirmationStatus.confirmed,
    MemoryConsumptionTrust trust = MemoryConsumptionTrust.modernValid,
    DateTime? validUntil,
    int? revision = 4,
    MemorySemanticIdentityReadResult? identity,
  }) {
    final source = proposal(
      id: 'identity-source',
      text: 'Je préfère mes rendez-vous le matin.',
      classification: MemoryEvidenceClassification.directExplicit,
      isCorrection: false,
    );
    return LifeMemoryFact(
      id: id,
      text: 'Je préfère mes rendez-vous le matin.',
      normalizedText: 'je préfère mes rendez-vous le matin',
      semanticType: LifeMemorySemanticType.preference,
      category: 'preference',
      importance: 2,
      sourceType: LifeContextSourceType.memory,
      confirmationStatus: confirmation,
      sensitivity: LifeContextSensitivity.standard,
      evidenceType: LifeContextEvidenceType.explicit,
      lifecycleState: state,
      lifecycleStateIsExplicit: true,
      consumptionTrust: trust,
      schemaVersion: 1,
      validUntil: validUntil,
      semanticIdentityRead: identity ??
          MemorySemanticIdentityReadResult.valid(source.semanticIdentity!),
      memoryRevision: revision,
      semanticValue: value,
      accountScopeId: 'account-a',
    );
  }

  test('detects incompatible closed values without exposing raw values', () {
    final result = detector.detect(
      accountScopeId: 'account-a',
      proposal: proposal(),
      existing: existing(),
      detectedAt: now,
    );

    expect(result, isNotNull);
    expect(result!.existingMemoryId, 'memory-1');
    expect(result.proposedMemoryId, 'proposal-2');
    expect(result.existingRevision, 4);
    expect(result.canonicalKey, proposal().semanticIdentity!.canonicalKey);
  });

  test('equivalent values are not contradictions', () {
    expect(
      detector.detect(
        accountScopeId: 'account-a',
        proposal: proposal(
          text: 'Finalement, je préfère mes rendez-vous le matin.',
        ),
        existing: existing(),
        detectedAt: now,
      ),
      isNull,
    );
  });

  test('identity, lifecycle, evidence and revisions fail closed', () {
    final invalidCases = <({MemoryProposal proposal, LifeMemoryFact existing})>[
      (
        proposal: proposal(
          classification: MemoryEvidenceClassification.ambiguous,
        ),
        existing: existing(),
      ),
      (
        proposal: proposal(subject: MemoryEvidenceSubjectType.unknown),
        existing: existing(),
      ),
      (
        proposal: proposal(),
        existing: existing(trust: MemoryConsumptionTrust.legacyTrusted),
      ),
      (
        proposal: proposal(),
        existing: existing(state: MemoryLifecycleState.superseded),
      ),
      (
        proposal: proposal(),
        existing: existing(validUntil: now),
      ),
      (
        proposal: proposal(),
        existing: existing(revision: null),
      ),
      (
        proposal: proposal(),
        existing: existing(
          identity: MemorySemanticIdentityReadResult.invalid,
        ),
      ),
    ];
    for (final item in invalidCases) {
      expect(
        detector.detect(
          accountScopeId: 'account-a',
          proposal: item.proposal,
          existing: item.existing,
          detectedAt: now,
        ),
        isNull,
      );
    }
  });

  test('unsupported structured attributes and unstructured values fail closed',
      () {
    final unstructured = proposal(
      text: 'Finalement, mon horaire de travail est différent.',
    );
    expect(
      detector.detect(
        accountScopeId: 'account-a',
        proposal: unstructured,
        existing: existing(value: 'some raw sentence'),
        detectedAt: now,
      ),
      isNull,
    );
  });

  test('foreign account scope fails closed', () {
    final foreign = existing();
    final copy = LifeMemoryFact(
      id: foreign.id,
      text: foreign.text,
      normalizedText: foreign.normalizedText,
      semanticType: foreign.semanticType,
      category: foreign.category,
      importance: foreign.importance,
      sourceType: foreign.sourceType,
      confirmationStatus: foreign.confirmationStatus,
      sensitivity: foreign.sensitivity,
      evidenceType: foreign.evidenceType,
      lifecycleState: foreign.lifecycleState,
      lifecycleStateIsExplicit: true,
      consumptionTrust: foreign.consumptionTrust,
      schemaVersion: 1,
      semanticIdentityRead: foreign.semanticIdentityRead,
      semanticValue: foreign.semanticValue,
      memoryRevision: foreign.memoryRevision,
      accountScopeId: 'account-b',
    );
    expect(
      detector.detect(
        accountScopeId: 'account-a',
        proposal: proposal(),
        existing: copy,
        detectedAt: now,
      ),
      isNull,
    );
  });

  test('closed French appointment aliases normalize deterministically', () {
    for (final alias in const [
      'morning',
      'matin',
      'le matin',
      ' MORNING ',
    ]) {
      expect(
        detector.detect(
          accountScopeId: 'account-a',
          proposal: proposal(),
          existing: existing(value: alias),
          detectedAt: now,
        ),
        isNotNull,
      );
    }
    for (final alias in const [
      'afternoon',
      'après-midi',
      'apres-midi',
      'l’après-midi',
      "l'apres-midi",
    ]) {
      expect(
        detector.detect(
          accountScopeId: 'account-a',
          proposal: proposal(),
          existing: existing(value: alias),
          detectedAt: now,
        ),
        isNull,
      );
    }
    for (final ambiguous in const ['dans la matinée', 'matin ou soir', '']) {
      expect(
        detector.detect(
          accountScopeId: 'account-a',
          proposal: proposal(),
          existing: existing(value: ambiguous),
          detectedAt: now,
        ),
        isNull,
      );
    }
  });

  test('engine accepts exactly one contradiction and fails closed for two', () {
    const engine = MemoryLifecycleEngine();
    final single = engine.evaluateProposal(
      proposal: proposal(),
      existingMemories: [existing(id: 'old-1')],
      referenceDate: now,
      accountScopeId: 'account-a',
    );
    expect(single.contradictionMatch?.existingMemoryId, 'old-1');
    expect(single.confirmationRequest?.previousValue, isNull);
    expect(single.confirmationRequest?.newValue, isNull);
    final visible = single.confirmationRequest!.prompt;
    expect(visible, isNot(contains('matin')));
    expect(visible, isNot(contains('après-midi')));
    final base = proposal();
    final sensitive = MemoryProposal(
      id: base.id,
      text: base.text,
      normalizedText: base.normalizedText,
      semanticType: base.semanticType,
      category: base.category,
      importance: base.importance,
      sensitivity: LifeContextSensitivity.sensitive,
      source: base.source,
      proposedAt: base.proposedAt,
      confirmationRequired: true,
      evidenceClassification: base.evidenceClassification,
      evidenceSubjectType: base.evidenceSubjectType,
      evidenceRisks: base.evidenceRisks,
      isCorrection: base.isCorrection,
      semanticIdentity: base.semanticIdentity,
      semanticValue: base.semanticValue,
    );
    final sensitiveDecision = engine.evaluateProposal(
      proposal: sensitive,
      existingMemories: [existing(id: 'old-sensitive')],
      referenceDate: now,
      accountScopeId: 'account-a',
    );
    expect(sensitiveDecision.confirmationRequest?.newValue, isNull);
    expect(sensitiveDecision.confirmationRequest?.previousValue, isNull);
    expect(sensitiveDecision.confirmationRequest?.prompt, visible);

    for (final memories in [
      [existing(id: 'old-1'), existing(id: 'old-2')],
      [existing(id: 'old-2'), existing(id: 'old-1')],
    ]) {
      final ambiguous = engine.evaluateProposal(
        proposal: proposal(),
        existingMemories: memories,
        referenceDate: now,
        accountScopeId: 'account-a',
      );
      expect(ambiguous.type, MemoryLifecycleDecisionType.ambiguous);
      expect(ambiguous.contradictionMatch, isNull);
      expect(ambiguous.confirmationRequest, isNull);
      expect(ambiguous.mutations, isEmpty);
    }
  });

  test('durable pending action round-trips without memory values', () {
    final action = MemoryReplacementPendingAction(
      actionId: 'a' * 64,
      accountScopeFingerprint: 'b' * 64,
      existingMemoryId: 'old-1',
      proposedMemoryId: 'new-1',
      canonicalKey:
          'v1|planning|preferred_appointment_period|authenticated_user|scope|personal_appointments|none',
      expectedExistingRevision: 4,
      expectedProposedRevision: 2,
      contradictionId: 'c' * 64,
      reasonCode:
          MemoryContradictionReasonCode.incompatibleClosedAttributeValues,
      state: MemoryReplacementActionState.pending,
      logicalRequestFingerprint: 'd' * 64,
      createdAt: now,
      updatedAt: now,
    );
    final json = action.toJson();
    expect(MemoryReplacementPendingAction.fromJson(json).toJson(), json);
    final serialized = json.toString();
    for (final privateValue in [
      'morning',
      'afternoon',
      'matin',
      'après-midi',
    ]) {
      expect(serialized, isNot(contains(privateValue)));
    }
    expect(
      () => MemoryReplacementPendingAction.fromJson({
        ...json,
        'expectedProposedRevision': 0,
      }),
      throwsFormatException,
    );
    for (final invalid in [
      {...json, 'state': 'unknown'},
      {...json, 'state': 'executed'},
      {
        ...json,
        'state': 'conflict',
        'executionCode': MemoryReplacementExecutionCode.executed.name,
      },
      {...json, 'executedAt': 'invalid-date'},
    ]) {
      expect(
        () => MemoryReplacementPendingAction.fromJson(invalid),
        throwsFormatException,
      );
    }

    final executed = MemoryReplacementPendingAction(
      actionId: action.actionId,
      accountScopeFingerprint: action.accountScopeFingerprint,
      existingMemoryId: action.existingMemoryId,
      proposedMemoryId: action.proposedMemoryId,
      canonicalKey: action.canonicalKey,
      expectedExistingRevision: action.expectedExistingRevision,
      expectedProposedRevision: action.expectedProposedRevision,
      contradictionId: action.contradictionId,
      reasonCode: action.reasonCode,
      state: MemoryReplacementActionState.executed,
      logicalRequestFingerprint: action.logicalRequestFingerprint,
      createdAt: now,
      updatedAt: now,
      executedAt: now,
      executionCode: MemoryReplacementExecutionCode.executed,
      finalExistingRevision: 5,
      finalProposedRevision: 3,
    );
    expect(
      MemoryReplacementPendingAction.fromJson(executed.toJson()).state,
      MemoryReplacementActionState.executed,
    );
  });
}
