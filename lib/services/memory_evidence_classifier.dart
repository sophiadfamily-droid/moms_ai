import '../models/memory_evidence.dart';
import 'french_question_detector.dart';

final class MemoryEvidenceClassifier {
  const MemoryEvidenceClassifier();

  MemoryEvidenceQualification classify(
    String message, {
    String? resolvedSubjectEntityId,
  }) {
    final normalized = _normalize(message);
    if (normalized.isEmpty) {
      return _unknown(
        MemoryEvidenceSubjectType.unknown,
        null,
        reason: 'empty_statement',
      );
    }

    final initialSubject = _subject(
      normalized,
      resolvedSubjectEntityId: resolvedSubjectEntityId,
    );
    if (_isQuestion(normalized)) {
      return _blocked(
        MemoryEvidenceClassification.question,
        initialSubject.type,
        initialSubject.id,
        false,
        MemoryEvidenceRisk.question,
        'question',
      );
    }
    if (_isQuotation(message, normalized)) {
      return _blocked(
        MemoryEvidenceClassification.quoted,
        initialSubject.type,
        initialSubject.id,
        false,
        MemoryEvidenceRisk.quotation,
        'quoted_content',
      );
    }
    if (_isUnresolvedThirdParty(normalized, initialSubject.type)) {
      return _blocked(
        MemoryEvidenceClassification.thirdParty,
        initialSubject.type,
        initialSubject.id,
        false,
        MemoryEvidenceRisk.thirdPartyAttribution,
        'unresolved_third_party',
      );
    }

    final correctionStatement = _extractCorrectionStatement(message);
    if (correctionStatement != null) {
      return _classifyStatement(
        correctionStatement,
        resolvedSubjectEntityId: resolvedSubjectEntityId,
        isCorrection: true,
      );
    }

    return _classifyStatement(
      message,
      resolvedSubjectEntityId: resolvedSubjectEntityId,
      isCorrection: false,
    );
  }

  MemoryEvidenceQualification assistantCandidate() =>
      MemoryEvidenceQualification(
        classification: MemoryEvidenceClassification.unknown,
        subjectType: MemoryEvidenceSubjectType.unknown,
        canConfirmImmediately: false,
        isCorrection: false,
        risks: const {MemoryEvidenceRisk.unknownSubject},
        reasonCodes: const ['assistant_candidate'],
      );

  MemoryEvidenceQualification _classifyStatement(
    String statement, {
    required String? resolvedSubjectEntityId,
    required bool isCorrection,
  }) {
    final normalized = _normalize(statement);
    final subject = _subject(
      normalized,
      resolvedSubjectEntityId: resolvedSubjectEntityId,
    );

    if (normalized.isEmpty) {
      return _unknown(
        subject.type,
        subject.id,
        isCorrection: isCorrection,
        reason: 'empty_statement',
      );
    }
    if (_isQuestion(normalized)) {
      return _blocked(
        MemoryEvidenceClassification.question,
        subject.type,
        subject.id,
        isCorrection,
        MemoryEvidenceRisk.question,
        'question',
      );
    }
    if (_isUnresolvedThirdParty(normalized, subject.type)) {
      return _blocked(
        MemoryEvidenceClassification.thirdParty,
        subject.type,
        subject.id,
        isCorrection,
        MemoryEvidenceRisk.thirdPartyAttribution,
        'unresolved_third_party',
      );
    }
    if (_hasConditionalMarker(normalized)) {
      return _blocked(
        MemoryEvidenceClassification.conditional,
        subject.type,
        subject.id,
        isCorrection,
        MemoryEvidenceRisk.conditional,
        'conditional_statement',
        statementForMemory: isCorrection ? statement.trim() : null,
      );
    }
    if (_hasHypothesisMarker(normalized)) {
      return _blocked(
        MemoryEvidenceClassification.hypothetical,
        subject.type,
        subject.id,
        isCorrection,
        MemoryEvidenceRisk.hypothesis,
        'hypothetical_statement',
        statementForMemory: isCorrection ? statement.trim() : null,
      );
    }
    if (_hasUncertaintyMarker(normalized)) {
      return _blocked(
        MemoryEvidenceClassification.ambiguous,
        subject.type,
        subject.id,
        isCorrection,
        MemoryEvidenceRisk.ambiguity,
        'ambiguous_statement',
        statementForMemory: isCorrection ? statement.trim() : null,
      );
    }
    if (_hasTemporaryMarker(normalized)) {
      return _blocked(
        MemoryEvidenceClassification.temporary,
        subject.type,
        subject.id,
        isCorrection,
        MemoryEvidenceRisk.temporaryOnly,
        'temporary_statement',
        statementForMemory: isCorrection ? statement.trim() : null,
      );
    }
    if (_hasPastOnlyMarker(normalized)) {
      return _blocked(
        MemoryEvidenceClassification.pastState,
        subject.type,
        subject.id,
        isCorrection,
        MemoryEvidenceRisk.pastOnly,
        'past_state',
        statementForMemory: isCorrection ? statement.trim() : null,
      );
    }
    if (_isNegatedPositiveClaim(normalized) && !isCorrection) {
      return _blocked(
        MemoryEvidenceClassification.negated,
        subject.type,
        subject.id,
        false,
        MemoryEvidenceRisk.negation,
        'negated_claim',
      );
    }
    if (!subject.isAttributable) {
      return _unknown(
        subject.type,
        subject.id,
        isCorrection: isCorrection,
        reason: 'subject_unknown',
        statementForMemory: isCorrection ? statement.trim() : null,
      );
    }

    final durableNegativeConstraint = _isDurableNegativeConstraint(normalized);
    final recognized = durableNegativeConstraint ||
        _isRecognizedDirectStatement(normalized) ||
        isCorrection && _isRecognizedCorrectionStatement(normalized);
    if (!recognized) {
      return _unknown(
        subject.type,
        subject.id,
        isCorrection: isCorrection,
        reason: 'direct_statement_not_proven',
        statementForMemory: isCorrection ? statement.trim() : null,
      );
    }

    return MemoryEvidenceQualification(
      classification: isCorrection
          ? MemoryEvidenceClassification.correction
          : MemoryEvidenceClassification.directExplicit,
      subjectType: subject.type,
      subjectEntityId: subject.id,
      statementForMemory: isCorrection ? statement.trim() : null,
      canConfirmImmediately: true,
      isCorrection: isCorrection,
      risks: durableNegativeConstraint || _isNegativeCorrection(normalized)
          ? const {MemoryEvidenceRisk.negation}
          : const {},
      reasonCodes: [
        isCorrection
            ? 'explicit_current_correction'
            : 'direct_explicit_statement',
      ],
    );
  }

  _EvidenceSubject _subject(
    String value, {
    required String? resolvedSubjectEntityId,
  }) {
    final resolvedId = resolvedSubjectEntityId?.trim();
    final hasResolvedSubject = resolvedId?.isNotEmpty == true;
    final reportedClaim = _hasReportedClaim(value);
    if (_isDurableRelationshipFact(value)) {
      return const _EvidenceSubject(MemoryEvidenceSubjectType.user, null);
    }
    final thirdParty = _hasThirdPartySubject(value);
    if (hasResolvedSubject && thirdParty && !reportedClaim) {
      return _EvidenceSubject(
        MemoryEvidenceSubjectType.structuredEntity,
        resolvedId,
      );
    }
    if (thirdParty || reportedClaim) {
      return const _EvidenceSubject(
        MemoryEvidenceSubjectType.unresolvedThirdParty,
        null,
      );
    }
    if (_hasFirstPersonSubject(value)) {
      return const _EvidenceSubject(MemoryEvidenceSubjectType.user, null);
    }
    return const _EvidenceSubject(MemoryEvidenceSubjectType.unknown, null);
  }

  bool _isUnresolvedThirdParty(
    String value,
    MemoryEvidenceSubjectType subjectType,
  ) =>
      subjectType == MemoryEvidenceSubjectType.unresolvedThirdParty ||
      _hasReportedClaim(value);

  String? _extractCorrectionStatement(String raw) {
    final explicitCorrection = RegExp(
      r'^\s*(?:correction|corrige|modification)\b[\s,:;-]*(.+)$',
      caseSensitive: false,
      unicode: true,
    ).firstMatch(raw);
    if (explicitCorrection != null) {
      return _nonEmpty(explicitCorrection.group(1));
    }

    final transition = RegExp(
      r"\b(?:mais\s+(?:maintenant|désormais|desormais|aujourd’hui|aujourd'hui)|maintenant|désormais|desormais)\b[\s,:;-]*(.+)$",
      caseSensitive: false,
      unicode: true,
    ).firstMatch(raw);
    if (transition != null) {
      return _nonEmpty(transition.group(1));
    }

    final leadingCorrection = RegExp(
      r'^\s*(?:finalement|en\s+fait)\b[\s,:;-]*(.+)$',
      caseSensitive: false,
      unicode: true,
    ).firstMatch(raw);
    if (leadingCorrection != null) {
      return _nonEmpty(leadingCorrection.group(1));
    }

    final admittedError = RegExp(
      r'^\s*je\s+me\s+suis\s+tromp(?:é|ée|e|ee)\b[\s,:;-]*(.+)$',
      caseSensitive: false,
      unicode: true,
    ).firstMatch(raw);
    if (admittedError != null) {
      return _nonEmpty(admittedError.group(1));
    }

    final noLongerTrue = RegExp(
      r"^\s*ce\s+n[’']est\s+plus\s+vrai\b[\s,:;-]*(.+)$",
      caseSensitive: false,
      unicode: true,
    ).firstMatch(raw);
    return _nonEmpty(noLongerTrue?.group(1));
  }

  String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  bool _hasConditionalMarker(String value) => _hasPhrase(value, const [
        'si je devais',
        'si j avais',
        'je prefererais',
        'je pourrais',
        'j aimerais peut etre',
        'ce serait',
        'eventuellement',
        'au cas ou',
      ]);

  bool _hasHypothesisMarker(String value) => _hasPhrase(value, const [
        'supposons que',
        'imaginons que',
        'il se peut que',
      ]);

  bool _hasUncertaintyMarker(String value) => _hasPhrase(value, const [
        'peut etre',
        'peut etre que',
        'je crois',
        'je ne crois pas',
        'je pense que',
        'je ne pense pas que',
        'il est possible que',
        'c est possible que',
        'possible que',
        'il me semble',
        'il me semble que',
        'j ai l impression que',
        'probablement',
        'possiblement',
        'vraisemblablement',
        'a mon avis',
        'je suppose que',
        'je ne sais pas si',
        'sans doute',
        'en principe',
        'normalement',
      ]);

  bool _hasTemporaryMarker(String value) => _hasPhrase(value, const [
        'seulement cette semaine',
        'pour cette semaine',
        'aujourd hui exceptionnellement',
        'exceptionnellement aujourd hui',
        'temporairement',
        'pour quelques jours',
      ]);

  bool _hasPastOnlyMarker(String value) => _hasPhrase(value, const [
        'avant',
        'autrefois',
        'quand j habitais',
        'a l epoque',
        'je preferais',
        'j habitais',
      ]);

  bool _isNegatedPositiveClaim(String value) => _hasPhrase(value, const [
        'je ne prefere pas',
        'je n aime pas',
        'ce n est pas vrai que',
        'il est faux que',
      ]);

  bool _isDurableNegativeConstraint(String value) => _hasPhrase(value, const [
        'je ne peux jamais',
        'je ne suis jamais disponible',
        'je ne peux pas tous les',
        'je ne peux pas le',
        'je suis indisponible tous les',
      ]);

  bool _isRecognizedDirectStatement(String value) {
    if (_isDurableRelationshipFact(value)) return true;
    if (RegExp(
      r'\b(?:je\s+(?:prefere|aime|veux)|j\s+aime|'
      r'nous\s+(?:preferons|aimons|voulons))\s+\S+',
    ).hasMatch(value)) {
      return true;
    }
    if (RegExp(r'\b(?:prefere|aime|deteste)\s+\S+').hasMatch(value) &&
        _hasThirdPartySubject(value)) {
      return true;
    }
    if (_hasPhrase(value, const [
          'tous les jours',
          'toutes les semaines',
          'chaque semaine',
          'chaque mois',
          'tous les lundis',
          'tous les mardis',
          'tous les mercredis',
          'tous les jeudis',
          'tous les vendredis',
          'tous les samedis',
          'tous les dimanches',
        ]) &&
        _hasFirstPersonSubject(value)) {
      return true;
    }
    return RegExp(
      r'\b(?:mon|ma|notre)\s+(?:adresse|bureau|domicile)(?:\s+actuel(?:le)?)?\s+est\s+\S+',
    ).hasMatch(value);
  }

  bool _isRecognizedCorrectionStatement(String value) =>
      RegExp(
        r'\bje\s+(?:ne\s+)?(?:travaille|prefere|suis|habite|peux)\b(?:\s+\S+)+',
      ).hasMatch(value) ||
      RegExp(r'\bce\s+n\s+est\s+plus\s+(?:mon|ma|mes|notre|nos)\s+\S+')
          .hasMatch(value) ||
      _isRecognizedDirectStatement(value);

  bool _isNegativeCorrection(String value) =>
      RegExp(r'\bje\s+ne\s+\S+(?:\s+\S+)*\s+plus\b').hasMatch(value) ||
      _hasPhrase(value, const ['ce n est plus']);

  MemoryEvidenceQualification _unknown(
    MemoryEvidenceSubjectType subjectType,
    String? subjectEntityId, {
    bool isCorrection = false,
    required String reason,
    String? statementForMemory,
  }) =>
      MemoryEvidenceQualification(
        classification: MemoryEvidenceClassification.unknown,
        subjectType: subjectType,
        subjectEntityId: subjectEntityId,
        statementForMemory: statementForMemory,
        canConfirmImmediately: false,
        isCorrection: isCorrection,
        risks: {
          if (subjectType == MemoryEvidenceSubjectType.unknown)
            MemoryEvidenceRisk.unknownSubject,
        },
        reasonCodes: [reason],
      );

  MemoryEvidenceQualification _blocked(
    MemoryEvidenceClassification classification,
    MemoryEvidenceSubjectType subjectType,
    String? subjectEntityId,
    bool correction,
    MemoryEvidenceRisk risk,
    String reason, {
    String? statementForMemory,
  }) =>
      MemoryEvidenceQualification(
        classification: classification,
        subjectType: subjectType,
        subjectEntityId: subjectEntityId,
        statementForMemory: statementForMemory,
        canConfirmImmediately: false,
        isCorrection: correction,
        risks: {
          risk,
          if (subjectType == MemoryEvidenceSubjectType.unknown)
            MemoryEvidenceRisk.unknownSubject,
        },
        reasonCodes: [reason],
      );

  bool _hasFirstPersonSubject(String value) =>
      RegExp(r'(?:^| )(?:je|j|mon|ma|mes|nous|notre|nos)(?: |$)')
          .hasMatch(value);

  bool _isDurableRelationshipFact(String value) => RegExp(
        r'\b(?:anniversaire|date de naissance)\s+de\s+(?:ma|mon)\s+'
        r'(?:mere|pere|soeur|frere|fille|fils|conjointe?|partenaire|'
        r'grand mere|grand pere)\s+est\s+(?:le\s+)?\d{1,2}\s+'
        r'(?:janvier|fevrier|mars|avril|mai|juin|juillet|aout|septembre|'
        r'octobre|novembre|decembre)\b',
      ).hasMatch(value);

  bool _hasThirdPartySubject(String value) =>
      RegExp(r'^(?:il|elle|ils|elles)\b').hasMatch(value) &&
          !_hasPhrase(value, const [
            'il est possible que',
            'il se peut que',
            'il me semble',
          ]) ||
      _hasPhrase(value, const [
        'ma soeur',
        'mon frere',
        'ma mere',
        'mon pere',
        'mon conjoint',
        'ma conjointe',
        'mon enfant',
        'ma fille',
        'mon fils',
      ]);

  bool _hasReportedClaim(String value) =>
      RegExp(
        r'(?:^| )(?:il|elle|ils|elles)\s+(?:dit|disent|pense|pensent|affirme|affirment)\s+que(?: |$)',
      ).hasMatch(value) ||
      RegExp(
        r'(?:^| )(?:ma soeur|mon frere|ma mere|mon pere|mon conjoint|ma conjointe|mon enfant|ma fille|mon fils)\s+(?:dit|pense|affirme)\s+que(?: |$)',
      ).hasMatch(value) ||
      _hasPhrase(value, const ['selon']);

  bool _isQuestion(String value) => FrenchQuestionDetector.isQuestion(value);

  bool _isQuotation(String raw, String normalized) =>
      RegExp(r'["“”«»]').hasMatch(raw) ||
      _hasPhrase(normalized, const [
        'c est ce que j avais ecrit',
        'je cite',
        'citation',
      ]);

  bool _hasPhrase(String value, Iterable<String> phrases) => phrases.any(
        (phrase) => RegExp(
          '(?:^| )${RegExp.escape(phrase)}(?: |\$)',
        ).hasMatch(value),
      );

  String _normalize(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('’', "'")
      .replaceAll('œ', 'oe')
      .replaceAll(RegExp(r"[^a-z0-9àâäéèêëîïôöùûüç']+"), ' ')
      .replaceAll("'", ' ')
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
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

final class _EvidenceSubject {
  const _EvidenceSubject(this.type, this.id);

  final MemoryEvidenceSubjectType type;
  final String? id;

  bool get isAttributable =>
      type == MemoryEvidenceSubjectType.user ||
      type == MemoryEvidenceSubjectType.structuredEntity;
}
