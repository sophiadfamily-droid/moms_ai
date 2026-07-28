import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'app_diagnostics.dart';
import 'app_error_classifier.dart';

final class AppGlobalErrorBoundary {
  const AppGlobalErrorBoundary._();

  static FlutterExceptionHandler? _previousFlutterHandler;
  static ErrorCallback? _previousPlatformHandler;

  static void install() {
    _previousFlutterHandler = FlutterError.onError;
    _previousPlatformHandler = PlatformDispatcher.instance.onError;
    FlutterError.onError = captureFlutterError;
    PlatformDispatcher.instance.onError = capturePlatformError;
  }

  static void captureFlutterError(FlutterErrorDetails details) {
    _record(
      details.exception,
      component: 'flutter_framework',
      step: 'uncaught_error',
    );
  }

  static bool capturePlatformError(Object error, StackTrace stackTrace) {
    _record(
      error,
      component: 'platform_dispatcher',
      step: 'uncaught_async_error',
    );
    return true;
  }

  static void captureZoneError(Object error, StackTrace stackTrace) {
    _record(
      error,
      component: 'application_zone',
      step: 'uncaught_async_error',
    );
  }

  static void captureStartupError(Object error, StackTrace stackTrace) {
    _record(
      error,
      component: 'application_startup',
      step: 'initialize',
    );
  }

  static void _record(
    Object error, {
    required String component,
    required String step,
  }) {
    final descriptor = AppErrorClassifier.classify(error);
    AppDiagnostics.record(
      component: component,
      domain: 'application',
      operation: 'handle_uncaught_error',
      step: step,
      code: descriptor.code,
      severity: AppErrorSeverity.criticalError,
      retryStrategy: descriptor.retryStrategy,
      correlationId: descriptor.correlationId,
      sourceExceptionType: AppErrorClassifier.safeExceptionType(error),
    );
  }

  @visibleForTesting
  static void resetForTesting() {
    FlutterError.onError = _previousFlutterHandler;
    PlatformDispatcher.instance.onError = _previousPlatformHandler;
    _previousFlutterHandler = null;
    _previousPlatformHandler = null;
  }
}
