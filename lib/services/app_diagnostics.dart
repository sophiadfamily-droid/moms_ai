import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

enum AppDiagnosticEnvironment { emulator, debug, staging, production }

enum AppErrorCode {
  unauthenticated('unauthenticated'),
  appCheckRequired('app-check-required'),
  permissionDenied('permission-denied'),
  invalidArgument('invalid-argument'),
  resourceExhausted('resource-exhausted'),
  networkUnavailable('network-unavailable'),
  timeout('timeout'),
  serviceUnavailable('service-unavailable'),
  conflict('conflict'),
  staleRevision('stale-revision'),
  notFound('not-found'),
  cancelled('cancelled'),
  storageFailure('storage-failure'),
  syncFailure('sync-failure'),
  proactiveShow('proactive-show'),
  proactiveNoShow('proactive-no-show'),
  proactivePersistenceFailure('proactive-persistence-failure'),
  unknown('unknown');

  const AppErrorCode(this.value);
  final String value;
}

enum AppErrorCategory {
  authentication,
  authorization,
  validation,
  quota,
  network,
  availability,
  concurrency,
  persistence,
  cancellation,
  unknown,
}

enum AppErrorSeverity { info, warning, error, critical }

final class AppErrorDescriptor {
  const AppErrorDescriptor({
    required this.code,
    required this.category,
    required this.severity,
    required this.userMessage,
    required this.technicalMessage,
    required this.retryable,
    required this.correlationId,
  });

  final AppErrorCode code;
  final AppErrorCategory category;
  final AppErrorSeverity severity;
  final String userMessage;
  final String technicalMessage;
  final bool retryable;
  final String correlationId;
}

final class AppErrorCatalog {
  const AppErrorCatalog._();

  static AppErrorDescriptor describe(
    AppErrorCode code, {
    String? correlationId,
  }) {
    final id = correlationId ?? AppDiagnostics.createCorrelationId();
    return switch (code) {
      AppErrorCode.unauthenticated => _descriptor(
          code,
          AppErrorCategory.authentication,
          'Ta session doit être rétablie avant de continuer.',
          'Authenticated session required.',
          true,
          id,
        ),
      AppErrorCode.appCheckRequired => _descriptor(
          code,
          AppErrorCategory.authorization,
          'Cette version de Zélia doit être vérifiée avant de continuer.',
          'Application attestation required.',
          false,
          id,
        ),
      AppErrorCode.permissionDenied => _descriptor(
          code,
          AppErrorCategory.authorization,
          'Cette action n’est pas autorisée.',
          'Permission denied.',
          false,
          id,
        ),
      AppErrorCode.invalidArgument => _descriptor(
          code,
          AppErrorCategory.validation,
          'Certaines informations ne sont pas valides. Vérifie ta demande.',
          'Invalid input.',
          false,
          id,
        ),
      AppErrorCode.resourceExhausted => _descriptor(
          code,
          AppErrorCategory.quota,
          'Trop de demandes ont été envoyées en peu de temps. Réessaie dans un instant.',
          'Technical request quota exceeded.',
          true,
          id,
        ),
      AppErrorCode.networkUnavailable => _descriptor(
          code,
          AppErrorCategory.network,
          'La connexion semble indisponible. Réessaie dans un instant.',
          'Network unavailable.',
          true,
          id,
        ),
      AppErrorCode.timeout => _descriptor(
          code,
          AppErrorCategory.availability,
          'Zélia met trop de temps à répondre. Réessaie dans un instant.',
          'Operation timed out.',
          true,
          id,
        ),
      AppErrorCode.serviceUnavailable => _descriptor(
          code,
          AppErrorCategory.availability,
          'Zélia rencontre un problème temporaire. Tes données ne sont pas perdues.',
          'Service temporarily unavailable.',
          true,
          id,
        ),
      AppErrorCode.conflict || AppErrorCode.staleRevision => _descriptor(
          code,
          AppErrorCategory.concurrency,
          'Cette information a été modifiée ailleurs. Vérifie la version à conserver.',
          'Concurrent change detected.',
          false,
          id,
        ),
      AppErrorCode.notFound => _descriptor(
          code,
          AppErrorCategory.validation,
          'Cette information n’est plus disponible.',
          'Requested resource not found.',
          false,
          id,
        ),
      AppErrorCode.cancelled => _descriptor(
          code,
          AppErrorCategory.cancellation,
          'L’action a été annulée.',
          'Operation cancelled.',
          false,
          id,
          severity: AppErrorSeverity.info,
        ),
      AppErrorCode.storageFailure || AppErrorCode.syncFailure => _descriptor(
          code,
          AppErrorCategory.persistence,
          'La sauvegarde n’a pas pu être terminée. Tes données locales sont conservées.',
          'Persistence operation failed.',
          true,
          id,
        ),
      AppErrorCode.proactiveShow => _descriptor(
          code,
          AppErrorCategory.persistence,
          'Une suggestion utile est disponible.',
          'Eligible proactive suggestion selected.',
          false,
          id,
          severity: AppErrorSeverity.info,
        ),
      AppErrorCode.proactiveNoShow => _descriptor(
          code,
          AppErrorCategory.persistence,
          'Aucune suggestion n’est nécessaire pour le moment.',
          'No proactive suggestion selected.',
          false,
          id,
          severity: AppErrorSeverity.info,
        ),
      AppErrorCode.proactivePersistenceFailure => _descriptor(
          code,
          AppErrorCategory.persistence,
          'La suggestion ne peut pas être affichée pour le moment.',
          'Proactive suggestion receipt persistence failed.',
          true,
          id,
        ),
      AppErrorCode.unknown => _descriptor(
          code,
          AppErrorCategory.unknown,
          'Zélia rencontre un problème temporaire. Tes données ne sont pas perdues.',
          'Unexpected application failure.',
          true,
          id,
        ),
    };
  }

  static AppErrorDescriptor _descriptor(
    AppErrorCode code,
    AppErrorCategory category,
    String userMessage,
    String technicalMessage,
    bool retryable,
    String correlationId, {
    AppErrorSeverity severity = AppErrorSeverity.error,
  }) {
    return AppErrorDescriptor(
      code: code,
      category: category,
      severity: severity,
      userMessage: userMessage,
      technicalMessage: technicalMessage,
      retryable: retryable,
      correlationId: correlationId,
    );
  }
}

typedef AppDiagnosticSink = void Function(String line);

final class AppDiagnostics {
  const AppDiagnostics._();

  static AppDiagnosticEnvironment _environment = kReleaseMode
      ? AppDiagnosticEnvironment.production
      : AppDiagnosticEnvironment.debug;
  static AppDiagnosticSink _sink = debugPrint;

  static const Set<String> _allowedMetadata = {
    'durationMs',
    'status',
    'count',
    'retryable',
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
  };

  static const Set<String> _forbiddenNames = {
    'message',
    'prompt',
    'content',
    'conversation',
    'memory',
    'profile',
    'email',
    'phone',
    'address',
    'birthdate',
    'health',
    'medical',
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
  }) {
    _environment = environment;
    if (sink != null) _sink = sink;
  }

  static String createCorrelationId() {
    final random = Random.secure();
    final values = List<int>.generate(16, (_) => random.nextInt(256));
    return values
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static void record({
    required String component,
    required String step,
    required AppErrorCode code,
    AppErrorSeverity severity = AppErrorSeverity.error,
    String? correlationId,
    Map<String, Object?> metadata = const {},
  }) {
    final safeMetadata = <String, Object?>{};
    for (final entry in metadata.entries) {
      final normalized = entry.key.toLowerCase();
      if (!_allowedMetadata.contains(entry.key) ||
          _forbiddenNames.any(normalized.contains)) {
        continue;
      }
      final value = entry.value;
      if (value is String || value is num || value is bool) {
        safeMetadata[entry.key] = value;
      }
    }

    _sink(jsonEncode({
      'event': 'zelia_diagnostic',
      'component': component,
      'step': step,
      'code': code.value,
      'severity': severity.name,
      'environment': _environment.name,
      'correlationId': correlationId ?? createCorrelationId(),
      ...safeMetadata,
    }));
  }
}
