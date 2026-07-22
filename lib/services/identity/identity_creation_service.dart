import '../../core/identity/entity_id_generator.dart';
import '../../core/identity/entity_normalizer.dart';
import '../../core/identity/entity_types.dart';
import '../../core/identity/life_entity.dart';
import '../../models/conversation_models.dart';
import '../../repositories/identity/identity_read_repository.dart';
import '../../repositories/identity/identity_repository_query.dart';
import '../../repositories/identity/identity_write_repository.dart';
import '../conversation_answer_classifier.dart';
import 'identity_application_models.dart';

final class IdentityCreationRequest {
  final IdentityAccountScope scope;
  final EntityType entityType;
  final String canonicalLabel;
  final EntitySource source;

  IdentityCreationRequest({
    required this.scope,
    required this.entityType,
    required String canonicalLabel,
    required this.source,
  }) : canonicalLabel =
            EntityNormalizer.normalize(canonicalLabel).displayValue {
    if (entityType == EntityType.unknown ||
        source.type == EntitySourceType.unknown ||
        this.canonicalLabel.isEmpty) {
      throw const ConversationIdentityException('invalid_creation_request');
    }
  }
}

final class IdentityCreationService {
  static const Duration defaultValidity = Duration(minutes: 15);

  final IdentityReadRepository _readRepository;
  final IdentityWriteRepository _writeRepository;
  final EntityIdGenerator _idGenerator;
  final ConversationAnswerClassifier _answerClassifier;
  final DateTime Function() _now;
  final Duration _validity;

  IdentityCreationService({
    required IdentityReadRepository readRepository,
    required IdentityWriteRepository writeRepository,
    required EntityIdGenerator idGenerator,
    ConversationAnswerClassifier answerClassifier =
        const ConversationAnswerClassifier(),
    DateTime Function()? now,
    Duration validity = defaultValidity,
  })  : _readRepository = readRepository,
        _writeRepository = writeRepository,
        _idGenerator = idGenerator,
        _answerClassifier = answerClassifier,
        _now = now ?? DateTime.now,
        _validity = validity {
    if (validity <= Duration.zero) {
      throw const ConversationIdentityException('invalid_creation_validity');
    }
  }

  PendingIdentityCreation propose({
    required IdentityApplicationResult applicationResult,
    required IdentityCreationRequest request,
  }) {
    if (applicationResult.status != IdentityApplicationStatus.notFound) {
      throw const ConversationIdentityException(
        'creation_requires_not_found_result',
      );
    }
    final createdAt = _now().toUtc();
    return PendingIdentityCreation(
      proposalId: _idGenerator.generate(),
      entityId: _idGenerator.generate(),
      entityType: request.entityType,
      canonicalLabel: request.canonicalLabel,
      source: request.source,
      createdAt: createdAt,
      expiresAt: createdAt.add(_validity),
      accountScopeId: request.scope.accountId,
    );
  }

  String question(PendingIdentityCreation pending) =>
      'Veux-tu enregistrer «${pending.canonicalLabel}» comme identité '
      'de type ${_typeLabel(pending.entityType)} ?';

  Future<IdentityCreationResult> process({
    required PendingIdentityCreation pending,
    required String answer,
    DateTime? referenceDate,
  }) async {
    final evaluatedAt = (referenceDate ?? _now()).toUtc();
    if (pending.isExpiredAt(evaluatedAt)) {
      return _result(
        pending,
        IdentityCreationStatus.expired,
        'identity_creation_expired',
        'Cette proposition a expiré. Aucune identité n’a été enregistrée.',
      );
    }
    final answerType = _answerClassifier.classify(answer);
    if (answerType == ConversationAnswer.ambiguous) {
      return _result(
        pending,
        IdentityCreationStatus.stillPending,
        'identity_creation_confirmation_required',
        'Réponds explicitement par oui ou non.',
      );
    }
    if (answerType == ConversationAnswer.negative) {
      return _result(
        pending,
        IdentityCreationStatus.cancelled,
        'identity_creation_cancelled',
        'D’accord, aucune identité n’a été enregistrée.',
      );
    }

    final scope = IdentityAccountScope(pending.accountScopeId);
    try {
      if (await _readRepository.findById(
            scope: scope,
            entityId: pending.entityId,
          ) !=
          null) {
        return _alreadyExists(pending);
      }
      final candidates = await _readRepository.queryCandidates(
        scope: scope,
        query: IdentityRepositoryQuery.byComparisonKey(
          comparisonKey: pending.canonicalLabel,
          expectedType: pending.entityType,
          includeInactive: true,
          includeMerged: true,
          includeDeleted: true,
        ),
      );
      if (candidates.entities.isNotEmpty || candidates.limitReached) {
        return _alreadyExists(pending);
      }

      final entity = LifeEntity.fromLabel(
        id: pending.entityId,
        type: pending.entityType,
        canonicalLabel: pending.canonicalLabel,
        source: pending.source,
        createdAt: evaluatedAt,
        updatedAt: evaluatedAt,
      );
      final created = await _writeRepository.create(
        scope: scope,
        entity: entity,
      );
      return IdentityCreationResult(
        status: IdentityCreationStatus.created,
        proposalId: pending.proposalId,
        createdEntityId: created.entity.id,
        diagnosticCode: 'identity_created',
        followUpMessage: 'L’identité a bien été enregistrée.',
      );
    } on IdentityRepositoryException catch (error) {
      if (error.code == 'identity_already_exists') {
        return _alreadyExists(pending);
      }
      return _result(
        pending,
        IdentityCreationStatus.repositoryFailure,
        'identity_creation_repository_failure',
        'Je n’ai pas pu enregistrer cette identité. Tu peux réessayer.',
      );
    } on EntityDomainException {
      return _result(
        pending,
        IdentityCreationStatus.invalid,
        'identity_creation_invalid',
        'Cette identité ne peut pas être enregistrée.',
      );
    }
  }

  IdentityCreationResult _alreadyExists(PendingIdentityCreation pending) =>
      _result(
        pending,
        IdentityCreationStatus.alreadyExists,
        'identity_creation_duplicate',
        'Une identité équivalente existe déjà. Rien n’a été créé.',
      );

  IdentityCreationResult _result(
    PendingIdentityCreation pending,
    IdentityCreationStatus status,
    String diagnosticCode,
    String message,
  ) =>
      IdentityCreationResult(
        status: status,
        proposalId: pending.proposalId,
        diagnosticCode: diagnosticCode,
        followUpMessage: message,
      );
}

String _typeLabel(EntityType type) => switch (type) {
      EntityType.person => 'personne',
      EntityType.place => 'lieu',
      EntityType.organization => 'organisation',
      EntityType.household => 'foyer',
      EntityType.group => 'groupe',
      EntityType.activity => 'activité',
      EntityType.vehicle => 'véhicule',
      EntityType.pet => 'animal',
      EntityType.product => 'produit',
      EntityType.unknown => 'inconnu',
    };
