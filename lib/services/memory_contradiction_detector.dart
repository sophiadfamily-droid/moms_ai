import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/life_context/memory_context.dart';
import '../models/memory_contradiction.dart';
import '../models/memory_evidence.dart';
import '../models/memory_lifecycle.dart';
import '../models/memory_semantic_identity.dart';
import 'memory_consumption_policy.dart';

final class MemoryContradictionDetector {
  const MemoryContradictionDetector();

  MemoryContradictionMatch? detect({
    required String accountScopeId,
    required MemoryProposal proposal,
    required LifeMemoryFact existing,
    required DateTime detectedAt,
  }) {
    final proposedIdentity = proposal.semanticIdentity;
    final existingRead = existing.semanticIdentityRead;
    final existingIdentity = existingRead.identity;
    if (accountScopeId.trim().isEmpty ||
        proposedIdentity == null ||
        existingRead.status != MemorySemanticIdentityReadStatus.valid ||
        existingIdentity == null ||
        existing.accountScopeId != accountScopeId ||
        existing.consumptionTrust != MemoryConsumptionTrust.modernValid ||
        !MemoryConsumptionPolicy.isConsumable(
          existing,
          referenceDate: detectedAt,
        ) ||
        !_eligibleProposal(proposal) ||
        proposedIdentity.schemaVersion !=
            MemorySemanticIdentity.currentSchemaVersion ||
        existingIdentity.schemaVersion != proposedIdentity.schemaVersion ||
        !proposedIdentity.eligibleForAutomaticContradiction ||
        !existingIdentity.eligibleForAutomaticContradiction ||
        proposedIdentity.canonicalKey != existingIdentity.canonicalKey ||
        proposedIdentity.subjectScope != existingIdentity.subjectScope ||
        proposedIdentity.subjectFingerprint !=
            existingIdentity.subjectFingerprint ||
        proposedIdentity.contextType != existingIdentity.contextType ||
        proposedIdentity.contextFingerprint !=
            existingIdentity.contextFingerprint ||
        proposedIdentity.attribute != existingIdentity.attribute ||
        existing.memoryRevision == null ||
        existing.memoryRevision! < 1) {
      return null;
    }
    final comparison = _compare(
      proposedIdentity.attribute,
      existing.semanticValue,
      proposal.semanticValue,
    );
    if (comparison == null || !comparison.incompatible) return null;
    return MemoryContradictionMatch(
      existingMemoryId: existing.id,
      proposedMemoryId: proposal.id,
      canonicalKey: proposedIdentity.canonicalKey,
      existingRevision: existing.memoryRevision!,
      existingValueFingerprint: _fingerprint(
        'zelia-memory-value-${proposedIdentity.attribute.wireName}-v1',
        comparison.existing,
      ),
      proposedValueFingerprint: _fingerprint(
        'zelia-memory-value-${proposedIdentity.attribute.wireName}-v1',
        comparison.proposed,
      ),
      subjectScope: proposedIdentity.subjectScope.wireName,
      reasonCode:
          MemoryContradictionReasonCode.incompatibleClosedAttributeValues,
    );
  }

  bool _eligibleProposal(MemoryProposal proposal) =>
      proposal.source == 'explicit_user_message' &&
      (proposal.evidenceClassification ==
              MemoryEvidenceClassification.directExplicit ||
          (proposal.evidenceClassification ==
                  MemoryEvidenceClassification.correction &&
              proposal.isCorrection)) &&
      const {
        MemoryEvidenceSubjectType.user,
        MemoryEvidenceSubjectType.structuredEntity,
      }.contains(proposal.evidenceSubjectType) &&
      proposal.evidenceRisks.isEmpty;

  _ValueComparison? _compare(
    MemorySemanticAttribute attribute,
    String? existing,
    String? proposed,
  ) {
    if (attribute != MemorySemanticAttribute.preferredAppointmentPeriod) {
      return null;
    }
    final left = _appointmentPeriod(existing);
    final right = _appointmentPeriod(proposed);
    if (left == null || right == null) return null;
    return _ValueComparison(left, right, left != right);
  }

  String? _appointmentPeriod(String? value) {
    final normalized = value
        ?.trim()
        .toLowerCase()
        .replaceAll('’', "'")
        .replaceAll(RegExp(r'\s+'), ' ');
    return switch (normalized) {
      'morning' || 'matin' || 'le matin' => 'morning',
      'afternoon' ||
      'après-midi' ||
      'apres-midi' ||
      "l'après-midi" ||
      "l'apres-midi" =>
        'afternoon',
      'evening' || 'soir' || 'le soir' => 'evening',
      _ => null,
    };
  }

  String _fingerprint(String namespace, String value) =>
      sha256.convert(utf8.encode('$namespace|$value')).toString();
}

final class _ValueComparison {
  const _ValueComparison(this.existing, this.proposed, this.incompatible);
  final String existing;
  final String proposed;
  final bool incompatible;
}
