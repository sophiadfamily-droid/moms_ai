import '../../core/identity/entity_id_generator.dart';
import '../../core/identity/entity_normalizer.dart';
import '../../models/conversation_models.dart';
import '../conversation_answer_classifier.dart';
import 'identity_application_models.dart';

final class IdentityClarificationService {
  static const Duration defaultValidity = Duration(minutes: 15);

  final EntityIdGenerator _idGenerator;
  final ConversationAnswerClassifier _answerClassifier;
  final DateTime Function() _now;
  final Duration _validity;

  IdentityClarificationService({
    required EntityIdGenerator idGenerator,
    ConversationAnswerClassifier answerClassifier =
        const ConversationAnswerClassifier(),
    DateTime Function()? now,
    Duration validity = defaultValidity,
  })  : _idGenerator = idGenerator,
        _answerClassifier = answerClassifier,
        _now = now ?? DateTime.now,
        _validity = validity {
    if (validity <= Duration.zero) {
      throw const ConversationIdentityException(
        'invalid_clarification_validity',
      );
    }
  }

  PendingIdentityClarification create({
    required IdentityApplicationResult applicationResult,
    required IdentityResolutionRequest request,
  }) {
    if (applicationResult.status != IdentityApplicationStatus.ambiguous &&
        applicationResult.status !=
            IdentityApplicationStatus.needsConfirmation) {
      throw const ConversationIdentityException(
        'clarification_requires_unresolved_candidates',
      );
    }
    final choices = applicationResult.candidates
        .map(
          (candidate) => IdentityClarificationChoice(
            entityId: candidate.entity.id,
            type: candidate.entity.type,
            displayLabel: candidate.entity.canonicalLabel,
          ),
        )
        .toList(growable: false)
      ..sort(_compareChoices);
    final createdAt = _now().toUtc();
    return PendingIdentityClarification(
      clarificationId: _idGenerator.generate(),
      reference: request.reference,
      candidateChoices: choices,
      createdAt: createdAt,
      expiresAt: createdAt.add(_validity),
      accountScopeId: request.scope.accountId,
    );
  }

  String question(PendingIdentityClarification pending) {
    final reference = pending.reference.rawValue?.trim();
    final subject = reference == null || reference.isEmpty
        ? 'cette référence'
        : '« $reference »';
    final choices = <String>[
      for (var index = 0; index < pending.candidateChoices.length; index++)
        '${index + 1}. ${pending.candidateChoices[index].displayLabel}',
    ];
    if (pending.candidateChoices.length == 1) {
      return [
        'Je dois confirmer l’identité correspondant à $subject.',
        'Est-ce bien celle-ci ?',
        ...choices,
      ].join('\n');
    }
    return [
      'J’ai trouvé plusieurs identités correspondant à $subject.',
      'De laquelle parles-tu ?',
      ...choices,
    ].join('\n');
  }

  IdentityClarificationResult process({
    required PendingIdentityClarification pending,
    required String answer,
    DateTime? referenceDate,
  }) {
    final evaluatedAt = (referenceDate ?? _now()).toUtc();
    if (pending.isExpiredAt(evaluatedAt)) {
      return _result(
        pending,
        IdentityClarificationStatus.expired,
        'clarification_expired',
        'Cette clarification a expiré. Tu peux reformuler ta demande.',
      );
    }
    final normalized = _normalize(answer);
    if (_isCancellation(normalized)) {
      return _result(
        pending,
        IdentityClarificationStatus.cancelled,
        'clarification_cancelled',
        'D’accord, j’annule cette clarification.',
      );
    }
    final selected = _explicitSelection(pending, normalized);
    if (selected != null) {
      return IdentityClarificationResult(
        status: IdentityClarificationStatus.resolved,
        resolvedEntityId: selected.entityId,
        clarificationId: pending.clarificationId,
        diagnosticCode: 'clarification_resolved',
        followUpMessage: 'Merci, l’identité est maintenant clarifiée.',
      );
    }
    return _result(
      pending,
      IdentityClarificationStatus.stillAmbiguous,
      'clarification_still_ambiguous',
      'Je n’ai pas pu identifier un choix unique. Réponds avec son numéro.',
    );
  }

  IdentityClarificationChoice? _explicitSelection(
    PendingIdentityClarification pending,
    String answer,
  ) {
    if (pending.candidateChoices.length == 1 &&
        _answerClassifier.classify(answer) == ConversationAnswer.positive) {
      return pending.candidateChoices.single;
    }
    final index = _choiceIndex(answer);
    if (index != null) {
      return index >= 0 && index < pending.candidateChoices.length
          ? pending.candidateChoices[index]
          : null;
    }
    final key = EntityNormalizer.comparisonKey(answer);
    if (key.isEmpty) return null;
    final matches = pending.candidateChoices
        .where(
          (choice) =>
              EntityNormalizer.comparisonKey(choice.displayLabel) == key,
        )
        .toList(growable: false);
    return matches.length == 1 ? matches.single : null;
  }

  int? _choiceIndex(String answer) {
    final numeric =
        RegExp(r'^(?:(?:le|la)\s+)?(\d+)(?:er|e|eme)?$').firstMatch(answer);
    if (numeric != null) return int.parse(numeric.group(1)!) - 1;
    const ordinals = <String, int>{
      'premier': 0,
      'premiere': 0,
      'le premier': 0,
      'la premiere': 0,
      'second': 1,
      'seconde': 1,
      'deuxieme': 1,
      'le second': 1,
      'la seconde': 1,
      'le deuxieme': 1,
      'la deuxieme': 1,
    };
    return ordinals[answer];
  }

  bool _isCancellation(String answer) {
    if (const {'aucun', 'aucune', 'annule', 'annuler'}.contains(answer)) {
      return true;
    }
    return _answerClassifier.classify(answer) == ConversationAnswer.negative;
  }

  IdentityClarificationResult _result(
    PendingIdentityClarification pending,
    IdentityClarificationStatus status,
    String diagnosticCode,
    String message,
  ) {
    return IdentityClarificationResult(
      status: status,
      clarificationId: pending.clarificationId,
      diagnosticCode: diagnosticCode,
      followUpMessage: message,
    );
  }

  String _normalize(String value) => EntityNormalizer.comparisonKey(value)
      .replaceAll(RegExp(r'[.!?;,]+$'), '')
      .trim();
}

int _compareChoices(
  IdentityClarificationChoice first,
  IdentityClarificationChoice second,
) {
  final type = first.type.index.compareTo(second.type.index);
  if (type != 0) return type;
  final label = EntityNormalizer.comparisonKey(first.displayLabel)
      .compareTo(EntityNormalizer.comparisonKey(second.displayLabel));
  if (label != 0) return label;
  return first.entityId.compareTo(second.entityId);
}
