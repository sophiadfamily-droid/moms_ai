import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/main.dart';
import 'package:moms_ai/services/app_diagnostics.dart';
import 'package:moms_ai/services/app_global_error_boundary.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppDiagnostics.resetForTesting();
  });

  tearDown(() {
    AppGlobalErrorBoundary.resetForTesting();
    AppDiagnostics.resetForTesting();
  });

  test('captures Flutter framework failures without private exception text',
      () {
    final lines = <String>[];
    var unsafePreviousHandlerCalled = false;
    FlutterError.onError = (_) => unsafePreviousHandlerCalled = true;
    AppDiagnostics.configure(
      environment: AppDiagnosticEnvironment.production,
      sink: lines.add,
    );
    AppGlobalErrorBoundary.install();

    AppGlobalErrorBoundary.captureFlutterError(
      FlutterErrorDetails(
        exception: StateError('person@example.test private task title'),
      ),
    );

    expect(lines, isNotEmpty);
    expect(lines.last, isNot(contains('example.test')));
    final diagnostic = jsonDecode(lines.last) as Map<String, dynamic>;
    expect(diagnostic['component'], 'flutter_framework');
    expect(diagnostic['severity'], 'criticalError');
    expect(unsafePreviousHandlerCalled, isFalse);
  });

  test('captures asynchronous platform failures and marks them handled', () {
    final lines = <String>[];
    AppDiagnostics.configure(
      environment: AppDiagnosticEnvironment.production,
      sink: lines.add,
    );
    expect(
      AppGlobalErrorBoundary.capturePlatformError(
        StateError('private message'),
        StackTrace.current,
      ),
      isTrue,
    );
    expect(lines.single, contains('platform_dispatcher'));
  });

  test('captures startup failures with a closed diagnostic', () {
    final lines = <String>[];
    AppDiagnostics.configure(
      environment: AppDiagnosticEnvironment.production,
      sink: lines.add,
    );
    AppGlobalErrorBoundary.captureStartupError(
      StateError('private firebase config'),
      StackTrace.current,
    );
    expect(lines.single, contains('application_startup'));
    expect(lines.single, isNot(contains('private firebase config')));
  });

  testWidgets('startup failure renders a bounded fallback instead of blank UI',
      (tester) async {
    await tester.pumpWidget(const ZeliaStartupFailureApp());
    expect(find.textContaining('n’a pas pu démarrer'), findsOneWidget);
    expect(find.textContaining('Firebase'), findsNothing);
  });
}
