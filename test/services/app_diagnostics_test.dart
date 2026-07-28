import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/services/app_diagnostics.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppDiagnostics.resetForTesting();
  });

  tearDown(AppDiagnostics.resetForTesting);

  test('redacts private, authentication and unknown fields', () {
    final lines = <String>[];
    AppDiagnostics.configure(
      environment: AppDiagnosticEnvironment.production,
      sink: lines.add,
    );

    AppDiagnostics.record(
      component: 'storage',
      domain: 'task',
      operation: 'write',
      step: 'local',
      code: AppErrorCode.storageFailure,
      correlationId: '0123456789abcdef0123456789abcdef',
      sourceExceptionType: 'StateError',
      metadata: {
        'message': 'conversation privée',
        'title': 'tâche privée',
        'prompt': 'prompt privé',
        'memory': 'mémoire privée',
        'profile': {'name': 'Person A'},
        'email': 'person@example.test',
        'authorization': 'Bearer private-token',
        'uid': 'private-user',
        'unknown': Object(),
        'status': 503,
        'retryable': true,
        'eventType': 'partialResult',
        'attemptCount': 1,
        'sessionGeneration': 2,
      },
    );

    expect(lines, hasLength(1));
    final line = lines.single;
    for (final sensitive in [
      'privée',
      'private',
      'example.test',
      'Bearer',
      'Person A',
    ]) {
      expect(line, isNot(contains(sensitive)));
    }
    final decoded = jsonDecode(line) as Map<String, dynamic>;
    expect(decoded['schemaVersion'], AppDiagnostics.schemaVersion);
    expect(decoded['domain'], 'task');
    expect(decoded['operation'], 'write');
    expect(decoded['status'], 503);
    expect(decoded['retryable'], isTrue);
    expect(decoded['sourceExceptionType'], 'StateError');
    expect(decoded['environment'], 'production');
  });

  test('unknown objects, exception messages and stack traces are absent', () {
    final lines = <String>[];
    AppDiagnostics.configure(
      environment: AppDiagnosticEnvironment.production,
      sink: lines.add,
    );
    AppDiagnostics.record(
      component: 'chat',
      step: 'send',
      code: AppErrorCode.internalFailure,
      sourceExceptionType:
          'StateError(person@example.test tâche-secrète private-token)',
      metadata: {
        'status': StackTrace.current,
        'message': 'person@example.test tâche-secrète private-token',
      },
    );
    expect(lines.single, isNot(contains('#0')));
    expect(lines.single, isNot(contains('example.test')));
    expect(lines.single, isNot(contains('tâche-secrète')));
    expect(
      (jsonDecode(lines.single) as Map)['sourceExceptionType'],
      'UnknownException',
    );
  });

  test('diagnostic sink and remote reporter failures are non recursive',
      () async {
    AppDiagnostics.configure(
      environment: AppDiagnosticEnvironment.production,
      sink: (_) => throw StateError('sink failed'),
      criticalReporter: _ThrowingReporter(),
    );
    expect(
      () => AppDiagnostics.record(
        component: 'application',
        step: 'uncaught',
        code: AppErrorCode.internalFailure,
        severity: AppErrorSeverity.criticalError,
      ),
      returnsNormally,
    );
    await Future<void>.delayed(Duration.zero);
    expect(AppDiagnostics.bufferedDiagnostics, hasLength(1));
  });

  test('local buffer is bounded, durable and tolerates corrupted storage',
      () async {
    final preferences = await SharedPreferences.getInstance();
    await AppDiagnostics.initializeLocal(preferences: preferences);
    AppDiagnostics.configure(
      environment: AppDiagnosticEnvironment.production,
      sink: (_) {},
    );
    for (var index = 0;
        index < AppDiagnostics.maximumBufferedDiagnostics + 5;
        index++) {
      AppDiagnostics.record(
        component: 'sync',
        step: 'retry_$index',
        code: AppErrorCode.syncFailure,
        metadata: {'attemptCount': index},
      );
    }
    await AppDiagnostics.flushForTesting();
    expect(
      AppDiagnostics.bufferedDiagnostics,
      hasLength(AppDiagnostics.maximumBufferedDiagnostics),
    );

    AppDiagnostics.resetForTesting();
    await AppDiagnostics.initializeLocal(preferences: preferences);
    expect(
      AppDiagnostics.bufferedDiagnostics,
      hasLength(AppDiagnostics.maximumBufferedDiagnostics),
    );

    await preferences.setString(
      'zelia.technicalDiagnostics.v1',
      '{corrupted',
    );
    AppDiagnostics.resetForTesting();
    await AppDiagnostics.initializeLocal(preferences: preferences);
    expect(AppDiagnostics.bufferedDiagnostics, isNotEmpty);

    await preferences.setString(
      'zelia.technicalDiagnostics.v1',
      '{corrupted',
    );
    await preferences.setString(
      'zelia.technicalDiagnostics.v1.backup',
      '{corrupted',
    );
    await preferences.remove('zelia.technicalDiagnostics.v1.backup');
    AppDiagnostics.resetForTesting();
    await AppDiagnostics.initializeLocal(preferences: preferences);
    expect(AppDiagnostics.bufferedDiagnostics, isEmpty);
  });

  test('identical diagnostics are deduplicated within the rotation window', () {
    AppDiagnostics.configure(
      environment: AppDiagnosticEnvironment.production,
      sink: (_) {},
    );
    for (var index = 0; index < 5; index++) {
      AppDiagnostics.record(
        component: 'sync',
        step: 'retry',
        code: AppErrorCode.timeout,
      );
    }
    expect(AppDiagnostics.bufferedDiagnostics, hasLength(1));
  });

  test('correlation identifiers use a closed non personal format', () {
    final first = AppDiagnostics.createCorrelationId();
    final second = AppDiagnostics.createCorrelationId();
    expect(first, isNot(second));
    expect(first, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(AppDiagnostics.validCorrelationId(first), isTrue);
    expect(AppDiagnostics.validCorrelationId('uid-person@example.test'), false);
  });

  test('taxonomy exposes safe messages, severities and retry strategies', () {
    for (final code in AppErrorCode.values) {
      final descriptor = AppErrorCatalog.describe(
        code,
        correlationId: '0123456789abcdef0123456789abcdef',
      );
      expect(descriptor.userMessage, isNotEmpty);
      expect(descriptor.technicalMessage, isNotEmpty);
      expect(descriptor.userMessage, isNot(contains('Firestore')));
      expect(descriptor.userMessage, isNot(contains('Function')));
    }
    expect(
      AppErrorCatalog.describe(AppErrorCode.timeout).retryStrategy,
      AppRetryStrategy.retryWithBackoff,
    );
    expect(
      AppErrorCatalog.describe(AppErrorCode.unauthenticated).retryStrategy,
      AppRetryStrategy.retryAfterReauthentication,
    );
    expect(
      AppErrorCatalog.describe(AppErrorCode.unauthenticated).canRetryDirectly,
      isFalse,
    );
    expect(
      AppErrorCatalog.describe(AppErrorCode.timeout).canRetryDirectly,
      isTrue,
    );
    expect(
      AppErrorCatalog.describe(AppErrorCode.accountScopeMismatch).severity,
      AppErrorSeverity.criticalError,
    );
    for (final code in [
      AppErrorCode.serviceUnavailable,
      AppErrorCode.internalFailure,
      AppErrorCode.unknown,
      AppErrorCode.storageFailure,
    ]) {
      expect(
        AppErrorCatalog.describe(code).userMessage,
        isNot(contains('données ne sont pas perdues')),
      );
    }
    expect(
      AppErrorCatalog.describe(AppErrorCode.syncPending).userMessage,
      contains('enregistré sur cet appareil'),
    );
  });
}

final class _ThrowingReporter implements AppCriticalDiagnosticReporter {
  @override
  Future<void> report(Map<String, Object?> diagnostic) async {
    throw StateError('reporter failed');
  }
}
