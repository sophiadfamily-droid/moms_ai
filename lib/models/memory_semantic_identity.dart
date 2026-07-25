enum MemorySemanticDomain {
  profile,
  planning,
  availability,
  preference,
  constraint,
  routine,
  residence,
  household,
  relationship,
  health,
  work,
  general,
}

enum MemorySemanticAttribute {
  preferredAppointmentPeriod,
  unavailableWeekdayPeriod,
  workSchedule,
  currentResidence,
  dietaryPreference,
  recurringActivitySchedule,
  generalFact,
  generalPreference,
  generalConstraint,
  generalRoutine,
}

enum MemorySemanticSubjectScope {
  authenticatedUser,
  structuredEntity,
  account,
  household,
  residence,
  unknown,
}

enum MemorySemanticContextType {
  personalAppointments,
  workAppointments,
  household,
  residence,
  workplace,
  dependentSchedule,
  general,
}

enum MemorySemanticIdentityReadStatus {
  valid,
  absentLegacy,
  invalidModern,
}

final class MemorySemanticIdentityReadResult {
  const MemorySemanticIdentityReadResult._(this.status, this.identity);

  static const absent = MemorySemanticIdentityReadResult._(
    MemorySemanticIdentityReadStatus.absentLegacy,
    null,
  );

  static const invalid = MemorySemanticIdentityReadResult._(
    MemorySemanticIdentityReadStatus.invalidModern,
    null,
  );

  factory MemorySemanticIdentityReadResult.valid(
    MemorySemanticIdentity identity,
  ) =>
      MemorySemanticIdentityReadResult._(
        MemorySemanticIdentityReadStatus.valid,
        identity,
      );

  final MemorySemanticIdentityReadStatus status;
  final MemorySemanticIdentity? identity;
}

final class MemorySemanticIdentity {
  static const currentSchemaVersion = 1;

  const MemorySemanticIdentity({
    required this.domain,
    required this.attribute,
    required this.subjectScope,
    required this.subjectFingerprint,
    required this.contextType,
    required this.contextFingerprint,
    required this.canonicalKey,
    required this.eligibleForAutomaticContradiction,
    this.schemaVersion = currentSchemaVersion,
  });

  final MemorySemanticDomain domain;
  final MemorySemanticAttribute attribute;
  final MemorySemanticSubjectScope subjectScope;
  final String? subjectFingerprint;
  final MemorySemanticContextType contextType;
  final String? contextFingerprint;
  final String canonicalKey;
  final bool eligibleForAutomaticContradiction;
  final int schemaVersion;

  bool get hasClosedAttribute => attribute.isClosed;

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'domain': domain.wireName,
        'attribute': attribute.wireName,
        'subjectScope': subjectScope.wireName,
        if (subjectFingerprint != null)
          'subjectFingerprint': subjectFingerprint,
        'contextType': contextType.wireName,
        if (contextFingerprint != null)
          'contextFingerprint': contextFingerprint,
        'canonicalKey': canonicalKey,
        'eligibleForAutomaticContradiction': eligibleForAutomaticContradiction,
      };

  factory MemorySemanticIdentity.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('invalid_memory_semantic_identity');
    }
    final map = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw const FormatException('invalid_memory_semantic_identity');
      }
      map[entry.key as String] = entry.value;
    }
    if (map['schemaVersion'] != currentSchemaVersion) {
      throw const FormatException('unsupported_memory_semantic_identity');
    }
    final domain = _enumByWire(
      MemorySemanticDomain.values,
      map['domain'],
      (item) => item.wireName,
    );
    final attribute = _enumByWire(
      MemorySemanticAttribute.values,
      map['attribute'],
      (item) => item.wireName,
    );
    final scope = _enumByWire(
      MemorySemanticSubjectScope.values,
      map['subjectScope'],
      (item) => item.wireName,
    );
    final contextType = _enumByWire(
      MemorySemanticContextType.values,
      map['contextType'],
      (item) => item.wireName,
    );
    final subjectFingerprint = _optionalFingerprint(map, 'subjectFingerprint');
    final contextFingerprint = _optionalFingerprint(map, 'contextFingerprint');
    final canonicalKey = map['canonicalKey'];
    final persistedEligibility = map['eligibleForAutomaticContradiction'];
    if (canonicalKey is! String || persistedEligibility is! bool) {
      throw const FormatException('incomplete_memory_semantic_identity');
    }
    if (attribute.isClosed &&
        !attribute.accepts(domain: domain, contextType: contextType)) {
      throw const FormatException('incoherent_memory_semantic_meaning');
    }
    final computedEligibility = computeEligibility(
      domain: domain,
      attribute: attribute,
      subjectScope: scope,
      subjectFingerprint: subjectFingerprint,
      contextType: contextType,
    );
    final computedKey = buildCanonicalKey(
      domain: domain,
      attribute: attribute,
      subjectScope: scope,
      subjectFingerprint: subjectFingerprint,
      contextType: contextType,
      contextFingerprint: contextFingerprint,
    );
    if (canonicalKey != computedKey ||
        persistedEligibility != computedEligibility) {
      throw const FormatException('incoherent_memory_semantic_identity');
    }
    return MemorySemanticIdentity(
      domain: domain,
      attribute: attribute,
      subjectScope: scope,
      subjectFingerprint: subjectFingerprint,
      contextType: contextType,
      contextFingerprint: contextFingerprint,
      canonicalKey: computedKey,
      eligibleForAutomaticContradiction: computedEligibility,
    );
  }

  static MemorySemanticIdentityReadResult read(Object? value) {
    if (value == null) return MemorySemanticIdentityReadResult.absent;
    try {
      return MemorySemanticIdentityReadResult.valid(
        MemorySemanticIdentity.fromJson(value),
      );
    } on FormatException {
      return MemorySemanticIdentityReadResult.invalid;
    }
  }

  static bool computeEligibility({
    required MemorySemanticDomain domain,
    required MemorySemanticAttribute attribute,
    required MemorySemanticSubjectScope subjectScope,
    required String? subjectFingerprint,
    required MemorySemanticContextType contextType,
  }) {
    if (!attribute.isClosed) return false;
    if (!attribute.accepts(domain: domain, contextType: contextType)) {
      return false;
    }
    if (subjectScope == MemorySemanticSubjectScope.unknown) return false;
    if (subjectScope.requiresFingerprint &&
        !_isFingerprint(subjectFingerprint)) {
      return false;
    }
    return true;
  }

  static String buildCanonicalKey({
    required MemorySemanticDomain domain,
    required MemorySemanticAttribute attribute,
    required MemorySemanticSubjectScope subjectScope,
    required String? subjectFingerprint,
    required MemorySemanticContextType contextType,
    required String? contextFingerprint,
  }) =>
      [
        'v$currentSchemaVersion',
        domain.wireName,
        attribute.wireName,
        subjectScope.wireName,
        subjectFingerprint ?? 'scope',
        contextType.wireName,
        contextFingerprint ?? 'none',
      ].join('|');

  static String? _optionalFingerprint(
    Map<String, Object?> map,
    String field,
  ) {
    if (!map.containsKey(field)) return null;
    final value = map[field];
    if (value is! String || !_isFingerprint(value)) {
      throw const FormatException('invalid_memory_identity_fingerprint');
    }
    return value;
  }

  static bool _isFingerprint(String? value) =>
      value != null && RegExp(r'^[a-f0-9]{64}$').hasMatch(value);
}

T _enumByWire<T>(
  Iterable<T> values,
  Object? raw,
  String Function(T) wire,
) {
  if (raw is! String) {
    throw const FormatException('invalid_memory_identity_enum');
  }
  for (final value in values) {
    if (wire(value) == raw) return value;
  }
  throw const FormatException('unknown_memory_identity_enum');
}

extension MemorySemanticDomainWire on MemorySemanticDomain {
  String get wireName => name;
}

extension MemorySemanticAttributeWire on MemorySemanticAttribute {
  String get wireName => switch (this) {
        MemorySemanticAttribute.preferredAppointmentPeriod =>
          'preferred_appointment_period',
        MemorySemanticAttribute.unavailableWeekdayPeriod =>
          'unavailable_weekday_period',
        MemorySemanticAttribute.workSchedule => 'work_schedule',
        MemorySemanticAttribute.currentResidence => 'current_residence',
        MemorySemanticAttribute.dietaryPreference => 'dietary_preference',
        MemorySemanticAttribute.recurringActivitySchedule =>
          'recurring_activity_schedule',
        MemorySemanticAttribute.generalFact => 'general_fact',
        MemorySemanticAttribute.generalPreference => 'general_preference',
        MemorySemanticAttribute.generalConstraint => 'general_constraint',
        MemorySemanticAttribute.generalRoutine => 'general_routine',
      };

  bool get isClosed => !const {
        MemorySemanticAttribute.generalFact,
        MemorySemanticAttribute.generalPreference,
        MemorySemanticAttribute.generalConstraint,
        MemorySemanticAttribute.generalRoutine,
      }.contains(this);

  bool accepts({
    required MemorySemanticDomain domain,
    required MemorySemanticContextType contextType,
  }) =>
      switch (this) {
        MemorySemanticAttribute.preferredAppointmentPeriod =>
          domain == MemorySemanticDomain.planning &&
              (contextType == MemorySemanticContextType.personalAppointments ||
                  contextType == MemorySemanticContextType.workAppointments),
        MemorySemanticAttribute.unavailableWeekdayPeriod =>
          domain == MemorySemanticDomain.availability &&
              (contextType == MemorySemanticContextType.general ||
                  contextType == MemorySemanticContextType.workplace ||
                  contextType == MemorySemanticContextType.dependentSchedule),
        MemorySemanticAttribute.workSchedule =>
          domain == MemorySemanticDomain.work &&
              contextType == MemorySemanticContextType.workplace,
        MemorySemanticAttribute.currentResidence =>
          domain == MemorySemanticDomain.residence &&
              contextType == MemorySemanticContextType.residence,
        MemorySemanticAttribute.dietaryPreference =>
          domain == MemorySemanticDomain.preference &&
              contextType == MemorySemanticContextType.general,
        MemorySemanticAttribute.recurringActivitySchedule =>
          domain == MemorySemanticDomain.routine,
        _ => false,
      };
}

extension MemorySemanticSubjectScopeWire on MemorySemanticSubjectScope {
  String get wireName => switch (this) {
        MemorySemanticSubjectScope.authenticatedUser => 'authenticated_user',
        MemorySemanticSubjectScope.structuredEntity => 'structured_entity',
        MemorySemanticSubjectScope.account => 'account',
        MemorySemanticSubjectScope.household => 'household',
        MemorySemanticSubjectScope.residence => 'residence',
        MemorySemanticSubjectScope.unknown => 'unknown',
      };

  bool get requiresFingerprint => const {
        MemorySemanticSubjectScope.structuredEntity,
        MemorySemanticSubjectScope.household,
        MemorySemanticSubjectScope.residence,
        MemorySemanticSubjectScope.unknown,
      }.contains(this);
}

extension MemorySemanticContextTypeWire on MemorySemanticContextType {
  String get wireName => switch (this) {
        MemorySemanticContextType.personalAppointments =>
          'personal_appointments',
        MemorySemanticContextType.workAppointments => 'work_appointments',
        MemorySemanticContextType.household => 'household',
        MemorySemanticContextType.residence => 'residence',
        MemorySemanticContextType.workplace => 'workplace',
        MemorySemanticContextType.dependentSchedule => 'dependent_schedule',
        MemorySemanticContextType.general => 'general',
      };
}
