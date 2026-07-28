import '../models/chat_backend_request.dart';
import '../models/chat_backend_response.dart';
import 'app_diagnostics.dart';

abstract interface class ChatBackendClient {
  Future<ChatBackendResponse> send(ChatBackendRequest request);
}

abstract interface class ClosableChatBackendClient
    implements ChatBackendClient {
  void close();
}

sealed class ChatBackendException implements Exception {
  final AppErrorDescriptor descriptor;

  ChatBackendException(AppErrorCode code, {String? correlationId})
      : descriptor = AppErrorCatalog.describe(
          code,
          correlationId: correlationId,
        );

  String get safeMessage => descriptor.userMessage;
  AppErrorCode get errorCode => descriptor.code;

  @override
  String toString() => 'ChatBackendException(${errorCode.value})';
}

final class ChatBackendTimeoutException extends ChatBackendException {
  ChatBackendTimeoutException({String? correlationId})
      : super(AppErrorCode.timeout, correlationId: correlationId);
}

final class ChatBackendHttpException extends ChatBackendException {
  final int statusCode;

  ChatBackendHttpException(this.statusCode, {String? correlationId})
      : super(AppErrorCode.serviceUnavailable, correlationId: correlationId);
}

final class ChatBackendMalformedResponseException extends ChatBackendException {
  ChatBackendMalformedResponseException({String? correlationId})
      : super(AppErrorCode.contractFailure, correlationId: correlationId);
}

final class ChatBackendConnectionException extends ChatBackendException {
  ChatBackendConnectionException({String? correlationId})
      : super(AppErrorCode.networkUnavailable, correlationId: correlationId);
}

final class ChatBackendQuotaExceededException extends ChatBackendException {
  ChatBackendQuotaExceededException({String? correlationId})
      : super(AppErrorCode.resourceExhausted, correlationId: correlationId);
}

final class ChatBackendAuthenticationException extends ChatBackendException {
  ChatBackendAuthenticationException({String? correlationId})
      : super(AppErrorCode.unauthenticated, correlationId: correlationId);
}

final class ChatBackendCallableException extends ChatBackendException {
  final String code;

  ChatBackendCallableException(
    this.code,
    AppErrorCode errorCode, {
    String? correlationId,
  }) : super(errorCode, correlationId: correlationId);
}
