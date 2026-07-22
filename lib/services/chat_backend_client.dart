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

  ChatBackendException(AppErrorCode code)
      : descriptor = AppErrorCatalog.describe(code);

  String get safeMessage => descriptor.userMessage;
  AppErrorCode get errorCode => descriptor.code;

  @override
  String toString() => 'ChatBackendException(${errorCode.value})';
}

final class ChatBackendTimeoutException extends ChatBackendException {
  ChatBackendTimeoutException() : super(AppErrorCode.timeout);
}

final class ChatBackendHttpException extends ChatBackendException {
  final int statusCode;

  ChatBackendHttpException(this.statusCode)
      : super(AppErrorCode.serviceUnavailable);
}

final class ChatBackendMalformedResponseException extends ChatBackendException {
  ChatBackendMalformedResponseException()
      : super(AppErrorCode.serviceUnavailable);
}

final class ChatBackendConnectionException extends ChatBackendException {
  ChatBackendConnectionException() : super(AppErrorCode.networkUnavailable);
}

final class ChatBackendQuotaExceededException extends ChatBackendException {
  ChatBackendQuotaExceededException() : super(AppErrorCode.resourceExhausted);
}

final class ChatBackendAuthenticationException extends ChatBackendException {
  ChatBackendAuthenticationException() : super(AppErrorCode.unauthenticated);
}

final class ChatBackendCallableException extends ChatBackendException {
  final String code;

  ChatBackendCallableException(this.code, AppErrorCode errorCode)
      : super(errorCode);
}
