import 'dart:async';

typedef FirebaseCurrentUid = String? Function();
typedef FirebaseAnonymousSignIn = Future<String> Function();

final class FirebaseAnonymousAuthBootstrap {
  FirebaseAnonymousAuthBootstrap({
    required FirebaseCurrentUid currentUid,
    required FirebaseAnonymousSignIn signInAnonymously,
  })  : _currentUid = currentUid,
        _signInAnonymously = signInAnonymously;

  final FirebaseCurrentUid _currentUid;
  final FirebaseAnonymousSignIn _signInAnonymously;
  Future<String>? _inFlight;

  Future<String> ensureAuthenticatedUid() {
    final existing = _validUid(_currentUid());
    if (existing != null) return Future<String>.value(existing);

    final active = _inFlight;
    if (active != null) return active;

    final operation = _authenticate();
    _inFlight = operation;
    operation.then<void>(
      (_) {
        if (identical(_inFlight, operation)) _inFlight = null;
      },
      onError: (_) {
        if (identical(_inFlight, operation)) _inFlight = null;
      },
    );
    return operation;
  }

  Future<String> _authenticate() async {
    final uid = _validUid(await _signInAnonymously());
    if (uid == null) {
      throw const FirebaseAnonymousAuthException(
        'anonymous_auth_missing_uid',
      );
    }
    return uid;
  }

  String? _validUid(String? value) {
    final uid = value?.trim();
    return uid == null || uid.isEmpty ? null : uid;
  }
}

final class FirebaseAnonymousAuthException implements Exception {
  const FirebaseAnonymousAuthException(this.code);

  final String code;

  @override
  String toString() => 'FirebaseAnonymousAuthException($code)';
}
