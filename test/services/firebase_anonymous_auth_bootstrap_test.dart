import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/services/firebase_anonymous_auth_bootstrap.dart';

void main() {
  test('reuses an existing authenticated UID without signing in', () async {
    var signInCalls = 0;
    final bootstrap = FirebaseAnonymousAuthBootstrap(
      currentUid: () => 'existing-uid',
      signInAnonymously: () async {
        signInCalls++;
        return 'new-uid';
      },
    );

    expect(await bootstrap.ensureAuthenticatedUid(), 'existing-uid');
    expect(signInCalls, 0);
  });

  test('creates one anonymous session for concurrent startup calls', () async {
    final completer = Completer<String>();
    var signInCalls = 0;
    final bootstrap = FirebaseAnonymousAuthBootstrap(
      currentUid: () => null,
      signInAnonymously: () {
        signInCalls++;
        return completer.future;
      },
    );

    final first = bootstrap.ensureAuthenticatedUid();
    final second = bootstrap.ensureAuthenticatedUid();
    final third = bootstrap.ensureAuthenticatedUid();
    expect(signInCalls, 1);

    completer.complete('anonymous-uid');
    expect(await Future.wait([first, second, third]),
        everyElement('anonymous-uid'));
    expect(signInCalls, 1);
  });

  test('surfaces network failure without retry loop or false UID', () async {
    var signInCalls = 0;
    final bootstrap = FirebaseAnonymousAuthBootstrap(
      currentUid: () => null,
      signInAnonymously: () async {
        signInCalls++;
        throw StateError('offline');
      },
    );

    await expectLater(
      bootstrap.ensureAuthenticatedUid(),
      throwsA(isA<StateError>()),
    );
    expect(signInCalls, 1);
  });

  test('rejects an authentication result without UID', () async {
    final bootstrap = FirebaseAnonymousAuthBootstrap(
      currentUid: () => null,
      signInAnonymously: () async => '   ',
    );

    await expectLater(
      bootstrap.ensureAuthenticatedUid(),
      throwsA(
        isA<FirebaseAnonymousAuthException>().having(
          (error) => error.code,
          'code',
          'anonymous_auth_missing_uid',
        ),
      ),
    );
  });
}
