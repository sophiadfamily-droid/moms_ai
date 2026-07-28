import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'app_diagnostics.dart';
import 'chat_backend_client.dart';

enum AppErrorBoundaryKind {
  application,
  contract,
  localStorage,
  synchronization,
  provider,
}

final class AppErrorClassifier {
  const AppErrorClassifier._();

  static AppErrorDescriptor classify(
    Object error, {
    AppErrorBoundaryKind boundary = AppErrorBoundaryKind.application,
    String? correlationId,
  }) {
    if (error is ChatBackendException) return error.descriptor;
    final code = switch (error) {
      TimeoutException() => AppErrorCode.timeout,
      FirebaseFunctionsException(code: 'unauthenticated') =>
        AppErrorCode.unauthenticated,
      FirebaseFunctionsException(code: 'permission-denied') =>
        AppErrorCode.permissionDenied,
      FirebaseFunctionsException(code: 'invalid-argument') =>
        AppErrorCode.invalidArgument,
      FirebaseFunctionsException(code: 'resource-exhausted') =>
        AppErrorCode.resourceExhausted,
      FirebaseFunctionsException(code: 'deadline-exceeded') =>
        AppErrorCode.timeout,
      FirebaseFunctionsException(code: 'unavailable') =>
        AppErrorCode.networkUnavailable,
      FirebaseFunctionsException(code: 'aborted') => AppErrorCode.conflict,
      FirebaseException(code: 'unauthenticated') =>
        AppErrorCode.unauthenticated,
      FirebaseException(code: 'permission-denied') =>
        AppErrorCode.permissionDenied,
      FirebaseException(code: 'invalid-argument') =>
        AppErrorCode.invalidArgument,
      FirebaseException(code: 'deadline-exceeded') => AppErrorCode.timeout,
      FirebaseException(code: 'unavailable') => AppErrorCode.networkUnavailable,
      FirebaseException(code: 'aborted') => AppErrorCode.conflict,
      FormatException() when boundary == AppErrorBoundaryKind.contract =>
        AppErrorCode.contractFailure,
      FormatException() => AppErrorCode.invalidArgument,
      _ when boundary == AppErrorBoundaryKind.contract =>
        AppErrorCode.contractFailure,
      _ when boundary == AppErrorBoundaryKind.localStorage =>
        AppErrorCode.storageFailure,
      _ when boundary == AppErrorBoundaryKind.synchronization =>
        AppErrorCode.syncFailure,
      _ when boundary == AppErrorBoundaryKind.provider =>
        AppErrorCode.providerFailure,
      _ => AppErrorCode.internalFailure,
    };
    return AppErrorCatalog.describe(code, correlationId: correlationId);
  }

  static String safeExceptionType(Object error) => switch (error) {
        TimeoutException() => 'TimeoutException',
        FirebaseFunctionsException() => 'FirebaseFunctionsException',
        FirebaseException() => 'FirebaseException',
        FormatException() => 'FormatException',
        StateError() => 'StateError',
        ArgumentError() => 'ArgumentError',
        ChatBackendException() => 'ChatBackendException',
        _ => 'UnknownException',
      };
}
