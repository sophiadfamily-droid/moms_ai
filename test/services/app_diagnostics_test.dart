import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/services/app_diagnostics.dart';

void main() {
  test('redacts personal, authentication, medical and unknown fields', () {
    final lines = <String>[];
    AppDiagnostics.configure(
      environment: AppDiagnosticEnvironment.production,
      sink: lines.add,
    );

    AppDiagnostics.record(
      component: 'storage',
      step: 'write',
      code: AppErrorCode.storageFailure,
      correlationId: 'technical-correlation',
      metadata: {
        'message': 'conversation privée',
        'prompt': 'prompt privé',
        'memory': 'mémoire privée',
        'profile': {'name': 'Person A'},
        'health': 'donnée médicale',
        'authorization': 'Bearer private-token',
        'appCheckToken': 'private-app-check',
        'idToken': 'private-id-token',
        'refreshToken': 'private-refresh-token',
        'secret': 'private-secret',
        'unknown': Object(),
        'status': 503,
        'retryable': true,
        'transcript': 'dictée privée',
        'eventType': 'partialResult',
        'accepted': true,
        'attemptCount': 1,
        'sessionGeneration': 2,
        'state': 'receivingPartialResult',
      },
    );

    expect(lines, hasLength(1));
    expect(lines.single, isNot(contains('privé')));
    expect(lines.single, isNot(contains('private')));
    final decoded = jsonDecode(lines.single) as Map<String, dynamic>;
    expect(decoded['status'], 503);
    expect(decoded['retryable'], isTrue);
    expect(decoded['eventType'], 'partialResult');
    expect(decoded['accepted'], isTrue);
    expect(decoded['attemptCount'], 1);
    expect(decoded['sessionGeneration'], 2);
    expect(decoded['state'], 'receivingPartialResult');
    expect(decoded, isNot(contains('transcript')));
    expect(decoded['environment'], 'production');
  });

  test('unknown objects and stack traces are never serialized', () {
    final lines = <String>[];
    AppDiagnostics.configure(
      environment: AppDiagnosticEnvironment.production,
      sink: lines.add,
    );
    AppDiagnostics.record(
      component: 'chat',
      step: 'send',
      code: AppErrorCode.unknown,
      metadata: {'status': StackTrace.current},
    );
    expect(lines.single, isNot(contains('#0')));
    expect(jsonDecode(lines.single), isNot(contains('status')));
  });

  test('correlation identifiers are random and non personal', () {
    final first = AppDiagnostics.createCorrelationId();
    final second = AppDiagnostics.createCorrelationId();
    expect(first, isNot(second));
    expect(first, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(first, isNot(contains('uid')));
  });

  test('taxonomy exposes stable French messages and retry policy', () {
    expect(AppErrorCode.values, hasLength(15));
    for (final code in AppErrorCode.values) {
      final descriptor = AppErrorCatalog.describe(
        code,
        correlationId: 'technical-correlation',
      );
      expect(descriptor.userMessage, isNotEmpty);
      expect(descriptor.technicalMessage, isNotEmpty);
      expect(descriptor.correlationId, 'technical-correlation');
      expect(descriptor.userMessage, isNot(contains('Firestore')));
      expect(descriptor.userMessage, isNot(contains('Function')));
    }
    expect(
      AppErrorCatalog.describe(AppErrorCode.networkUnavailable).retryable,
      isTrue,
    );
    expect(
      AppErrorCatalog.describe(AppErrorCode.conflict).retryable,
      isFalse,
    );
  });
}
