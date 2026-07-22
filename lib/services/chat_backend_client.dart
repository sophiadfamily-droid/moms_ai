import '../models/chat_backend_request.dart';
import '../models/chat_backend_response.dart';

abstract interface class ChatBackendClient {
  Future<ChatBackendResponse> send(ChatBackendRequest request);
}

abstract interface class ClosableChatBackendClient
    implements ChatBackendClient {
  void close();
}

sealed class ChatBackendException implements Exception {
  final String safeMessage;

  const ChatBackendException(this.safeMessage);

  @override
  String toString() => 'Exception: $safeMessage';
}

final class ChatBackendTimeoutException extends ChatBackendException {
  const ChatBackendTimeoutException()
      : super('Le service met trop de temps à répondre. Réessaie plus tard.');
}

final class ChatBackendHttpException extends ChatBackendException {
  final int statusCode;

  ChatBackendHttpException(this.statusCode)
      : super('Erreur serveur $statusCode');
}

final class ChatBackendMalformedResponseException extends ChatBackendException {
  const ChatBackendMalformedResponseException()
      : super('La réponse du service est invalide.');
}

final class ChatBackendConnectionException extends ChatBackendException {
  const ChatBackendConnectionException()
      : super('Impossible de contacter le service pour le moment.');
}

final class ChatBackendQuotaExceededException extends ChatBackendException {
  const ChatBackendQuotaExceededException()
      : super('La limite de requêtes est atteinte. Réessaie plus tard.');
}

final class ChatBackendAuthenticationException extends ChatBackendException {
  const ChatBackendAuthenticationException()
      : super('Une session sécurisée est nécessaire. Réessaie plus tard.');
}

final class ChatBackendCallableException extends ChatBackendException {
  final String code;

  ChatBackendCallableException(this.code)
      : super('Le service est momentanément indisponible.');
}
