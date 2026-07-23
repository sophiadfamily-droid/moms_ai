enum MemoryGeneralMode { automatic, askEveryTime, paused }

enum MemoryHealthMode { disabled, askEveryTime, enabled }

enum MemoryPolicyChangeSource { explicitUserSetting, restrictiveDefault }

final class MemoryPolicyException implements Exception {
  const MemoryPolicyException(this.code);

  final String code;
}

final class MemoryPolicy {
  static const int currentSchemaVersion = 1;

  const MemoryPolicy({
    this.schemaVersion = currentSchemaVersion,
    required this.accountScopeId,
    required this.generalMode,
    required this.healthMode,
    required this.healthConsentGranted,
    required this.changedAt,
    required this.changeSource,
  });

  factory MemoryPolicy.restrictiveDefault({
    required String accountScopeId,
    required DateTime changedAt,
  }) =>
      MemoryPolicy(
        accountScopeId: accountScopeId,
        generalMode: MemoryGeneralMode.askEveryTime,
        healthMode: MemoryHealthMode.disabled,
        healthConsentGranted: false,
        changedAt: changedAt,
        changeSource: MemoryPolicyChangeSource.restrictiveDefault,
      );

  factory MemoryPolicy.fromJson(
    Map<String, Object?> json, {
    required String expectedAccountScopeId,
  }) {
    final version = json['schemaVersion'];
    if (version != currentSchemaVersion) {
      throw const MemoryPolicyException('unsupported_memory_policy_version');
    }
    final scope = json['accountScopeId']?.toString() ?? '';
    final general = _enumValue(
      MemoryGeneralMode.values,
      json['generalMode'],
    );
    final health = _enumValue(
      MemoryHealthMode.values,
      json['healthMode'],
    );
    final source = _enumValue(
      MemoryPolicyChangeSource.values,
      json['changeSource'],
    );
    final changedAt = DateTime.tryParse(json['changedAt']?.toString() ?? '');
    final consent = json['healthConsentGranted'];
    if (scope != expectedAccountScopeId ||
        general == null ||
        health == null ||
        source == null ||
        changedAt == null ||
        consent is! bool) {
      throw const MemoryPolicyException('invalid_memory_policy');
    }
    final policy = MemoryPolicy(
      accountScopeId: scope,
      generalMode: general,
      healthMode: health,
      healthConsentGranted: consent,
      changedAt: changedAt.toUtc(),
      changeSource: source,
    );
    policy.validate();
    return policy;
  }

  final int schemaVersion;
  final String accountScopeId;
  final MemoryGeneralMode generalMode;
  final MemoryHealthMode healthMode;
  final bool healthConsentGranted;
  final DateTime changedAt;
  final MemoryPolicyChangeSource changeSource;

  bool get acceptsNewProposals => generalMode != MemoryGeneralMode.paused;
  bool get readsExistingMemories => true;

  void validate() {
    if (schemaVersion != currentSchemaVersion ||
        accountScopeId.trim().isEmpty ||
        (healthMode == MemoryHealthMode.enabled && !healthConsentGranted)) {
      throw const MemoryPolicyException('invalid_memory_policy');
    }
  }

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'accountScopeId': accountScopeId,
        'generalMode': generalMode.name,
        'healthMode': healthMode.name,
        'healthConsentGranted': healthConsentGranted,
        'changedAt': changedAt.toUtc().toIso8601String(),
        'changeSource': changeSource.name,
      };

  static T? _enumValue<T extends Enum>(List<T> values, Object? raw) {
    final value = raw?.toString();
    for (final item in values) {
      if (item.name == value) return item;
    }
    return null;
  }
}

final class MemoryPolicyTransition {
  const MemoryPolicyTransition({
    required this.previous,
    required this.current,
    required this.pendingProposalsRemainPending,
    required this.existingMemoriesRemainAvailable,
    required this.retroactiveCaptureAllowed,
  });

  final MemoryPolicy previous;
  final MemoryPolicy current;
  final bool pendingProposalsRemainPending;
  final bool existingMemoriesRemainAvailable;
  final bool retroactiveCaptureAllowed;
}
