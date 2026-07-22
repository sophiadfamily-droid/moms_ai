import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/services/firebase_security_bootstrap.dart';

void main() {
  group('environment policy', () {
    test('defaults debug builds to debug and releases to production', () {
      expect(
        ZeliaFirebaseEnvironmentPolicy.resolve(
          configured: '',
          isRelease: false,
        ),
        ZeliaFirebaseEnvironment.debug,
      );
      expect(
        ZeliaFirebaseEnvironmentPolicy.resolve(
          configured: '',
          isRelease: true,
        ),
        ZeliaFirebaseEnvironment.production,
      );
    });

    test('unknown values fail closed to production', () {
      expect(
        ZeliaFirebaseEnvironmentPolicy.resolve(
          configured: 'unexpected',
          isRelease: false,
        ),
        ZeliaFirebaseEnvironment.production,
      );
    });

    test('release cannot select debug or emulator', () {
      for (final value in ['debug', 'emulator']) {
        expect(
          () => ZeliaFirebaseEnvironmentPolicy.resolve(
            configured: value,
            isRelease: true,
          ),
          throwsA(isA<FirebaseSecurityBootstrapException>()),
        );
      }
    });

    test('staging and production require production App Check', () {
      expect(
          ZeliaFirebaseEnvironment.staging.requiresProductionAppCheck, isTrue);
      expect(ZeliaFirebaseEnvironment.production.requiresProductionAppCheck,
          isTrue);
      expect(ZeliaFirebaseEnvironment.debug.usesDebugAppCheck, isTrue);
      expect(ZeliaFirebaseEnvironment.emulator.usesFirebaseEmulators, isTrue);
    });
  });

  test('initializes environment, App Check then Auth exactly once', () async {
    final order = <String>[];
    final authCompleter = Completer<String>();
    var authCalls = 0;
    final bootstrap = FirebaseSecurityBootstrap(
      configureEnvironment: () async => order.add('environment'),
      activateAppCheck: () async => order.add('app-check'),
      ensureAuthenticatedUid: () {
        authCalls++;
        order.add('auth');
        return authCompleter.future;
      },
    );

    final first = bootstrap.initialize();
    final second = bootstrap.initialize();
    await Future<void>.delayed(Duration.zero);
    expect(order, ['environment', 'app-check', 'auth']);
    expect(authCalls, 1);

    authCompleter.complete('uid');
    expect(await Future.wait([first, second]), ['uid', 'uid']);
  });
}
