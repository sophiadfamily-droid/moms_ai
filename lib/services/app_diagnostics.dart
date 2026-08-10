import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppDiagnosticEnvironment { emulator, debug, staging, production }

enum AppErrorCode {
  unauthenticated('unauthenticated'),
  appCheckRequired('app-check-required'),
  permissionDenied('permission-denied'),
  invalidArgument('invalid-argument'),
  contractFailure('contract-failure'),
  resourceExhausted('resource-exhausted'),
  networkUnavailable('network-unavailable'),
  timeout('timeout'),
  serviceUnavailable('service-unavailable'),
  dependencyUnavailable('dependency-unavailable'),
  providerFailure('provider-failure'),
  configurationFailure('configuration-failure'),
  conflict('conflict'),
  staleRevision('stale-revision'),
  staleResult('stale-result'),
  accountScopeMismatch('account-scope-mismatch'),
  notFound('not-found'),
  cancelled('cancelled'),
  storageFailure('storage-failure'),
  syncPending('sync-pending'),
  syncFailure('sync-failure'),
  permanentlyFailed('permanently-failed'),
  lifecycleEvent('lifecycle-event'),
  proactiveShow('proactive-show'),
  proactiveNoShow('proactive-no-show'),
  proactivePersistenceFailure('proactive-persistence-failure'),
  internalFailure('internal-failure'),
  unknown('unknown');

  const AppErrorCode(this.value);
  final String value;
}

enum AppErrorCategory {
  authentication,
  authorization,
  validation,
  contract,
  quota,
  network,
  timeout,
  availability,
  dependency,
  provider,
  configuration,
  concurrency,
  accountScope,
  staleResult,
  persistence,
  synchronization,
  lifecycle,
  cancellation,
  internal,
  unknown,
}

enum AppErrorSeverity {
  info,
  warning,
  recoverableError,
  criticalError,
}

enum AppRetryStrategy {
  notRetryable,
  retryImmediately,
  retryWithBackoff,
  retryAfterUserAction,
  retryAfterReauthentication,
}

final class AppErrorDescriptor {
  const AppErrorDescriptor({
    required this.code,
    required this.category,
    required this.severity,
    required this.userMessage,
    required this.technicalMessage,
    required this.retryStrategy,
    required this.correlationId,
  });

  final AppErrorCode code;
  final AppErrorCategory category;
  final AppErrorSeverity severity;
  final String userMessage;
  final String technicalMessage;
  final AppRetryStrategy retryStrategy;
  final String correlationId;

  bool get retryable => retryStrategy != AppRetryStrategy.notRetryable;
  bool get canRetryDirectly =>
      retryStrategy == AppRetryStrategy.retryImmediately ||
      retryStrategy == AppRetryStrategy.retryWithBackoff;
}

final class AppErrorCatalog {
  const AppErrorCatalog._();

  static AppErrorDescriptor describe(
    AppErrorCode code, {
    String? correlationId,
  }) {
    final id = AppDiagnostics.validCorrelationId(correlationId)
        ? correlationId!
        : AppDiagnostics.createCorrelationId();
    return switch (code) {
      AppErrorCode.unauthenticated => _descriptor(
          code,
          AppErrorCategory.authentication,
          'Je dois te reconnecter avant de continuer.',
          'Authenticated session required.',
          AppRetryStrategy.retryAfterReauthentication,
          id,
        ),
      AppErrorCode.appCheckRequired => _descriptor(
          code,
          AppErrorCategory.authorization,
          'Je ne peux pas vérifier l’application pour le moment. Ferme-la puis rouvre-la avant de continuer.',
          'Application attestation required.',
          AppRetryStrategy.notRetryable,
          id,
        ),
      AppErrorCode.permissionDenied => _descriptor(
          code,
          AppErrorCategory.authorization,
          'Je n’ai pas l’autorisation de faire cela.',
          'Permission denied.',
          AppRetryStrategy.notRetryable,
          id,
        ),
      AppErrorCode.invalidArgument => _descriptor(
          code,
          AppErrorCategory.validation,
          'Je n’arrive pas à utiliser certaines informations. Vérifie ta demande.',
          'Invalid input.',
          AppRetryStrategy.retryAfterUserAction,
          id,
        ),
      AppErrorCode.contractFailure => _descriptor(
          code,
          AppErrorCategory.contract,
          'Je n’ai pas réussi à comprendre la réponse. Réessaie dans un instant.',
          'Closed contract validation failed.',
          AppRetryStrategy.retryWithBackoff,
          id,
        ),
      AppErrorCode.resourceExhausted => _descriptor(
          code,
          AppErrorCategory.quota,
          'J’ai reçu beaucoup de demandes. Attends un peu avant de réessayer.',
          'Technical request quota exceeded.',
          AppRetryStrategy.retryWithBackoff,
          id,
        ),
      AppErrorCode.networkUnavailable => _descriptor(
          code,
          AppErrorCategory.network,
          'Je n’ai pas de connexion pour le moment. Réessaie quand le réseau revient.',
          'Network unavailable.',
          AppRetryStrategy.retryWithBackoff,
          id,
        ),
      AppErrorCode.timeout => _descriptor(
          code,
          AppErrorCategory.timeout,
          'Ça prend plus de temps que prévu. Tu peux réessayer.',
          'Operation timed out.',
          AppRetryStrategy.retryWithBackoff,
          id,
        ),
      AppErrorCode.serviceUnavailable ||
      AppErrorCode.dependencyUnavailable =>
        _descriptor(
          code,
          AppErrorCategory.availability,
          'Je ne peux pas répondre pour le moment. Vérifie ta connexion Internet, puis réessaie dans un instant.',
          'Dependency temporarily unavailable.',
          AppRetryStrategy.retryWithBackoff,
          id,
        ),
      AppErrorCode.providerFailure => _descriptor(
          code,
          AppErrorCategory.provider,
          'Je ne peux pas répondre pour le moment. Vérifie ta connexion Internet, puis réessaie dans un instant.',
          'Provider operation failed.',
          AppRetryStrategy.retryWithBackoff,
          id,
        ),
      AppErrorCode.configurationFailure => _descriptor(
          code,
          AppErrorCategory.configuration,
          'Je ne peux pas continuer avec cette version de l’application.',
          'Application configuration invalid.',
          AppRetryStrategy.notRetryable,
          id,
          severity: AppErrorSeverity.criticalError,
        ),
      AppErrorCode.conflict || AppErrorCode.staleRevision => _descriptor(
          code,
          AppErrorCategory.concurrency,
          'Cette information a changé sur un autre appareil. Vérifie ce que tu veux garder.',
          'Concurrent change detected.',
          AppRetryStrategy.retryAfterUserAction,
          id,
        ),
      AppErrorCode.staleResult => _descriptor(
          code,
          AppErrorCategory.staleResult,
          'Les informations viennent de changer. Réessaie pour que je les vérifie à nouveau.',
          'Stale asynchronous result discarded.',
          AppRetryStrategy.retryImmediately,
          id,
          severity: AppErrorSeverity.warning,
        ),
      AppErrorCode.accountScopeMismatch => _descriptor(
          code,
          AppErrorCategory.accountScope,
          'Je me suis arrêtée parce que tu as changé de compte.',
          'Account scope mismatch.',
          AppRetryStrategy.notRetryable,
          id,
          severity: AppErrorSeverity.criticalError,
        ),
      AppErrorCode.notFound => _descriptor(
          code,
          AppErrorCategory.validation,
          'Je ne retrouve plus cette information.',
          'Requested resource not found.',
          AppRetryStrategy.notRetryable,
          id,
        ),
      AppErrorCode.cancelled => _descriptor(
          code,
          AppErrorCategory.cancellation,
          'D’accord, j’arrête ici.',
          'Operation cancelled.',
          AppRetryStrategy.notRetryable,
          id,
          severity: AppErrorSeverity.info,
        ),
      AppErrorCode.storageFailure => _descriptor(
          code,
          AppErrorCategory.persistence,
          'Je n’ai pas réussi à enregistrer ça. Réessaie avant de quitter.',
          'Local persistence operation failed.',
          AppRetryStrategy.retryImmediately,
          id,
        ),
      AppErrorCode.syncPending => _descriptor(
          code,
          AppErrorCategory.synchronization,
          'C’est bien enregistré ici. Je le transmettrai à tes autres appareils dès que possible.',
          'Durable local write pending cloud synchronization.',
          AppRetryStrategy.retryWithBackoff,
          id,
          severity: AppErrorSeverity.warning,
        ),
      AppErrorCode.syncFailure || AppErrorCode.permanentlyFailed => _descriptor(
          code,
          AppErrorCategory.synchronization,
          'Je n’ai pas réussi à transmettre les changements à tes autres appareils. Vérifie qu’ils sont bien enregistrés ici.',
          'Synchronization operation failed.',
          code == AppErrorCode.syncFailure
              ? AppRetryStrategy.retryWithBackoff
              : AppRetryStrategy.retryAfterUserAction,
          id,
        ),
      AppErrorCode.lifecycleEvent => _descriptor(
          code,
          AppErrorCategory.lifecycle,
          'État technique mis à jour.',
          'Closed lifecycle event observed.',
          AppRetryStrategy.notRetryable,
          id,
          severity: AppErrorSeverity.info,
        ),
      AppErrorCode.proactiveShow => _descriptor(
          code,
          AppErrorCategory.persistence,
          'J’ai une suggestion qui pourrait t’aider.',
          'Eligible proactive suggestion selected.',
          AppRetryStrategy.notRetryable,
          id,
          severity: AppErrorSeverity.info,
        ),
      AppErrorCode.proactiveNoShow => _descriptor(
          code,
          AppErrorCategory.persistence,
          'Tout est sous contrôle pour le moment.',
          'No proactive suggestion selected.',
          AppRetryStrategy.notRetryable,
          id,
          severity: AppErrorSeverity.info,
        ),
      AppErrorCode.proactivePersistenceFailure => _descriptor(
          code,
          AppErrorCategory.persistence,
          'Je n’arrive pas à afficher cette suggestion pour le moment.',
          'Proactive suggestion receipt persistence failed.',
          AppRetryStrategy.retryWithBackoff,
          id,
        ),
      AppErrorCode.internalFailure || AppErrorCode.unknown => _descriptor(
          code,
          AppErrorCategory.internal,
          'Je rencontre un problème. Tu peux réessayer.',
          'Unexpected application failure.',
          AppRetryStrategy.retryWithBackoff,
          id,
          severity: AppErrorSeverity.criticalError,
        ),
    };
  }

  static AppErrorDescriptor _descriptor(
    AppErrorCode code,
    AppErrorCategory category,
    String userMessage,
    String technicalMessage,
    AppRetryStrategy retryStrategy,
    String correlationId, {
    AppErrorSeverity severity = AppErrorSeverity.recoverableError,
  }) =>
      AppErrorDescriptor(
        code: code,
        category: category,
        severity: severity,
        userMessage: userMessage,
        technicalMessage: technicalMessage,
        retryStrategy: retryStrategy,
        correlationId: correlationId,
      );
}

typedef AppDiagnosticSink = void Function(String line);

abstract interface class AppCriticalDiagnosticReporter {
  Future<void> report(Map<String, Object?> diagnostic);
}

final class AppDiagnostics {
  const AppDiagnostics._();

  static const int schemaVersion = 1;
  static const int maximumBufferedDiagnostics = 100;
  static const int maximumEncodedBufferBytes = 256 * 1024;
  static const int maximumSafeStringLength = 80;
  static const String _storageKey = 'zelia.technicalDiagnostics.v1';
  static const String _backupStorageKey =
      'zelia.technicalDiagnostics.v1.backup';

  static AppDiagnosticEnvironment _environment = kReleaseMode
      ? AppDiagnosticEnvironment.production
      : AppDiagnosticEnvironment.debug;
  static AppDiagnosticSink _sink = debugPrint;
  static AppCriticalDiagnosticReporter? _criticalReporter;
  static SharedPreferences? _preferences;
  static final List<Map<String, Object?>> _buffer = [];
  static String? _lastDeduplicationKey;
  static DateTime? _lastRecordedAt;
  static Future<void> _persistenceTail = Future.value();

  static const Set<String> _allowedMetadata = {
    'durationMs',
    'status',
    'count',
    'retryable',
    'retryStrategy',
    'accepted',
    'attemptCount',
    'sessionGeneration',
    'state',
    'eventType',
    'result',
    'candidateCount',
    'suggestionType',
    'reasonCodes',
    'decision',
    'interactionActive',
    'tabActive',
    'historyState',
    'sessionQuotaConsumed',
    'sourceRevision',
    'evaluationGeneration',
    'revision',
    'syncStatus',
    'accountScopePresent',
    'accountScopeMatch',
    'pendingMutationCount',
    'oldestPendingMutationAgeBucket',
  };

  static const Set<String> _forbiddenNames = {
    'message',
    'title',
    'prompt',
    'content',
    'payload',
    'conversation',
    'memory',
    'profile',
    'email',
    'phone',
    'address',
    'birthdate',
    'health',
    'medical',
    'location',
    'participant',
    'token',
    'authorization',
    'appchecktoken',
    'idtoken',
    'refreshtoken',
    'secret',
    'apikey',
    'password',
    'uid',
  };

  static void configure({
    required AppDiagnosticEnvironment environment,
    AppDiagnosticSink? sink,
    AppCriticalDiagnosticReporter? criticalReporter,
  }) {
    _environment = environment;
    if (sink != null) _sink = sink;
    _criticalReporter = criticalReporter;
  }

  static Future<void> initializeLocal({
    SharedPreferences? preferences,
  }) async {
    try {
      _preferences = preferences ?? await SharedPreferences.getInstance();
      final primary = _preferences!.getString(_storageKey);
      final backup = _preferences!.getString(_backupStorageKey);
      List<Map<String, Object?>> decoded;
      if (primary == null) {
        decoded = _decodeStoredBuffer(backup);
      } else {
        try {
          decoded = _decodeStoredBuffer(primary);
        } catch (_) {
          decoded = _decodeStoredBuffer(backup);
        }
      }
      _buffer
        ..clear()
        ..addAll(decoded.take(maximumBufferedDiagnostics));
    } catch (_) {
      _buffer.clear();
      try {
        await _preferences?.remove(_storageKey);
        await _preferences?.remove(_backupStorageKey);
      } catch (_) {
        // Diagnostics must never replace the original application failure.
      }
    }
  }

  @visibleForTesting
  static void resetForTesting() {
    _buffer.clear();
    _preferences = null;
    _criticalReporter = null;
    _lastDeduplicationKey = null;
    _lastRecordedAt = null;
    _persistenceTail = Future.value();
    _sink = debugPrint;
  }

  @visibleForTesting
  static List<Map<String, Object?>> get bufferedDiagnostics =>
      _buffer.map(Map<String, Object?>.from).toList(growable: false);

  @visibleForTesting
  static Future<void> flushForTesting() => _persistenceTail;

  static String createCorrelationId() {
    final random = Random.secure();
    final values = List<int>.generate(16, (_) => random.nextInt(256));
    return values
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static bool validCorrelationId(String? value) =>
      value != null && RegExp(r'^[0-9a-f]{32}$').hasMatch(value);

  static void record({
    required String component,
    required String step,
    required AppErrorCode code,
    String domain = 'application',
    String operation = 'observe',
    AppErrorSeverity? severity,
    AppRetryStrategy? retryStrategy,
    String? correlationId,
    String? technicalStatus,
    String? sourceExceptionType,
    Map<String, Object?> metadata = const {},
  }) {
    try {
      final descriptor = AppErrorCatalog.describe(
        code,
        correlationId: correlationId,
      );
      final now = DateTime.now().toUtc();
      final safeComponent = _safeCode(component, fallback: 'unknown_component');
      final safeDomain = _safeCode(domain, fallback: 'application');
      final safeOperation = _safeCode(operation, fallback: 'observe');
      final safeStep = _safeCode(step, fallback: 'unknown_step');
      final safeMetadata = _sanitizeMetadata(metadata);
      final effectiveSeverity = severity ?? descriptor.severity;
      final effectiveRetryStrategy = retryStrategy ??
          (effectiveSeverity == AppErrorSeverity.info
              ? AppRetryStrategy.notRetryable
              : descriptor.retryStrategy);
      final record = <String, Object?>{
        'event': 'zelia_diagnostic',
        'schemaVersion': schemaVersion,
        'diagnosticId': createCorrelationId(),
        'correlationId': descriptor.correlationId,
        'component': safeComponent,
        'domain': safeDomain,
        'operation': safeOperation,
        'step': safeStep,
        'code': code.value,
        'severity': effectiveSeverity.name,
        'retryability': effectiveRetryStrategy.name,
        'timestamp': now.toIso8601String(),
        'environment': _environment.name,
        if (technicalStatus != null)
          'technicalStatus': _safeCode(
            technicalStatus,
            fallback: 'unknown_status',
          ),
        if (sourceExceptionType != null)
          'sourceExceptionType': _safeExceptionType(sourceExceptionType),
        ...safeMetadata,
      };
      final deduplicationKey = [
        safeComponent,
        safeDomain,
        safeOperation,
        safeStep,
        code.value,
        record['sourceExceptionType'],
      ].join('|');
      final duplicate = deduplicationKey == _lastDeduplicationKey &&
          _lastRecordedAt != null &&
          now.difference(_lastRecordedAt!) < const Duration(minutes: 1);
      _lastDeduplicationKey = deduplicationKey;
      _lastRecordedAt = now;

      final line = jsonEncode(record);
      try {
        _sink(line);
      } catch (_) {
        // A diagnostic sink is never allowed to mask the original exception.
      }
      if (!duplicate) {
        _buffer.add(record);
        _trimBuffer();
        _persistenceTail =
            _persistenceTail.then((_) => _persistBuffer()).catchError(
                  (Object _) {},
                );
      }
      if (effectiveSeverity == AppErrorSeverity.criticalError) {
        final reporter = _criticalReporter;
        if (reporter != null) {
          unawaited(reporter.report(record).catchError((Object _) {}));
        }
      }
    } catch (_) {
      // Observability is fail-safe and never recursive.
    }
  }

  static Map<String, Object?> _sanitizeMetadata(
    Map<String, Object?> metadata,
  ) {
    final result = <String, Object?>{};
    for (final entry in metadata.entries) {
      final normalized = entry.key.toLowerCase();
      if (!_allowedMetadata.contains(entry.key) ||
          _forbiddenNames.any(normalized.contains)) {
        continue;
      }
      final value = entry.value;
      if (value is num || value is bool) {
        result[entry.key] = value;
      } else if (value is String &&
          value.length <= maximumSafeStringLength &&
          RegExp(r'^[a-zA-Z0-9_.:, -]+$').hasMatch(value)) {
        result[entry.key] = value;
      }
    }
    return result;
  }

  static String _safeCode(String value, {required String fallback}) {
    final normalized = value.trim();
    if (normalized.isEmpty ||
        normalized.length > maximumSafeStringLength ||
        !RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(normalized)) {
      return fallback;
    }
    return normalized;
  }

  static String _safeExceptionType(String value) {
    const allowed = {
      'TimeoutException',
      'FirebaseException',
      'FirebaseFunctionsException',
      'FormatException',
      'StateError',
      'ArgumentError',
      'ChatBackendException',
      'ConversationTaskPersistenceException',
      'PlatformException',
      'UnknownException',
    };
    return allowed.contains(value) ? value : 'UnknownException';
  }

  static bool _validStoredDiagnostic(Map<String, Object?> value) =>
      value['schemaVersion'] == schemaVersion &&
      value['event'] == 'zelia_diagnostic' &&
      validCorrelationId(value['correlationId'] as String?) &&
      validCorrelationId(value['diagnosticId'] as String?);

  static List<Map<String, Object?>> _decodeStoredBuffer(String? raw) {
    if (raw == null) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) throw const FormatException();
    return decoded
        .whereType<Map>()
        .map((value) => Map<String, Object?>.from(value))
        .where(_validStoredDiagnostic)
        .toList(growable: false);
  }

  static void _trimBuffer() {
    while (_buffer.length > maximumBufferedDiagnostics) {
      _buffer.removeAt(0);
    }
    while (_buffer.isNotEmpty &&
        utf8.encode(jsonEncode(_buffer)).length > maximumEncodedBufferBytes) {
      _buffer.removeAt(0);
    }
  }

  static Future<void> _persistBuffer() async {
    final preferences = _preferences;
    if (preferences == null) return;
    try {
      final encoded = jsonEncode(_buffer);
      final current = preferences.getString(_storageKey);
      if (current != null) {
        await preferences.setString(_backupStorageKey, current);
      }
      await preferences.setString(_storageKey, encoded);
    } catch (_) {
      // Persistence is best effort and cannot alter application behavior.
    }
  }
}
