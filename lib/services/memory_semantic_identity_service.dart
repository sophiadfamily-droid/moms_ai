import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/life_context/memory_context.dart';
import '../models/memory_evidence.dart';
import '../models/memory_semantic_identity.dart';

final class MemorySemanticResolution {
  const MemorySemanticResolution({
    required this.identity,
    required this.value,
  });

  final MemorySemanticIdentity identity;
  final String value;
}

final class MemorySemanticIdentityService {
  const MemorySemanticIdentityService();

  MemorySemanticResolution resolve({
    required String proposalId,
    required String text,
    required LifeMemorySemanticType semanticType,
    required MemoryEvidenceQualification? evidence,
    MemorySemanticSubjectScope? explicitSubjectScope,
    String? explicitSubjectEntityId,
    MemorySemanticContextType? contextType,
    String? contextEntityId,
  }) {
    final normalized = _normalize(text);
    final meaning = _meaning(normalized, semanticType);
    var subject = _subject(
      evidence,
      explicitSubjectScope: explicitSubjectScope,
      explicitSubjectEntityId: explicitSubjectEntityId,
    );
    if (subject.scope.requiresFingerprint &&
        (subject.entityId == null || subject.entityId!.isEmpty)) {
      subject = const _MemorySubject(MemorySemanticSubjectScope.unknown, null);
    }
    final subjectFingerprint =
        subject.scope == MemorySemanticSubjectScope.unknown
            ? fingerprint(
                namespace: 'zelia-memory-unknown-v1',
                scope: 'proposal',
                exactId: proposalId,
              )
            : subject.entityId == null
                ? null
                : fingerprint(
                    namespace: 'zelia-memory-subject-v1',
                    scope: subject.scope.wireName,
                    exactId: subject.entityId!,
                  );
    final effectiveContext = contextType ?? meaning.contextType;
    final contextFingerprint =
        contextEntityId == null || contextEntityId.isEmpty
            ? null
            : fingerprint(
                namespace: 'zelia-memory-context-v1',
                scope: effectiveContext.wireName,
                exactId: contextEntityId,
              );
    final eligible = MemorySemanticIdentity.computeEligibility(
      domain: meaning.domain,
      attribute: meaning.attribute,
      subjectScope: subject.scope,
      subjectFingerprint: subjectFingerprint,
      contextType: effectiveContext,
    );
    final key = MemorySemanticIdentity.buildCanonicalKey(
      domain: meaning.domain,
      attribute: meaning.attribute,
      subjectScope: subject.scope,
      subjectFingerprint: subjectFingerprint,
      contextType: effectiveContext,
      contextFingerprint: contextFingerprint,
    );

    return MemorySemanticResolution(
      identity: MemorySemanticIdentity(
        domain: meaning.domain,
        attribute: meaning.attribute,
        subjectScope: subject.scope,
        subjectFingerprint: subjectFingerprint,
        contextType: effectiveContext,
        contextFingerprint: contextFingerprint,
        canonicalKey: key,
        eligibleForAutomaticContradiction: eligible,
      ),
      value: meaning.value,
    );
  }

  static String fingerprint({
    required String namespace,
    required String scope,
    required String exactId,
  }) =>
      sha256.convert(utf8.encode('$namespace|$scope|$exactId')).toString();

  _MemoryMeaning _meaning(
    String text,
    LifeMemorySemanticType semanticType,
  ) {
    if (text.contains('rendez vous') && text.contains('prefere')) {
      return _MemoryMeaning(
        MemorySemanticDomain.planning,
        MemorySemanticAttribute.preferredAppointmentPeriod,
        MemorySemanticContextType.personalAppointments,
        _periodValue(text),
      );
    }
    if (_containsAny(text, const [
      'ne peux jamais',
      'jamais disponible',
      'indisponible tous les',
    ])) {
      return _MemoryMeaning(
        MemorySemanticDomain.availability,
        MemorySemanticAttribute.unavailableWeekdayPeriod,
        text.contains('travail')
            ? MemorySemanticContextType.workplace
            : MemorySemanticContextType.general,
        text,
      );
    }
    if (_containsAny(text, const ['adresse actuelle', 'domicile actuel'])) {
      return _MemoryMeaning(
        MemorySemanticDomain.residence,
        MemorySemanticAttribute.currentResidence,
        MemorySemanticContextType.residence,
        text,
      );
    }
    if (_containsAny(text, const ['travaille', 'horaire de travail'])) {
      return _MemoryMeaning(
        MemorySemanticDomain.work,
        MemorySemanticAttribute.workSchedule,
        MemorySemanticContextType.workplace,
        text,
      );
    }
    if (_containsAny(text, const [
      'tous les',
      'toutes les',
      'chaque semaine',
      'chaque mois',
    ])) {
      return _MemoryMeaning(
        MemorySemanticDomain.routine,
        MemorySemanticAttribute.recurringActivitySchedule,
        MemorySemanticContextType.general,
        text,
      );
    }
    if (_containsAny(text, const [
      'vegetar',
      'vegan',
      'sans gluten',
      'alimentaire',
    ])) {
      return _MemoryMeaning(
        MemorySemanticDomain.preference,
        MemorySemanticAttribute.dietaryPreference,
        MemorySemanticContextType.general,
        text,
      );
    }
    return switch (semanticType) {
      LifeMemorySemanticType.preference => _MemoryMeaning(
          MemorySemanticDomain.preference,
          MemorySemanticAttribute.generalPreference,
          MemorySemanticContextType.general,
          text,
        ),
      LifeMemorySemanticType.constraint => _MemoryMeaning(
          MemorySemanticDomain.constraint,
          MemorySemanticAttribute.generalConstraint,
          MemorySemanticContextType.general,
          text,
        ),
      LifeMemorySemanticType.routine => _MemoryMeaning(
          MemorySemanticDomain.routine,
          MemorySemanticAttribute.generalRoutine,
          MemorySemanticContextType.general,
          text,
        ),
      _ => _MemoryMeaning(
          MemorySemanticDomain.general,
          MemorySemanticAttribute.generalFact,
          MemorySemanticContextType.general,
          text,
        ),
    };
  }

  _MemorySubject _subject(
    MemoryEvidenceQualification? evidence, {
    required MemorySemanticSubjectScope? explicitSubjectScope,
    required String? explicitSubjectEntityId,
  }) {
    if (explicitSubjectScope != null) {
      return _MemorySubject(explicitSubjectScope, explicitSubjectEntityId);
    }
    return switch (evidence?.subjectType) {
      MemoryEvidenceSubjectType.user => const _MemorySubject(
          MemorySemanticSubjectScope.authenticatedUser, null),
      MemoryEvidenceSubjectType.structuredEntity => _MemorySubject(
          MemorySemanticSubjectScope.structuredEntity,
          evidence?.subjectEntityId,
        ),
      _ => const _MemorySubject(MemorySemanticSubjectScope.unknown, null),
    };
  }

  String _periodValue(String text) {
    if (text.contains('apres midi')) return 'afternoon';
    if (text.contains('matin')) return 'morning';
    if (text.contains('soir')) return 'evening';
    return 'unspecified';
  }

  bool _containsAny(String value, Iterable<String> markers) =>
      markers.any(value.contains);

  String _normalize(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('’', "'")
      .replaceAll('œ', 'oe')
      .replaceAll("'", ' ')
      .replaceAll('-', ' ')
      .replaceAll('à', 'a')
      .replaceAll('â', 'a')
      .replaceAll('ä', 'a')
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('ë', 'e')
      .replaceAll('î', 'i')
      .replaceAll('ï', 'i')
      .replaceAll('ô', 'o')
      .replaceAll('ö', 'o')
      .replaceAll('ù', 'u')
      .replaceAll('û', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'[^a-z0-9_]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

final class _MemoryMeaning {
  const _MemoryMeaning(
    this.domain,
    this.attribute,
    this.contextType,
    this.value,
  );

  final MemorySemanticDomain domain;
  final MemorySemanticAttribute attribute;
  final MemorySemanticContextType contextType;
  final String value;
}

final class _MemorySubject {
  const _MemorySubject(this.scope, this.entityId);

  final MemorySemanticSubjectScope scope;
  final String? entityId;
}
