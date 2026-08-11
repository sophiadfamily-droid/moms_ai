import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/life_context/memory_context.dart';
import '../models/memory_contradiction.dart';
import '../models/memory_evidence.dart';
import '../models/memory_lifecycle.dart';
import '../models/memory_semantic_identity.dart';
import 'memory_consumption_policy.dart';
import 'memory_semantic_identity_service.dart';

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
    final birthdayCompatibility = _legacyBirthdayCompatibility(
      proposal: proposal,
      existing: existing,
    );
    if (accountScopeId.trim().isEmpty ||
        proposedIdentity == null ||
        ((existingRead.status != MemorySemanticIdentityReadStatus.valid ||
                existingIdentity == null) &&
            birthdayCompatibility == null) ||
        existing.accountScopeId != accountScopeId ||
        existing.consumptionTrust != MemoryConsumptionTrust.modernValid ||
        !MemoryConsumptionPolicy.isConsumable(
          existing,
          referenceDate: detectedAt,
        ) ||
        !_eligibleProposal(proposal) ||
        proposedIdentity.schemaVersion !=
            MemorySemanticIdentity.currentSchemaVersion ||
        (existingIdentity != null &&
            existingIdentity.schemaVersion != proposedIdentity.schemaVersion) ||
        !proposedIdentity.eligibleForAutomaticContradiction ||
        (birthdayCompatibility == null &&
            (!existingIdentity!.eligibleForAutomaticContradiction ||
                proposedIdentity.canonicalKey !=
                    existingIdentity.canonicalKey ||
                proposedIdentity.subjectScope !=
                    existingIdentity.subjectScope ||
                proposedIdentity.subjectFingerprint !=
                    existingIdentity.subjectFingerprint ||
                proposedIdentity.contextType != existingIdentity.contextType ||
                proposedIdentity.contextFingerprint !=
                    existingIdentity.contextFingerprint ||
                proposedIdentity.attribute != existingIdentity.attribute)) ||
        existing.memoryRevision == null ||
        existing.memoryRevision! < 1) {
      return null;
    }
    final comparison = birthdayCompatibility ??
        _compare(
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
    if (attribute == MemorySemanticAttribute.birthday) {
      final left = _birthday(existing);
      final right = _birthday(proposed);
      if (left == null || right == null) return null;
      return _ValueComparison(left, right, left != right);
    }
    if (attribute != MemorySemanticAttribute.preferredAppointmentPeriod) {
      return null;
    }
    final left = _appointmentPeriod(existing);
    final right = _appointmentPeriod(proposed);
    if (left == null || right == null) return null;
    return _ValueComparison(left, right, left != right);
  }

  _ValueComparison? _legacyBirthdayCompatibility({
    required MemoryProposal proposal,
    required LifeMemoryFact existing,
  }) {
    if (proposal.semanticIdentity?.attribute !=
        MemorySemanticAttribute.birthday) {
      return null;
    }
    final existingMeaning = const MemorySemanticIdentityService().resolve(
      proposalId: existing.id,
      text: existing.text,
      semanticType: existing.semanticType,
      evidence: MemoryEvidenceQualification(
        classification: MemoryEvidenceClassification.directExplicit,
        subjectType: MemoryEvidenceSubjectType.user,
        canConfirmImmediately: true,
        isCorrection: false,
      ),
    );
    if (existingMeaning.identity.attribute !=
            MemorySemanticAttribute.birthday ||
        existingMeaning.identity.canonicalKey !=
            proposal.semanticIdentity!.canonicalKey) {
      return null;
    }
    final left = _birthday(existingMeaning.value);
    final right = _birthday(proposal.semanticValue);
    if (left == null || right == null) return null;
    return _ValueComparison(left, right, left != right);
  }

  String? _birthday(String? value) {
    final normalized = value?.trim();
    if (normalized == null ||
        !RegExp(r'^(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$')
            .hasMatch(normalized)) {
      return null;
    }
    return normalized;
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
