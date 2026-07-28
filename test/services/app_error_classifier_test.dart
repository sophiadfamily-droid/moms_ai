import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/services/app_diagnostics.dart';
import 'package:moms_ai/services/app_error_classifier.dart';

void main() {
  test('classifies retry and security boundaries deterministically', () {
    expect(
      AppErrorClassifier.classify(TimeoutException('private')).code,
      AppErrorCode.timeout,
    );
    expect(
      AppErrorClassifier.classify(
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
      ).code,
      AppErrorCode.networkUnavailable,
    );
    expect(
      AppErrorClassifier.classify(
        FirebaseFunctionsException(
          code: 'permission-denied',
          message: 'private',
        ),
      ).code,
      AppErrorCode.permissionDenied,
    );
    expect(
      AppErrorClassifier.classify(
        FirebaseFunctionsException(
          code: 'unauthenticated',
          message: 'private',
        ),
      ).retryStrategy,
      AppRetryStrategy.retryAfterReauthentication,
    );
  });

  test('distinguishes invalid input, contracts, storage and internal failures',
      () {
    expect(
      AppErrorClassifier.classify(const FormatException()).code,
      AppErrorCode.invalidArgument,
    );
    expect(
      AppErrorClassifier.classify(
        const FormatException(),
        boundary: AppErrorBoundaryKind.contract,
      ).code,
      AppErrorCode.contractFailure,
    );
    expect(
      AppErrorClassifier.classify(
        StateError('private task title'),
        boundary: AppErrorBoundaryKind.localStorage,
      ).code,
      AppErrorCode.storageFailure,
    );
    expect(
      AppErrorClassifier.classify(StateError('private')).code,
      AppErrorCode.internalFailure,
    );
  });
}
