import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';

import '../models/chat_backend_request.dart';
import '../models/chat_backend_response.dart';
import 'chat_backend_client.dart';
import 'auth_service.dart';

typedef ChatCallableInvoker = Future<dynamic> Function(
  Map<String, dynamic> data,
);

typedef ChatCallableFactory = ChatCallableInvoker Function({
  required String region,
  required String functionName,
  required Duration timeout,
  FirebaseFunctions? functions,
});

typedef ChatAuthenticationBootstrap = Future<String> Function();

class CallableChatBackendClient implements ChatBackendClient {
  static const functionName = 'chatWithZeliaCallable';
  static const region = 'us-central1';
  static const defaultTimeout = Duration(seconds: 30);

  final ChatCallableInvoker _invoke;
  final ChatAuthenticationBootstrap _ensureAuthenticatedUid;

  CallableChatBackendClient({
    FirebaseFunctions? functions,
    Duration timeout = defaultTimeout,
    ChatCallableFactory callableFactory = _createFirebaseInvoker,
    ChatAuthenticationBootstrap ensureAuthenticatedUid =
        AuthService.ensureAuthenticatedUid,
  })  : _ensureAuthenticatedUid = ensureAuthenticatedUid,
        _invoke = callableFactory(
          region: region,
          functionName: functionName,
          timeout: timeout,
          functions: functions,
        );

  CallableChatBackendClient.withInvoker(
    ChatCallableInvoker invoker, {
    ChatAuthenticationBootstrap? ensureAuthenticatedUid,
  })  : _invoke = invoker,
        _ensureAuthenticatedUid =
            ensureAuthenticatedUid ?? (() async => 'test-authenticated-uid');

  static ChatCallableInvoker _createFirebaseInvoker({
    required String region,
    required String functionName,
    required Duration timeout,
    FirebaseFunctions? functions,
  }) {
    final firebaseFunctions =
        functions ?? FirebaseFunctions.instanceFor(region: region);
    final callable = firebaseFunctions.httpsCallable(
      functionName,
      options: HttpsCallableOptions(timeout: timeout),
    );

    return (data) async {
      final result = await callable.call<dynamic>(data);
      return result.data;
    };
  }

  @override
  Future<ChatBackendResponse> send(ChatBackendRequest request) async {
    try {
      await _ensureAuthenticatedUid();
      final data = await _invoke(request.toJson());

      if (data is! Map) {
        throw const ChatBackendMalformedResponseException();
      }

      final Map<String, dynamic> normalized;
      try {
        normalized = Map<String, dynamic>.from(data);
      } on TypeError {
        throw const ChatBackendMalformedResponseException();
      }

      return ChatBackendResponse.fromJson(normalized);
    } on ChatBackendException {
      rethrow;
    } on TimeoutException {
      throw const ChatBackendTimeoutException();
    } on FirebaseFunctionsException catch (error) {
      switch (error.code) {
        case 'deadline-exceeded':
          throw const ChatBackendTimeoutException();
        case 'unavailable':
          throw const ChatBackendConnectionException();
        case 'resource-exhausted':
          throw const ChatBackendQuotaExceededException();
        case 'unauthenticated':
          throw const ChatBackendAuthenticationException();
        case 'internal':
          throw ChatBackendHttpException(500);
        default:
          throw ChatBackendCallableException(error.code);
      }
    }
  }
}
