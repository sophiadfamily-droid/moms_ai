import 'dart:collection';

import '../../core/identity/entity_identity.dart';
import '../../core/identity/entity_types.dart';
import '../../core/identity/persisted_identity_link.dart';

final class HumanModelException implements Exception {
  const HumanModelException(this.code);

  final String code;

  @override
  String toString() => 'HumanModelException($code)';
}

enum HumanInformationSource {
  explicitUserInput,
  legacyProfile,
  zeliaProposal,
  imported,
  calculated,
  unknown,
}

enum HumanConfirmationStatus {
  confirmed,
  proposed,
  inferred,
  needsConfirmation,
  rejected,
  historical,
}

enum HumanPersonStatus { active, historical, absent, deceased }

enum HumanRecordStatus { active, ended, historical, uncertain }

enum HouseholdStatus { primary, secondary, temporary, historical }

enum ResidenceStatus { primary, secondary, temporary, historical }

final class HumanEvidence {
  const HumanEvidence({
    required this.source,
    required this.confirmation,
  });

  final HumanInformationSource source;
  final HumanConfirmationStatus confirmation;

  Map<String, Object?> toJson() => {
        'source': source.name,
        'confirmation': confirmation.name,
      };

  factory HumanEvidence.fromJson(Object? value) {
    final map = _stringMap(value, 'invalid_human_evidence');
    return HumanEvidence(
      source: _enumValue(
        HumanInformationSource.values,
        map['source'],
        'invalid_human_information_source',
      ),
      confirmation: _enumValue(
        HumanConfirmationStatus.values,
        map['confirmation'],
        'invalid_human_confirmation_status',
      ),
    );
  }
}

final class HumanValidityPeriod {
  const HumanValidityPeriod({this.validFrom, this.validUntil});

  final DateTime? validFrom;
  final DateTime? validUntil;

  void validate() {
    if (validFrom != null &&
        validUntil != null &&
        validUntil!.isBefore(validFrom!)) {
      throw const HumanModelException('invalid_human_validity_period');
    }
  }

  bool isActiveAt(DateTime instant) {
    validate();
    if (validFrom != null && instant.isBefore(validFrom!)) return false;
    if (validUntil != null && instant.isAfter(validUntil!)) return false;
    return true;
  }

  Map<String, Object?> toJson() => {
        'validFrom': validFrom?.toUtc().toIso8601String(),
        'validUntil': validUntil?.toUtc().toIso8601String(),
      };

  factory HumanValidityPeriod.fromJson(Object? value) {
    if (value == null) return const HumanValidityPeriod();
    final map = _stringMap(value, 'invalid_human_validity_period');
    final result = HumanValidityPeriod(
      validFrom: _optionalDate(map['validFrom']),
      validUntil: _optionalDate(map['validUntil']),
    );
    result.validate();
    return result;
  }
}

abstract final class HumanRelationshipTypes {
  static const partner = 'partner';
  static const spouse = 'spouse';
  static const formerPartner = 'formerPartner';
  static const parent = 'parent';
  static const child = 'child';
  static const sibling = 'sibling';
  static const halfSibling = 'halfSibling';
  static const stepParent = 'stepParent';
  static const stepChild = 'stepChild';
  static const grandParent = 'grandParent';
  static const grandChild = 'grandChild';
  static const guardian = 'guardian';
  static const responsiblePerson = 'responsiblePerson';
  static const caregiver = 'caregiver';
  static const caredForPerson = 'caredForPerson';
  static const fosterFamily = 'fosterFamily';
  static const fosterChild = 'fosterChild';
  static const closePerson = 'closePerson';
  static const custom = 'custom';

  static const known = {
    partner,
    spouse,
    formerPartner,
    parent,
    child,
    sibling,
    halfSibling,
    stepParent,
    stepChild,
    grandParent,
    grandChild,
    guardian,
    responsiblePerson,
    caregiver,
    caredForPerson,
    fosterFamily,
    fosterChild,
    closePerson,
    custom,
  };
}

abstract final class HouseholdMembershipRoles {
  static const permanentMember = 'permanentMember';
  static const alternatingMember = 'alternatingMember';
  static const temporaryMember = 'temporaryMember';
  static const responsiblePerson = 'responsiblePerson';
  static const dependent = 'dependent';
  static const hostedGuest = 'hostedGuest';
  static const custom = 'custom';
}

abstract final class HumanResponsibilityTypes {
  static const parental = 'parental';
  static const custody = 'custody';
  static const accompaniment = 'accompaniment';
  static const care = 'care';
  static const dailyAssistance = 'dailyAssistance';
  static const transport = 'transport';
  static const emergency = 'emergency';
  static const temporary = 'temporary';
  static const delegation = 'delegation';
  static const custom = 'custom';
}

final class HumanPerson {
  HumanPerson({
    required this.id,
    required this.accountScopeId,
    this.identityLink,
    this.displayName,
    this.status = HumanPersonStatus.active,
    required this.evidence,
    Map<String, Object?> customFields = const {},
  }) : customFields = _freezeMap(customFields) {
    _requireIdentity(id, 'invalid_human_person_id');
    _requireScope(accountScopeId);
    if (identityLink != null && identityLink!.entityType != EntityType.person) {
      throw const HumanModelException('human_person_identity_must_be_person');
    }
  }

  final String id;
  final String accountScopeId;
  final PersistedIdentityLink? identityLink;
  final String? displayName;
  final HumanPersonStatus status;
  final HumanEvidence evidence;
  final Map<String, Object?> customFields;

  HumanPerson copyWith({
    String? displayName,
    bool clearDisplayName = false,
    HumanPersonStatus? status,
    HumanEvidence? evidence,
    Map<String, Object?>? customFields,
  }) {
    return HumanPerson(
      id: id,
      accountScopeId: accountScopeId,
      identityLink: identityLink,
      displayName: clearDisplayName ? null : (displayName ?? this.displayName),
      status: status ?? this.status,
      evidence: evidence ?? this.evidence,
      customFields: customFields ?? this.customFields,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'accountScopeId': accountScopeId,
        'identityLink': identityLink == null
            ? null
            : {
                'entityId': identityLink!.entityId,
                'entityType': identityLink!.entityType.name,
                'schemaVersion': identityLink!.schemaVersion,
              },
        'displayName': displayName,
        'status': status.name,
        'evidence': evidence.toJson(),
        'customFields': customFields,
      };

  factory HumanPerson.fromJson(Object? value) {
    final map = _stringMap(value, 'invalid_human_person');
    return HumanPerson(
      id: _requiredString(map['id'], 'invalid_human_person_id'),
      accountScopeId:
          _requiredString(map['accountScopeId'], 'invalid_account_scope_id'),
      identityLink: _identityLink(map['identityLink']),
      displayName: _optionalString(map['displayName']),
      status: _enumValue(
        HumanPersonStatus.values,
        map['status'],
        'invalid_human_person_status',
      ),
      evidence: HumanEvidence.fromJson(map['evidence']),
      customFields: _objectMap(map['customFields']),
    );
  }
}

final class HumanRelationship {
  HumanRelationship({
    required this.id,
    required this.accountScopeId,
    required this.sourcePersonId,
    required this.targetPersonId,
    required this.type,
    this.customType,
    this.reciprocal = false,
    this.status = HumanRecordStatus.active,
    this.validity = const HumanValidityPeriod(),
    required this.evidence,
    Map<String, Object?> structuredNotes = const {},
  }) : structuredNotes = _freezeMap(structuredNotes) {
    _requireIdentity(id, 'invalid_human_relationship_id');
    _requireScope(accountScopeId);
    _requireIdentity(sourcePersonId, 'invalid_relationship_source_id');
    _requireIdentity(targetPersonId, 'invalid_relationship_target_id');
    if (sourcePersonId == targetPersonId) {
      throw const HumanModelException('human_relationship_cannot_target_self');
    }
    if (!HumanRelationshipTypes.known.contains(type)) {
      throw const HumanModelException('invalid_human_relationship_type');
    }
    if (type == HumanRelationshipTypes.custom &&
        (customType == null || customType!.trim().isEmpty)) {
      throw const HumanModelException('custom_relationship_requires_type');
    }
    validity.validate();
  }

  final String id;
  final String accountScopeId;
  final String sourcePersonId;
  final String targetPersonId;
  final String type;
  final String? customType;
  final bool reciprocal;
  final HumanRecordStatus status;
  final HumanValidityPeriod validity;
  final HumanEvidence evidence;
  final Map<String, Object?> structuredNotes;

  bool isActiveAt(DateTime instant) =>
      status == HumanRecordStatus.active && validity.isActiveAt(instant);

  HumanRelationship copyWith({
    String? type,
    String? customType,
    bool clearCustomType = false,
    bool? reciprocal,
    HumanRecordStatus? status,
    HumanValidityPeriod? validity,
    HumanEvidence? evidence,
  }) =>
      HumanRelationship(
        id: id,
        accountScopeId: accountScopeId,
        sourcePersonId: sourcePersonId,
        targetPersonId: targetPersonId,
        type: type ?? this.type,
        customType: clearCustomType ? null : (customType ?? this.customType),
        reciprocal: reciprocal ?? this.reciprocal,
        status: status ?? this.status,
        validity: validity ?? this.validity,
        evidence: evidence ?? this.evidence,
        structuredNotes: structuredNotes,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'accountScopeId': accountScopeId,
        'sourcePersonId': sourcePersonId,
        'targetPersonId': targetPersonId,
        'type': type,
        'customType': customType,
        'reciprocal': reciprocal,
        'status': status.name,
        'validity': validity.toJson(),
        'evidence': evidence.toJson(),
        'structuredNotes': structuredNotes,
      };

  factory HumanRelationship.fromJson(Object? value) {
    final map = _stringMap(value, 'invalid_human_relationship');
    final rawType =
        _requiredString(map['type'], 'invalid_human_relationship_type');
    final knownType = HumanRelationshipTypes.known.contains(rawType)
        ? rawType
        : HumanRelationshipTypes.custom;
    return HumanRelationship(
      id: _requiredString(map['id'], 'invalid_human_relationship_id'),
      accountScopeId:
          _requiredString(map['accountScopeId'], 'invalid_account_scope_id'),
      sourcePersonId: _requiredString(
          map['sourcePersonId'], 'invalid_relationship_source_id'),
      targetPersonId: _requiredString(
          map['targetPersonId'], 'invalid_relationship_target_id'),
      type: knownType,
      customType: knownType == HumanRelationshipTypes.custom
          ? (_optionalString(map['customType']) ?? rawType)
          : _optionalString(map['customType']),
      reciprocal: map['reciprocal'] == true,
      status: _enumValue(
        HumanRecordStatus.values,
        map['status'],
        'invalid_human_record_status',
      ),
      validity: HumanValidityPeriod.fromJson(map['validity']),
      evidence: HumanEvidence.fromJson(map['evidence']),
      structuredNotes: _objectMap(map['structuredNotes']),
    );
  }
}

final class HumanHousehold {
  HumanHousehold({
    required this.id,
    required this.accountScopeId,
    this.displayName,
    this.status = HouseholdStatus.primary,
    this.validity = const HumanValidityPeriod(),
    required this.evidence,
  }) {
    _requireIdentity(id, 'invalid_human_household_id');
    _requireScope(accountScopeId);
    validity.validate();
  }

  final String id;
  final String accountScopeId;
  final String? displayName;
  final HouseholdStatus status;
  final HumanValidityPeriod validity;
  final HumanEvidence evidence;

  bool isActiveAt(DateTime instant) =>
      status != HouseholdStatus.historical && validity.isActiveAt(instant);

  HumanHousehold copyWith({
    String? displayName,
    bool clearDisplayName = false,
    HouseholdStatus? status,
    HumanValidityPeriod? validity,
    HumanEvidence? evidence,
  }) =>
      HumanHousehold(
        id: id,
        accountScopeId: accountScopeId,
        displayName:
            clearDisplayName ? null : (displayName ?? this.displayName),
        status: status ?? this.status,
        validity: validity ?? this.validity,
        evidence: evidence ?? this.evidence,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'accountScopeId': accountScopeId,
        'displayName': displayName,
        'status': status.name,
        'validity': validity.toJson(),
        'evidence': evidence.toJson(),
      };

  factory HumanHousehold.fromJson(Object? value) {
    final map = _stringMap(value, 'invalid_human_household');
    return HumanHousehold(
      id: _requiredString(map['id'], 'invalid_human_household_id'),
      accountScopeId:
          _requiredString(map['accountScopeId'], 'invalid_account_scope_id'),
      displayName: _optionalString(map['displayName']),
      status: _enumValue(
        HouseholdStatus.values,
        map['status'],
        'invalid_household_status',
      ),
      validity: HumanValidityPeriod.fromJson(map['validity']),
      evidence: HumanEvidence.fromJson(map['evidence']),
    );
  }
}

final class HumanResidence {
  HumanResidence({
    required this.id,
    required this.accountScopeId,
    required this.label,
    this.placeEntityId,
    List<String> householdIds = const [],
    List<String> personIds = const [],
    this.status = ResidenceStatus.primary,
    this.validity = const HumanValidityPeriod(),
    required this.evidence,
  })  : householdIds = List.unmodifiable(householdIds),
        personIds = List.unmodifiable(personIds) {
    _requireIdentity(id, 'invalid_human_residence_id');
    _requireScope(accountScopeId);
    if (label.trim().isEmpty) {
      throw const HumanModelException('human_residence_requires_label');
    }
    if (placeEntityId != null) {
      _requireIdentity(placeEntityId!, 'invalid_residence_place_entity_id');
    }
    validity.validate();
  }

  final String id;
  final String accountScopeId;
  final String label;
  final String? placeEntityId;
  final List<String> householdIds;
  final List<String> personIds;
  final ResidenceStatus status;
  final HumanValidityPeriod validity;
  final HumanEvidence evidence;

  HumanResidence copyWith({
    String? label,
    String? placeEntityId,
    bool clearPlaceEntityId = false,
    List<String>? householdIds,
    List<String>? personIds,
    ResidenceStatus? status,
    HumanValidityPeriod? validity,
    HumanEvidence? evidence,
  }) =>
      HumanResidence(
        id: id,
        accountScopeId: accountScopeId,
        label: label ?? this.label,
        placeEntityId:
            clearPlaceEntityId ? null : (placeEntityId ?? this.placeEntityId),
        householdIds: householdIds ?? this.householdIds,
        personIds: personIds ?? this.personIds,
        status: status ?? this.status,
        validity: validity ?? this.validity,
        evidence: evidence ?? this.evidence,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'accountScopeId': accountScopeId,
        'label': label,
        'placeEntityId': placeEntityId,
        'householdIds': householdIds,
        'personIds': personIds,
        'status': status.name,
        'validity': validity.toJson(),
        'evidence': evidence.toJson(),
      };

  factory HumanResidence.fromJson(Object? value) {
    final map = _stringMap(value, 'invalid_human_residence');
    return HumanResidence(
      id: _requiredString(map['id'], 'invalid_human_residence_id'),
      accountScopeId:
          _requiredString(map['accountScopeId'], 'invalid_account_scope_id'),
      label: _requiredString(map['label'], 'human_residence_requires_label'),
      placeEntityId: _optionalString(map['placeEntityId']),
      householdIds: _stringList(map['householdIds']),
      personIds: _stringList(map['personIds']),
      status: _enumValue(
        ResidenceStatus.values,
        map['status'],
        'invalid_residence_status',
      ),
      validity: HumanValidityPeriod.fromJson(map['validity']),
      evidence: HumanEvidence.fromJson(map['evidence']),
    );
  }
}

final class HumanHouseholdMembership {
  HumanHouseholdMembership({
    required this.id,
    required this.accountScopeId,
    required this.householdId,
    required this.personId,
    required this.role,
    this.customRole,
    this.validity = const HumanValidityPeriod(),
    required this.evidence,
  }) {
    _requireIdentity(id, 'invalid_household_membership_id');
    _requireScope(accountScopeId);
    _requireIdentity(householdId, 'invalid_membership_household_id');
    _requireIdentity(personId, 'invalid_membership_person_id');
    if (role.trim().isEmpty) {
      throw const HumanModelException('invalid_household_membership_role');
    }
    validity.validate();
  }

  final String id;
  final String accountScopeId;
  final String householdId;
  final String personId;
  final String role;
  final String? customRole;
  final HumanValidityPeriod validity;
  final HumanEvidence evidence;

  bool isActiveAt(DateTime instant) => validity.isActiveAt(instant);

  HumanHouseholdMembership copyWith({
    String? role,
    String? customRole,
    bool clearCustomRole = false,
    HumanValidityPeriod? validity,
    HumanEvidence? evidence,
  }) =>
      HumanHouseholdMembership(
        id: id,
        accountScopeId: accountScopeId,
        householdId: householdId,
        personId: personId,
        role: role ?? this.role,
        customRole: clearCustomRole ? null : (customRole ?? this.customRole),
        validity: validity ?? this.validity,
        evidence: evidence ?? this.evidence,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'accountScopeId': accountScopeId,
        'householdId': householdId,
        'personId': personId,
        'role': role,
        'customRole': customRole,
        'validity': validity.toJson(),
        'evidence': evidence.toJson(),
      };

  factory HumanHouseholdMembership.fromJson(Object? value) {
    final map = _stringMap(value, 'invalid_household_membership');
    return HumanHouseholdMembership(
      id: _requiredString(map['id'], 'invalid_household_membership_id'),
      accountScopeId:
          _requiredString(map['accountScopeId'], 'invalid_account_scope_id'),
      householdId: _requiredString(
          map['householdId'], 'invalid_membership_household_id'),
      personId:
          _requiredString(map['personId'], 'invalid_membership_person_id'),
      role: _requiredString(map['role'], 'invalid_household_membership_role'),
      customRole: _optionalString(map['customRole']),
      validity: HumanValidityPeriod.fromJson(map['validity']),
      evidence: HumanEvidence.fromJson(map['evidence']),
    );
  }
}

final class HumanResponsibility {
  HumanResponsibility({
    required this.id,
    required this.accountScopeId,
    required this.responsiblePersonId,
    required this.subjectPersonId,
    required this.type,
    this.customType,
    this.scope,
    this.validity = const HumanValidityPeriod(),
    this.status = HumanRecordStatus.active,
    required this.evidence,
  }) {
    _requireIdentity(id, 'invalid_human_responsibility_id');
    _requireScope(accountScopeId);
    _requireIdentity(
      responsiblePersonId,
      'invalid_responsible_person_id',
    );
    _requireIdentity(subjectPersonId, 'invalid_responsibility_subject_id');
    if (type.trim().isEmpty) {
      throw const HumanModelException('invalid_human_responsibility_type');
    }
    validity.validate();
  }

  final String id;
  final String accountScopeId;
  final String responsiblePersonId;
  final String subjectPersonId;
  final String type;
  final String? customType;
  final String? scope;
  final HumanValidityPeriod validity;
  final HumanRecordStatus status;
  final HumanEvidence evidence;

  bool isActiveAt(DateTime instant) =>
      status == HumanRecordStatus.active && validity.isActiveAt(instant);

  HumanResponsibility copyWith({
    String? type,
    String? customType,
    bool clearCustomType = false,
    String? scope,
    bool clearScope = false,
    HumanValidityPeriod? validity,
    HumanRecordStatus? status,
    HumanEvidence? evidence,
  }) =>
      HumanResponsibility(
        id: id,
        accountScopeId: accountScopeId,
        responsiblePersonId: responsiblePersonId,
        subjectPersonId: subjectPersonId,
        type: type ?? this.type,
        customType: clearCustomType ? null : (customType ?? this.customType),
        scope: clearScope ? null : (scope ?? this.scope),
        validity: validity ?? this.validity,
        status: status ?? this.status,
        evidence: evidence ?? this.evidence,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'accountScopeId': accountScopeId,
        'responsiblePersonId': responsiblePersonId,
        'subjectPersonId': subjectPersonId,
        'type': type,
        'customType': customType,
        'scope': scope,
        'validity': validity.toJson(),
        'status': status.name,
        'evidence': evidence.toJson(),
      };

  factory HumanResponsibility.fromJson(Object? value) {
    final map = _stringMap(value, 'invalid_human_responsibility');
    return HumanResponsibility(
      id: _requiredString(map['id'], 'invalid_human_responsibility_id'),
      accountScopeId:
          _requiredString(map['accountScopeId'], 'invalid_account_scope_id'),
      responsiblePersonId: _requiredString(
        map['responsiblePersonId'],
        'invalid_responsible_person_id',
      ),
      subjectPersonId: _requiredString(
        map['subjectPersonId'],
        'invalid_responsibility_subject_id',
      ),
      type: _requiredString(map['type'], 'invalid_human_responsibility_type'),
      customType: _optionalString(map['customType']),
      scope: _optionalString(map['scope']),
      validity: HumanValidityPeriod.fromJson(map['validity']),
      status: _enumValue(
        HumanRecordStatus.values,
        map['status'],
        'invalid_human_record_status',
      ),
      evidence: HumanEvidence.fromJson(map['evidence']),
    );
  }
}

final class HumanModel {
  static const currentSchemaVersion = 1;
  static const _knownKeys = {
    'schemaVersion',
    'accountScopeId',
    'primaryPersonId',
    'persons',
    'relationships',
    'households',
    'residences',
    'memberships',
    'responsibilities',
    'legacyProfile',
  };

  HumanModel({
    this.schemaVersion = currentSchemaVersion,
    required this.accountScopeId,
    required this.primaryPersonId,
    List<HumanPerson> persons = const [],
    List<HumanRelationship> relationships = const [],
    List<HumanHousehold> households = const [],
    List<HumanResidence> residences = const [],
    List<HumanHouseholdMembership> memberships = const [],
    List<HumanResponsibility> responsibilities = const [],
    Map<String, Object?> legacyProfile = const {},
    Map<String, Object?> unknownFields = const {},
  })  : persons = _sorted(persons, (item) => item.id),
        relationships = _sorted(relationships, (item) => item.id),
        households = _sorted(households, (item) => item.id),
        residences = _sorted(residences, (item) => item.id),
        memberships = _sorted(memberships, (item) => item.id),
        responsibilities = _sorted(responsibilities, (item) => item.id),
        legacyProfile = _freezeMap(legacyProfile),
        unknownFields = _freezeMap(unknownFields) {
    validate();
  }

  final int schemaVersion;
  final String accountScopeId;
  final String primaryPersonId;
  final List<HumanPerson> persons;
  final List<HumanRelationship> relationships;
  final List<HumanHousehold> households;
  final List<HumanResidence> residences;
  final List<HumanHouseholdMembership> memberships;
  final List<HumanResponsibility> responsibilities;
  final Map<String, Object?> legacyProfile;
  final Map<String, Object?> unknownFields;

  HumanModel copyWith({
    List<HumanPerson>? persons,
    List<HumanRelationship>? relationships,
    List<HumanHousehold>? households,
    List<HumanResidence>? residences,
    List<HumanHouseholdMembership>? memberships,
    List<HumanResponsibility>? responsibilities,
    Map<String, Object?>? legacyProfile,
    Map<String, Object?>? unknownFields,
  }) {
    return HumanModel(
      schemaVersion: schemaVersion,
      accountScopeId: accountScopeId,
      primaryPersonId: primaryPersonId,
      persons: persons ?? this.persons,
      relationships: relationships ?? this.relationships,
      households: households ?? this.households,
      residences: residences ?? this.residences,
      memberships: memberships ?? this.memberships,
      responsibilities: responsibilities ?? this.responsibilities,
      legacyProfile: legacyProfile ?? this.legacyProfile,
      unknownFields: unknownFields ?? this.unknownFields,
    );
  }

  void validate() {
    if (schemaVersion < 1 || schemaVersion > currentSchemaVersion) {
      throw const HumanModelException('unsupported_human_schema_version');
    }
    _requireScope(accountScopeId);
    _requireIdentity(primaryPersonId, 'invalid_primary_person_id');
    final personIds = _uniqueIds(persons.map((item) => item.id));
    final householdIds = _uniqueIds(households.map((item) => item.id));
    _uniqueIds(relationships.map((item) => item.id));
    _uniqueIds(residences.map((item) => item.id));
    _uniqueIds(memberships.map((item) => item.id));
    _uniqueIds(responsibilities.map((item) => item.id));
    if (!personIds.contains(primaryPersonId)) {
      throw const HumanModelException('primary_person_not_found');
    }
    for (final scoped in [
      ...persons.map((item) => item.accountScopeId),
      ...relationships.map((item) => item.accountScopeId),
      ...households.map((item) => item.accountScopeId),
      ...residences.map((item) => item.accountScopeId),
      ...memberships.map((item) => item.accountScopeId),
      ...responsibilities.map((item) => item.accountScopeId),
    ]) {
      if (scoped != accountScopeId) {
        throw const HumanModelException('human_model_scope_mismatch');
      }
    }
    for (final relation in relationships) {
      if (!personIds.contains(relation.sourcePersonId) ||
          !personIds.contains(relation.targetPersonId)) {
        throw const HumanModelException('relationship_person_not_found');
      }
    }
    _rejectDuplicateKeys(
      relationships.map(
        (relation) => [
          relation.sourcePersonId,
          relation.targetPersonId,
          relation.type,
          relation.customType ?? '',
          relation.status.name,
          _periodKey(relation.validity),
        ].join('|'),
      ),
      'duplicate_human_relationship',
    );
    final membershipKeys = <String>{};
    for (final membership in memberships) {
      if (!personIds.contains(membership.personId) ||
          !householdIds.contains(membership.householdId)) {
        throw const HumanModelException('membership_reference_not_found');
      }
      final key = [
        membership.householdId,
        membership.personId,
        membership.role,
        membership.validity.validFrom?.toUtc().toIso8601String() ?? '',
        membership.validity.validUntil?.toUtc().toIso8601String() ?? '',
      ].join('|');
      if (!membershipKeys.add(key)) {
        throw const HumanModelException('duplicate_household_membership');
      }
    }
    for (final residence in residences) {
      if (residence.personIds.any((id) => !personIds.contains(id)) ||
          residence.householdIds.any((id) => !householdIds.contains(id))) {
        throw const HumanModelException('residence_reference_not_found');
      }
    }
    for (final responsibility in responsibilities) {
      if (!personIds.contains(responsibility.responsiblePersonId) ||
          !personIds.contains(responsibility.subjectPersonId)) {
        throw const HumanModelException('responsibility_person_not_found');
      }
    }
    _rejectDuplicateKeys(
      responsibilities.map(
        (responsibility) => [
          responsibility.responsiblePersonId,
          responsibility.subjectPersonId,
          responsibility.type,
          responsibility.customType ?? '',
          responsibility.scope ?? '',
          responsibility.status.name,
          _periodKey(responsibility.validity),
        ].join('|'),
      ),
      'duplicate_human_responsibility',
    );
  }

  HumanPerson? personById(String id) {
    for (final person in persons) {
      if (person.id == id) return person;
    }
    return null;
  }

  List<HumanRelationship> activeRelationships(DateTime at) => relationships
      .where((item) => item.isActiveAt(at))
      .toList(growable: false);

  List<HumanHousehold> activeHouseholds(DateTime at) =>
      households.where((item) => item.isActiveAt(at)).toList(growable: false);

  List<HumanResponsibility> activeResponsibilities(DateTime at) =>
      responsibilities
          .where((item) => item.isActiveAt(at))
          .toList(growable: false);

  Map<String, Object?> toJson() => {
        ...unknownFields,
        'schemaVersion': schemaVersion,
        'accountScopeId': accountScopeId,
        'primaryPersonId': primaryPersonId,
        'persons': persons.map((item) => item.toJson()).toList(),
        'relationships': relationships.map((item) => item.toJson()).toList(),
        'households': households.map((item) => item.toJson()).toList(),
        'residences': residences.map((item) => item.toJson()).toList(),
        'memberships': memberships.map((item) => item.toJson()).toList(),
        'responsibilities':
            responsibilities.map((item) => item.toJson()).toList(),
        'legacyProfile': legacyProfile,
      };

  factory HumanModel.fromJson(Object? value) {
    final map = _stringMap(value, 'invalid_human_model_json');
    final rawVersion = map['schemaVersion'] ?? currentSchemaVersion;
    if (rawVersion is! int || rawVersion < 1) {
      throw const HumanModelException('invalid_human_schema_version');
    }
    if (rawVersion > currentSchemaVersion) {
      throw const HumanModelException('unsupported_human_schema_version');
    }
    return HumanModel(
      schemaVersion: rawVersion,
      accountScopeId:
          _requiredString(map['accountScopeId'], 'invalid_account_scope_id'),
      primaryPersonId:
          _requiredString(map['primaryPersonId'], 'invalid_primary_person_id'),
      persons: _objectList(map['persons']).map(HumanPerson.fromJson).toList(),
      relationships: _objectList(map['relationships'])
          .map(HumanRelationship.fromJson)
          .toList(),
      households:
          _objectList(map['households']).map(HumanHousehold.fromJson).toList(),
      residences:
          _objectList(map['residences']).map(HumanResidence.fromJson).toList(),
      memberships: _objectList(map['memberships'])
          .map(HumanHouseholdMembership.fromJson)
          .toList(),
      responsibilities: _objectList(map['responsibilities'])
          .map(HumanResponsibility.fromJson)
          .toList(),
      legacyProfile: _objectMap(map['legacyProfile']),
      unknownFields: Map.unmodifiable(
        Map<String, Object?>.fromEntries(
          map.entries.where((entry) => !_knownKeys.contains(entry.key)),
        ),
      ),
    );
  }
}

List<T> _sorted<T>(Iterable<T> values, String Function(T) id) {
  final result = List<T>.from(values)..sort((a, b) => id(a).compareTo(id(b)));
  return List.unmodifiable(result);
}

Set<String> _uniqueIds(Iterable<String> ids) {
  final result = <String>{};
  for (final id in ids) {
    if (!result.add(id)) {
      throw const HumanModelException('duplicate_human_record_id');
    }
  }
  return result;
}

void _rejectDuplicateKeys(Iterable<String> keys, String code) {
  final seen = <String>{};
  for (final key in keys) {
    if (!seen.add(key)) throw HumanModelException(code);
  }
}

String _periodKey(HumanValidityPeriod period) => [
      period.validFrom?.toUtc().toIso8601String() ?? '',
      period.validUntil?.toUtc().toIso8601String() ?? '',
    ].join('/');

void _requireIdentity(String value, String code) {
  if (!EntityIdentity.isValid(value)) throw HumanModelException(code);
}

void _requireScope(String value) {
  if (value.trim().isEmpty) {
    throw const HumanModelException('invalid_account_scope_id');
  }
}

Map<String, Object?> _stringMap(Object? value, String code) {
  if (value is! Map) throw HumanModelException(code);
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) throw HumanModelException(code);
    result[entry.key as String] = entry.value;
  }
  return result;
}

Map<String, Object?> _objectMap(Object? value) {
  if (value == null) return const {};
  return _freezeMap(_stringMap(value, 'invalid_human_object_map'));
}

Map<String, Object?> _freezeMap(Map<String, Object?> value) {
  final sorted = SplayTreeMap<String, Object?>();
  for (final entry in value.entries) {
    sorted[entry.key] = _freezeValue(entry.value);
  }
  return Map.unmodifiable(sorted);
}

Object? _freezeValue(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is Map) {
    return _freezeMap(_stringMap(value, 'invalid_human_object_map'));
  }
  if (value is List) {
    return List.unmodifiable(value.map(_freezeValue));
  }
  throw const HumanModelException('invalid_human_custom_value');
}

List<Object?> _objectList(Object? value) {
  if (value == null) return const [];
  if (value is! List) {
    throw const HumanModelException('invalid_human_object_list');
  }
  return value;
}

List<String> _stringList(Object? value) {
  if (value == null) return const [];
  if (value is! List || value.any((item) => item is! String)) {
    throw const HumanModelException('invalid_human_string_list');
  }
  return List.unmodifiable(value.cast<String>());
}

String _requiredString(Object? value, String code) {
  if (value is! String || value.trim().isEmpty) throw HumanModelException(code);
  return value;
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  if (value is! String) {
    throw const HumanModelException('invalid_optional_human_string');
  }
  return value.trim().isEmpty ? null : value;
}

DateTime? _optionalDate(Object? value) {
  if (value == null) return null;
  if (value is! String) {
    throw const HumanModelException('invalid_human_date');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw const HumanModelException('invalid_human_date');
  return parsed.toUtc();
}

PersistedIdentityLink? _identityLink(Object? value) {
  if (value == null) return null;
  final map = _stringMap(value, 'invalid_human_person_identity_link');
  if (map.keys.toSet().difference(const {
    'entityId',
    'entityType',
    'schemaVersion',
  }).isNotEmpty) {
    throw const HumanModelException('invalid_human_person_identity_link');
  }
  final entityId = map['entityId'];
  final schemaVersion = map['schemaVersion'];
  if (entityId is! String ||
      !EntityIdentity.isValid(entityId) ||
      map['entityType'] != EntityType.person.name ||
      schemaVersion != PersistedIdentityLink.currentSchemaVersion) {
    throw const HumanModelException('invalid_human_person_identity_link');
  }
  return PersistedIdentityLink(
    entityId: entityId,
    entityType: EntityType.person,
    schemaVersion: schemaVersion as int,
  );
}

T _enumValue<T extends Enum>(List<T> values, Object? raw, String code) {
  if (raw is String) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
  }
  throw HumanModelException(code);
}
