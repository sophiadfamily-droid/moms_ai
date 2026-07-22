import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'auth_service.dart';
import 'app_diagnostics.dart';
import 'callable_chat_backend_client.dart';

enum ZeliaFirebaseEnvironment {
  emulator,
  debug,
  staging,
  production;

  bool get usesFirebaseEmulators => this == emulator;
  bool get usesDebugAppCheck => this == debug;
  bool get requiresProductionAppCheck => this == staging || this == production;
}

final class ZeliaFirebaseEnvironmentPolicy {
  const ZeliaFirebaseEnvironmentPolicy._();

  static ZeliaFirebaseEnvironment resolve({
    required String configured,
    required bool isRelease,
  }) {
    final value = configured.trim().toLowerCase();
    final resolved = switch (value) {
      'emulator' => ZeliaFirebaseEnvironment.emulator,
      'debug' => ZeliaFirebaseEnvironment.debug,
      'staging' => ZeliaFirebaseEnvironment.staging,
      'production' => ZeliaFirebaseEnvironment.production,
      '' => isRelease
          ? ZeliaFirebaseEnvironment.production
          : ZeliaFirebaseEnvironment.debug,
      _ => ZeliaFirebaseEnvironment.production,
    };

    if (isRelease &&
        (resolved == ZeliaFirebaseEnvironment.debug ||
            resolved == ZeliaFirebaseEnvironment.emulator)) {
      throw const FirebaseSecurityBootstrapException(
        'unsafe_release_environment',
      );
    }
    return resolved;
  }
}

typedef FirebaseSecurityOperation = Future<void> Function();
typedef FirebaseUidBootstrap = Future<String> Function();

final class FirebaseSecurityBootstrap {
  FirebaseSecurityBootstrap({
    required FirebaseSecurityOperation configureEnvironment,
    required FirebaseSecurityOperation activateAppCheck,
    required FirebaseUidBootstrap ensureAuthenticatedUid,
  })  : _configureEnvironment = configureEnvironment,
        _activateAppCheck = activateAppCheck,
        _ensureAuthenticatedUid = ensureAuthenticatedUid;

  static const _configuredEnvironment = String.fromEnvironment(
    'ZELIA_FIREBASE_ENVIRONMENT',
  );

  static FirebaseSecurityBootstrap? _productionInstance;

  final FirebaseSecurityOperation _configureEnvironment;
  final FirebaseSecurityOperation _activateAppCheck;
  final FirebaseUidBootstrap _ensureAuthenticatedUid;
  Future<String>? _inFlight;

  static Future<String> initializeProduction() {
    final environment = ZeliaFirebaseEnvironmentPolicy.resolve(
      configured: _configuredEnvironment,
      isRelease: kReleaseMode,
    );
    AppDiagnostics.configure(
      environment: switch (environment) {
        ZeliaFirebaseEnvironment.emulator => AppDiagnosticEnvironment.emulator,
        ZeliaFirebaseEnvironment.debug => AppDiagnosticEnvironment.debug,
        ZeliaFirebaseEnvironment.staging => AppDiagnosticEnvironment.staging,
        ZeliaFirebaseEnvironment.production =>
          AppDiagnosticEnvironment.production,
      },
    );
    final instance = _productionInstance ??= _createProduction(environment);
    return instance.initialize();
  }

  static FirebaseSecurityBootstrap _createProduction(
    ZeliaFirebaseEnvironment environment,
  ) {
    return FirebaseSecurityBootstrap(
      configureEnvironment: () => _configureProductionEnvironment(environment),
      activateAppCheck: () => _activateProductionAppCheck(environment),
      ensureAuthenticatedUid: AuthService.ensureAuthenticatedUid,
    );
  }

  Future<String> initialize() {
    final active = _inFlight;
    if (active != null) return active;
    final operation = _initializeOnce();
    _inFlight = operation;
    return operation;
  }

  Future<String> _initializeOnce() async {
    await _configureEnvironment();
    await _activateAppCheck();
    return _ensureAuthenticatedUid();
  }

  static Future<void> _configureProductionEnvironment(
    ZeliaFirebaseEnvironment environment,
  ) async {
    if (!environment.usesFirebaseEmulators) return;

    const host = '127.0.0.1';
    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
    FirebaseFunctions.instanceFor(region: CallableChatBackendClient.region)
        .useFunctionsEmulator(host, 5001);
  }

  static Future<void> _activateProductionAppCheck(
    ZeliaFirebaseEnvironment environment,
  ) async {
    if (environment.usesFirebaseEmulators) return;

    if (environment.usesDebugAppCheck) {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: const AndroidDebugProvider(),
        providerApple: const AppleDebugProvider(),
      );
      return;
    }

    await FirebaseAppCheck.instance.activate(
      providerAndroid: const AndroidPlayIntegrityProvider(),
      providerApple: const AppleAppAttestWithDeviceCheckFallbackProvider(),
    );
  }
}

final class FirebaseSecurityBootstrapException implements Exception {
  const FirebaseSecurityBootstrapException(this.code);

  final String code;

  @override
  String toString() => 'FirebaseSecurityBootstrapException($code)';
}
