import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/application_health_snapshot.dart';

void main() {
  test('health snapshot exposes only closed technical state', () {
    final snapshot = ApplicationHealthSnapshot(
      generatedAt: DateTime.utc(2026, 7, 28),
      startupState: ApplicationStartupState.ready,
      authState: ApplicationDependencyState.available,
      accountScopeState: ApplicationAccountScopeState.authenticated,
      localStorageState: ApplicationDependencyState.available,
      firestoreState: ApplicationDependencyState.degraded,
      callableState: ApplicationDependencyState.available,
      pendingMutationCountByDomain: const {'task': 2, 'event': 1},
      oldestPendingMutationAgeBucket: 'under_1h',
      lastSuccessfulSyncBucket: 'under_5m',
      lastCriticalDiagnosticCode: 'sync-failure',
      diagnosticsBufferState: 'available',
      environment: 'production',
      buildIdentifier: 'release_technical',
    );
    final json = snapshot.toJson();
    expect(json['pendingMutationCountByDomain'], {'task': 2, 'event': 1});
    expect(json.toString(), isNot(contains('uid')));
    expect(json.toString(), isNot(contains('title')));
  });

  test('health snapshot rejects free-form or oversized values', () {
    final snapshot = ApplicationHealthSnapshot(
      generatedAt: DateTime.utc(2026, 7, 28),
      startupState: ApplicationStartupState.ready,
      authState: ApplicationDependencyState.available,
      accountScopeState: ApplicationAccountScopeState.guest,
      localStorageState: ApplicationDependencyState.available,
      firestoreState: ApplicationDependencyState.unknown,
      callableState: ApplicationDependencyState.unknown,
      pendingMutationCountByDomain: const {'task title': 1},
      oldestPendingMutationAgeBucket: 'under_1h',
      lastSuccessfulSyncBucket: 'unknown',
      lastCriticalDiagnosticCode: null,
      diagnosticsBufferState: 'available',
      environment: 'production',
      buildIdentifier: 'release',
    );
    expect(snapshot.toJson, throwsFormatException);
  });
}
