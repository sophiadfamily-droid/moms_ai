import '../models/life_context/life_context_provenance.dart';
import '../models/memory_lifecycle.dart';
import '../models/memory_evidence.dart';
import '../models/memory_semantic_identity.dart';
import 'life_context/life_context_memory_projection.dart';
import 'memory_semantic_identity_service.dart';

final class MemoryProposalFactory {
  final LifeContextMemoryProjection _projection;
  final MemorySemanticIdentityService _identityService;

  const MemoryProposalFactory({
    LifeContextMemoryProjection projection =
        const HistoricalMemoryContextProjection(),
    MemorySemanticIdentityService identityService =
        const MemorySemanticIdentityService(),
  })  : _projection = projection,
        _identityService = identityService;

  MemoryProposal? fromHistoricalPayload({
    required String id,
    required Map<String, dynamic> payload,
    required String source,
    required DateTime proposedAt,
    bool confirmationRequired = true,
    MemoryEvidenceQualification? evidenceQualification,
    MemorySemanticSubjectScope? semanticSubjectScope,
    String? semanticSubjectEntityId,
    MemorySemanticContextType? semanticContextType,
    String? semanticContextEntityId,
  }) {
    if (id.trim().isEmpty) return null;
    final text = payload['text']?.toString() ?? '';
    final category = payload['category']?.toString().trim().toLowerCase() ?? '';
    final effectivePayload = <String, dynamic>{
      ...payload,
      if (_hasTemporarySignal(text) &&
          (category.isEmpty || category == 'personal'))
        'category': 'temporary',
    };
    final context = _projection.project([
      {
        ...effectivePayload,
        'id': id,
        'source': source,
        'createdAt': proposedAt,
      },
    ]);
    if (context.memories.isEmpty) return null;
    final fact = context.memories.single;
    if (fact.text.trim().isEmpty || fact.normalizedText.trim().isEmpty) {
      return null;
    }
    final semantic = _identityService.resolve(
      proposalId: id,
      text: fact.text,
      semanticType: fact.semanticType,
      evidence: evidenceQualification,
      explicitSubjectScope: semanticSubjectScope,
      explicitSubjectEntityId: semanticSubjectEntityId,
      contextType: semanticContextType,
      contextEntityId: semanticContextEntityId,
    );
    return MemoryProposal(
      id: id,
      text: fact.text,
      normalizedText: fact.normalizedText,
      semanticType: fact.semanticType,
      category: fact.category.isEmpty ? 'personal' : fact.category,
      importance: fact.importance,
      sensitivity: fact.sensitivity,
      source: source,
      proposedAt: proposedAt,
      confirmationRequired: confirmationRequired ||
          fact.sensitivity == LifeContextSensitivity.sensitive,
      validFrom: fact.validFrom,
      validUntil: fact.validUntil,
      expiresAt: fact.validUntil,
      evidence: evidenceQualification?.classification.name,
      evidenceClassification: evidenceQualification?.classification ??
          MemoryEvidenceClassification.unknown,
      evidenceSubjectType: evidenceQualification?.subjectType ??
          MemoryEvidenceSubjectType.unknown,
      subjectEntityId: evidenceQualification?.subjectEntityId,
      evidenceRisks: evidenceQualification?.risks.toList() ?? const [],
      isCorrection: evidenceQualification?.isCorrection ?? false,
      semanticIdentity: semantic.identity,
      semanticValue: semantic.value,
      confidence: fact.confidence,
    );
  }

  bool _hasTemporarySignal(String text) {
    final normalized = text.trim().toLowerCase();
    return const [
      'cette semaine',
      "aujourd'hui",
      'aujourd’hui',
      'demain',
      'exceptionnellement',
      'pour quelques jours',
      "jusqu'a",
      'jusqu’à',
      'pendant les vacances',
    ].any(normalized.contains);
  }
}
