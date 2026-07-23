import 'dart:collection';

import 'conversation_context_envelope.dart';

enum ConversationEpistemicState {
  grounded,
  groundedPartial,
  uncertain,
  conflicting,
  stale,
  contextUnavailable,
  insufficientInformation,
  unsupported,
  invalid,
}

enum ConversationResponseKind {
  answer,
  answerWithCaveat,
  clarificationRequired,
  confirmationRequired,
  actionProposal,
  actionResult,
  cannotDetermine,
  contextUnavailable,
  unsupportedRequest,
  safeFailure,
}

enum ConversationConfidenceLevel { high, medium, low, unavailable }

enum ConversationGroundingSourceType {
  currentUserMessage,
  validatedHistoryMessage,
  lifeContextHuman,
  lifeContextIdentity,
  lifeContextEvent,
  lifeContextTask,
  lifeContextRoutine,
  lifeContextMemory,
  lifeContextRelation,
  confirmedClarification,
  confirmedActionResult,
  generalKnowledge,
}

enum ConversationPersonalClaimCategory {
  humanFact,
  eventFact,
  taskFact,
  routineFact,
  memoryFact,
  relationshipFact,
  actionResultFact,
}

enum ConversationMissingInformationCode {
  missingDate,
  missingTime,
  missingDuration,
  missingTravelOutbound,
  missingTravelReturn,
  missingDeadline,
  missingTaskTarget,
  missingPerson,
  missingHousehold,
  missingResidence,
  missingConfirmation,
  missingChoice,
  missingActionType,
  missingContext,
  missingCurrentValue,
}

enum ConversationContradictionType {
  twoConfirmedValues,
  localVsCloud,
  currentVsHistorical,
  userMessageVsStoredContext,
  clarificationVsStoredContext,
  actionResultVsPendingState,
  staleVsCurrent,
  unsupportedCombination,
}

enum ConversationClarificationAnswerType {
  freeTextBounded,
  yesNo,
  date,
  time,
  duration,
  choice,
  personChoice,
  locationChoice,
  confirmation,
}

enum ConversationClarificationDecision {
  answer,
  answerWithCaveat,
  clarify,
  refuseAction,
  cannotDetermine,
  retryContext,
}

enum ConversationUncertaintyCode {
  partialContext,
  staleSource,
  unavailableSource,
  unconfirmedSource,
  conflictingSources,
  missingRequiredInformation,
  clarificationLimitReached,
  groundingUnavailable,
}

abstract final class ConversationEpistemicRegistry {
  static const int currentVersion = 1;
}

final class ConversationGroundingReference {
  static const int currentSchemaVersion = 1;

  const ConversationGroundingReference({
    this.schemaVersion = currentSchemaVersion,
    required this.sourceType,
    this.section,
    this.factKey,
    required this.freshness,
    required this.confirmation,
    required this.projectionVersion,
  });

  final int schemaVersion;
  final ConversationGroundingSourceType sourceType;
  final String? section;
  final String? factKey;
  final String freshness;
  final String confirmation;
  final int projectionVersion;

  bool existsIn(ConversationContextEnvelope envelope) {
    if (schemaVersion != currentSchemaVersion) return false;
    if (sourceType == ConversationGroundingSourceType.currentUserMessage ||
        sourceType == ConversationGroundingSourceType.validatedHistoryMessage ||
        sourceType == ConversationGroundingSourceType.confirmedClarification ||
        sourceType == ConversationGroundingSourceType.confirmedActionResult ||
        sourceType == ConversationGroundingSourceType.generalKnowledge) {
      return section == null && factKey == null;
    }
    if (projectionVersion != envelope.projectionVersion ||
        section == null ||
        factKey == null) {
      return false;
    }
    return envelope.sections.any(
      (candidate) =>
          candidate.type == section &&
          candidate.availability != 'unavailable' &&
          candidate.items.any((item) => item.facts.containsKey(factKey)),
    );
  }

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'sourceType': sourceType.name,
        'section': section,
        'factKey': factKey,
        'freshness': freshness,
        'confirmation': confirmation,
        'projectionVersion': projectionVersion,
      };
}

final class ConversationPersonalClaim {
  static const int maximumReferences = 3;

  ConversationPersonalClaim({
    required this.claimId,
    required this.category,
    required List<int> sourceReferenceIndexes,
    required this.certainty,
  }) : sourceReferenceIndexes =
            UnmodifiableListView(sourceReferenceIndexes.toList()..sort()) {
    if (claimId.trim().isEmpty ||
        this.sourceReferenceIndexes.isEmpty ||
        this.sourceReferenceIndexes.length > maximumReferences ||
        this.sourceReferenceIndexes.any((index) => index < 0)) {
      throw const FormatException('invalid_conversation_personal_claim');
    }
  }

  final String claimId;
  final ConversationPersonalClaimCategory category;
  final List<int> sourceReferenceIndexes;
  final ConversationEpistemicState certainty;

  Map<String, Object> toJson() => {
        'claimId': claimId,
        'category': category.name,
        'sourceReferenceIndexes': sourceReferenceIndexes,
        'certainty': certainty.name,
      };
}

final class ConversationMissingInformation {
  static const int currentSchemaVersion = 1;

  const ConversationMissingInformation({
    this.schemaVersion = currentSchemaVersion,
    required this.code,
    required this.domain,
    required this.field,
    required this.isRequired,
    required this.canClarify,
  });

  final int schemaVersion;
  final ConversationMissingInformationCode code;
  final String domain;
  final String field;
  final bool isRequired;
  final bool canClarify;

  Map<String, Object> toJson() => {
        'schemaVersion': schemaVersion,
        'code': code.name,
        'domain': domain,
        'field': field,
        'isRequired': isRequired,
        'canClarify': canClarify,
      };
}

final class ConversationContradiction {
  static const int currentSchemaVersion = 1;

  const ConversationContradiction({
    this.schemaVersion = currentSchemaVersion,
    required this.type,
    required this.domain,
    required this.field,
    required this.requiresClarification,
    required this.blocksAction,
    required this.code,
  });

  final int schemaVersion;
  final ConversationContradictionType type;
  final String domain;
  final String field;
  final bool requiresClarification;
  final bool blocksAction;
  final String code;

  Map<String, Object> toJson() => {
        'schemaVersion': schemaVersion,
        'type': type.name,
        'domain': domain,
        'field': field,
        'requiresClarification': requiresClarification,
        'blocksAction': blocksAction,
        'code': code,
      };
}

final class ConversationClarification {
  static const int currentSchemaVersion = 1;
  static const int maximumQuestionCharacters = 240;
  static const int maximumChoices = 6;
  static const int maximumAttempts = 3;

  ConversationClarification({
    this.schemaVersion = currentSchemaVersion,
    required this.clarificationId,
    required this.reasonCode,
    required String questionText,
    required this.expectedAnswerType,
    required List<String> allowedChoices,
    required List<ConversationMissingInformationCode> missingFieldCodes,
    required this.createdAt,
    this.expiresAt,
    required this.attemptNumber,
    required this.sessionGeneration,
  })  : questionText = questionText.trim(),
        allowedChoices = UnmodifiableListView(allowedChoices),
        missingFieldCodes = UnmodifiableListView(missingFieldCodes) {
    if (schemaVersion != currentSchemaVersion ||
        clarificationId.trim().isEmpty ||
        reasonCode.trim().isEmpty ||
        this.questionText.isEmpty ||
        this.questionText.length > maximumQuestionCharacters ||
        this.allowedChoices.length > maximumChoices ||
        this.missingFieldCodes.isEmpty ||
        attemptNumber < 1 ||
        attemptNumber > maximumAttempts ||
        sessionGeneration < 0 ||
        (expiresAt != null && !expiresAt!.isAfter(createdAt))) {
      throw const FormatException('invalid_conversation_clarification');
    }
  }

  final int schemaVersion;
  final String clarificationId;
  final String reasonCode;
  final String questionText;
  final ConversationClarificationAnswerType expectedAnswerType;
  final List<String> allowedChoices;
  final List<ConversationMissingInformationCode> missingFieldCodes;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final int attemptNumber;
  final int sessionGeneration;

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'clarificationId': clarificationId,
        'reasonCode': reasonCode,
        'questionText': questionText,
        'expectedAnswerType': expectedAnswerType.name,
        'allowedChoices': allowedChoices,
        'missingFieldCodes':
            missingFieldCodes.map((value) => value.name).toList(),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'expiresAt': expiresAt?.toUtc().toIso8601String(),
        'attemptNumber': attemptNumber,
        'maximumAttempts': maximumAttempts,
        'sessionGeneration': sessionGeneration,
      };
}

final class ConversationEpistemicContract {
  static const int currentSchemaVersion =
      ConversationEpistemicRegistry.currentVersion;
  static const int maximumGroundingReferences = 20;
  static const int maximumClaims = 10;
  static const int maximumMissingInformation = 10;
  static const int maximumContradictions = 6;

  ConversationEpistemicContract({
    this.schemaVersion = currentSchemaVersion,
    required this.responseKind,
    required this.epistemicState,
    required this.confidenceLevel,
    required List<ConversationGroundingSourceType> usedSourceTypes,
    required List<ConversationGroundingReference> groundingReferences,
    required List<ConversationPersonalClaim> personalClaims,
    required List<ConversationMissingInformation> missingInformation,
    required List<ConversationContradiction> contradictions,
    this.clarification,
    required List<ConversationUncertaintyCode> uncertaintyCodes,
    required this.contextStateObserved,
    required List<String> warningCodes,
    required this.responseId,
  })  : usedSourceTypes = UnmodifiableListView(usedSourceTypes),
        groundingReferences = UnmodifiableListView(groundingReferences),
        personalClaims = UnmodifiableListView(personalClaims),
        missingInformation = UnmodifiableListView(missingInformation),
        contradictions = UnmodifiableListView(contradictions),
        uncertaintyCodes = UnmodifiableListView(uncertaintyCodes),
        warningCodes = UnmodifiableListView(warningCodes) {
    if (schemaVersion != currentSchemaVersion ||
        responseId.trim().isEmpty ||
        this.groundingReferences.length > maximumGroundingReferences ||
        this.personalClaims.length > maximumClaims ||
        this.missingInformation.length > maximumMissingInformation ||
        this.contradictions.length > maximumContradictions) {
      throw const FormatException('invalid_conversation_epistemic_contract');
    }
  }

  factory ConversationEpistemicContract.fromJson(Map<String, dynamic> json) {
    const contractKeys = {
      'schemaVersion',
      'responseKind',
      'epistemicState',
      'confidenceLevel',
      'usedSourceTypes',
      'groundingReferences',
      'personalClaims',
      'missingInformation',
      'contradictions',
      'clarification',
      'uncertaintyCodes',
      'contextStateObserved',
      'warningCodes',
      'responseId',
    };
    if (json.length != contractKeys.length ||
        !contractKeys.containsAll(json.keys)) {
      throw const FormatException('unknown_conversation_epistemic_field');
    }
    T parsed<T extends Enum>(List<T> values, Object? raw, String code) =>
        values.firstWhere(
          (value) => value.name == raw,
          orElse: () => throw FormatException(code),
        );

    final rawReferences = json['groundingReferences'];
    final rawClaims = json['personalClaims'];
    final rawMissing = json['missingInformation'];
    final rawContradictions = json['contradictions'];
    if (rawReferences is! List ||
        rawClaims is! List ||
        rawMissing is! List ||
        rawContradictions is! List ||
        json['usedSourceTypes'] is! List ||
        json['uncertaintyCodes'] is! List ||
        json['warningCodes'] is! List) {
      throw const FormatException('invalid_conversation_epistemic_lists');
    }
    Map<String, dynamic> record(Object? value) {
      if (value is! Map) {
        throw const FormatException('invalid_conversation_epistemic_record');
      }
      return Map<String, dynamic>.from(value);
    }

    void exact(
      Map<String, dynamic> value,
      Set<String> expected,
      String code,
    ) {
      if (value.length != expected.length ||
          !expected.containsAll(value.keys)) {
        throw FormatException(code);
      }
    }

    final references = rawReferences.map((value) {
      final item = record(value);
      exact(
          item,
          const {
            'schemaVersion',
            'sourceType',
            'section',
            'factKey',
            'freshness',
            'confirmation',
            'projectionVersion',
          },
          'unknown_grounding_reference_field');
      return ConversationGroundingReference(
        schemaVersion: item['schemaVersion'] as int? ?? 0,
        sourceType: parsed(
          ConversationGroundingSourceType.values,
          item['sourceType'],
          'unknown_grounding_source',
        ),
        section: item['section'] as String?,
        factKey: item['factKey'] as String?,
        freshness: item['freshness'] as String? ?? '',
        confirmation: item['confirmation'] as String? ?? '',
        projectionVersion: item['projectionVersion'] as int? ?? -1,
      );
    }).toList();
    final clarificationJson = json['clarification'];
    final clarification = clarificationJson == null
        ? null
        : (() {
            final item = record(clarificationJson);
            exact(
                item,
                const {
                  'schemaVersion',
                  'clarificationId',
                  'reasonCode',
                  'questionText',
                  'expectedAnswerType',
                  'allowedChoices',
                  'missingFieldCodes',
                  'createdAt',
                  'expiresAt',
                  'attemptNumber',
                  'maximumAttempts',
                  'sessionGeneration',
                },
                'unknown_clarification_field');
            if (item['maximumAttempts'] !=
                ConversationClarification.maximumAttempts) {
              throw const FormatException(
                'invalid_clarification_attempt_limit',
              );
            }
            return ConversationClarification(
              schemaVersion: item['schemaVersion'] as int? ?? 0,
              clarificationId: item['clarificationId'] as String? ?? '',
              reasonCode: item['reasonCode'] as String? ?? '',
              questionText: item['questionText'] as String? ?? '',
              expectedAnswerType: parsed(
                ConversationClarificationAnswerType.values,
                item['expectedAnswerType'],
                'unknown_clarification_answer_type',
              ),
              allowedChoices: List<String>.from(
                  item['allowedChoices'] as List? ?? const []),
              missingFieldCodes:
                  (item['missingFieldCodes'] as List? ?? const [])
                      .map(
                        (value) => parsed(
                          ConversationMissingInformationCode.values,
                          value,
                          'unknown_missing_information_code',
                        ),
                      )
                      .toList(),
              createdAt: DateTime.parse(item['createdAt'] as String).toUtc(),
              expiresAt: item['expiresAt'] == null
                  ? null
                  : DateTime.parse(item['expiresAt'] as String).toUtc(),
              attemptNumber: item['attemptNumber'] as int? ?? 0,
              sessionGeneration: item['sessionGeneration'] as int? ?? -1,
            );
          })();
    return ConversationEpistemicContract(
      schemaVersion: json['schemaVersion'] as int? ?? 0,
      responseKind: parsed(
        ConversationResponseKind.values,
        json['responseKind'],
        'unknown_conversation_response_kind',
      ),
      epistemicState: parsed(
        ConversationEpistemicState.values,
        json['epistemicState'],
        'unknown_epistemic_state',
      ),
      confidenceLevel: parsed(
        ConversationConfidenceLevel.values,
        json['confidenceLevel'],
        'unknown_confidence_level',
      ),
      usedSourceTypes: (json['usedSourceTypes'] as List)
          .map(
            (value) => parsed(
              ConversationGroundingSourceType.values,
              value,
              'unknown_grounding_source',
            ),
          )
          .toList(),
      groundingReferences: references,
      personalClaims: rawClaims.map((value) {
        final item = record(value);
        exact(
            item,
            const {
              'claimId',
              'category',
              'sourceReferenceIndexes',
              'certainty',
            },
            'unknown_personal_claim_field');
        return ConversationPersonalClaim(
          claimId: item['claimId'] as String? ?? '',
          category: parsed(
            ConversationPersonalClaimCategory.values,
            item['category'],
            'unknown_personal_claim_category',
          ),
          sourceReferenceIndexes: List<int>.from(
              item['sourceReferenceIndexes'] as List? ?? const []),
          certainty: parsed(
            ConversationEpistemicState.values,
            item['certainty'],
            'unknown_claim_certainty',
          ),
        );
      }).toList(),
      missingInformation: rawMissing.map((value) {
        final item = record(value);
        exact(
            item,
            const {
              'schemaVersion',
              'code',
              'domain',
              'field',
              'isRequired',
              'canClarify',
            },
            'unknown_missing_information_field');
        if (item['schemaVersion'] !=
            ConversationMissingInformation.currentSchemaVersion) {
          throw const FormatException('unknown_missing_information_version');
        }
        return ConversationMissingInformation(
          schemaVersion: item['schemaVersion'] as int? ?? 0,
          code: parsed(
            ConversationMissingInformationCode.values,
            item['code'],
            'unknown_missing_information_code',
          ),
          domain: item['domain'] as String? ?? '',
          field: item['field'] as String? ?? '',
          isRequired: item['isRequired'] == true,
          canClarify: item['canClarify'] == true,
        );
      }).toList(),
      contradictions: rawContradictions.map((value) {
        final item = record(value);
        exact(
            item,
            const {
              'schemaVersion',
              'type',
              'domain',
              'field',
              'requiresClarification',
              'blocksAction',
              'code',
            },
            'unknown_contradiction_field');
        if (item['schemaVersion'] !=
            ConversationContradiction.currentSchemaVersion) {
          throw const FormatException('unknown_contradiction_version');
        }
        return ConversationContradiction(
          schemaVersion: item['schemaVersion'] as int? ?? 0,
          type: parsed(
            ConversationContradictionType.values,
            item['type'],
            'unknown_contradiction_type',
          ),
          domain: item['domain'] as String? ?? '',
          field: item['field'] as String? ?? '',
          requiresClarification: item['requiresClarification'] == true,
          blocksAction: item['blocksAction'] == true,
          code: item['code'] as String? ?? '',
        );
      }).toList(),
      clarification: clarification,
      uncertaintyCodes: (json['uncertaintyCodes'] as List)
          .map(
            (value) => parsed(
              ConversationUncertaintyCode.values,
              value,
              'unknown_uncertainty_code',
            ),
          )
          .toList(),
      contextStateObserved: parsed(
        ConversationContextState.values,
        json['contextStateObserved'],
        'unknown_context_state',
      ),
      warningCodes: List<String>.from(json['warningCodes'] as List),
      responseId: json['responseId'] as String? ?? '',
    );
  }

  factory ConversationEpistemicContract.legacySafe({
    required bool hasActions,
  }) =>
      ConversationEpistemicContract(
        responseKind: hasActions
            ? ConversationResponseKind.actionProposal
            : ConversationResponseKind.answer,
        epistemicState: ConversationEpistemicState.grounded,
        confidenceLevel: ConversationConfidenceLevel.high,
        usedSourceTypes: const [
          ConversationGroundingSourceType.currentUserMessage,
        ],
        groundingReferences: const [
          ConversationGroundingReference(
            sourceType: ConversationGroundingSourceType.currentUserMessage,
            freshness: 'current',
            confirmation: 'confirmed',
            projectionVersion: 0,
          ),
        ],
        personalClaims: const [],
        missingInformation: const [],
        contradictions: const [],
        uncertaintyCodes: const [],
        contextStateObserved: ConversationContextState.complete,
        warningCodes: const [],
        responseId: 'legacy-safe-response',
      );

  final int schemaVersion;
  final ConversationResponseKind responseKind;
  final ConversationEpistemicState epistemicState;
  final ConversationConfidenceLevel confidenceLevel;
  final List<ConversationGroundingSourceType> usedSourceTypes;
  final List<ConversationGroundingReference> groundingReferences;
  final List<ConversationPersonalClaim> personalClaims;
  final List<ConversationMissingInformation> missingInformation;
  final List<ConversationContradiction> contradictions;
  final ConversationClarification? clarification;
  final List<ConversationUncertaintyCode> uncertaintyCodes;
  final ConversationContextState contextStateObserved;
  final List<String> warningCodes;
  final String responseId;

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'responseKind': responseKind.name,
        'epistemicState': epistemicState.name,
        'confidenceLevel': confidenceLevel.name,
        'usedSourceTypes': usedSourceTypes.map((value) => value.name).toList(),
        'groundingReferences':
            groundingReferences.map((value) => value.toJson()).toList(),
        'personalClaims':
            personalClaims.map((value) => value.toJson()).toList(),
        'missingInformation':
            missingInformation.map((value) => value.toJson()).toList(),
        'contradictions':
            contradictions.map((value) => value.toJson()).toList(),
        'clarification': clarification?.toJson(),
        'uncertaintyCodes':
            uncertaintyCodes.map((value) => value.name).toList(),
        'contextStateObserved': contextStateObserved.name,
        'warningCodes': warningCodes,
        'responseId': responseId,
      };
}
