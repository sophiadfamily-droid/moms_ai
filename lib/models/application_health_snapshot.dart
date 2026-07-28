enum ApplicationStartupState { starting, ready, degraded, failed }

enum ApplicationDependencyState {
  unknown,
  available,
  degraded,
  unavailable,
}

enum ApplicationAccountScopeState {
  signedOut,
  guest,
  authenticated,
  mismatch,
}

final class ApplicationHealthSnapshot {
  static const int currentSchemaVersion = 1;

  const ApplicationHealthSnapshot({
    this.schemaVersion = currentSchemaVersion,
    required this.generatedAt,
    required this.startupState,
    required this.authState,
    required this.accountScopeState,
    required this.localStorageState,
    required this.firestoreState,
    required this.callableState,
    required this.pendingMutationCountByDomain,
    required this.oldestPendingMutationAgeBucket,
    required this.lastSuccessfulSyncBucket,
    required this.lastCriticalDiagnosticCode,
    required this.diagnosticsBufferState,
    required this.environment,
    required this.buildIdentifier,
  });

  final int schemaVersion;
  final DateTime generatedAt;
  final ApplicationStartupState startupState;
  final ApplicationDependencyState authState;
  final ApplicationAccountScopeState accountScopeState;
  final ApplicationDependencyState localStorageState;
  final ApplicationDependencyState firestoreState;
  final ApplicationDependencyState callableState;
  final Map<String, int> pendingMutationCountByDomain;
  final String oldestPendingMutationAgeBucket;
  final String lastSuccessfulSyncBucket;
  final String? lastCriticalDiagnosticCode;
  final String diagnosticsBufferState;
  final String environment;
  final String buildIdentifier;

  Map<String, Object?> toJson() {
    if (schemaVersion != currentSchemaVersion ||
        pendingMutationCountByDomain.entries.any(
          (entry) =>
              !_validCode(entry.key) || entry.value < 0 || entry.value > 10000,
        ) ||
        !_validCode(oldestPendingMutationAgeBucket) ||
        !_validCode(lastSuccessfulSyncBucket) ||
        !_validCode(diagnosticsBufferState) ||
        !_validCode(environment) ||
        !_validCode(buildIdentifier) ||
        (lastCriticalDiagnosticCode != null &&
            !_validCode(lastCriticalDiagnosticCode!))) {
      throw const FormatException('invalid_application_health_snapshot');
    }
    return {
      'schemaVersion': schemaVersion,
      'generatedAt': generatedAt.toUtc().toIso8601String(),
      'startupState': startupState.name,
      'authState': authState.name,
      'accountScopeState': accountScopeState.name,
      'localStorageState': localStorageState.name,
      'firestoreState': firestoreState.name,
      'callableState': callableState.name,
      'pendingMutationCountByDomain': pendingMutationCountByDomain,
      'oldestPendingMutationAgeBucket': oldestPendingMutationAgeBucket,
      'lastSuccessfulSyncBucket': lastSuccessfulSyncBucket,
      'lastCriticalDiagnosticCode': lastCriticalDiagnosticCode,
      'diagnosticsBufferState': diagnosticsBufferState,
      'environment': environment,
      'buildIdentifier': buildIdentifier,
    };
  }

  static bool _validCode(String value) =>
      value.isNotEmpty &&
      value.length <= 80 &&
      RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(value);
}
