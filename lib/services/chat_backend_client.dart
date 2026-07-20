import '../models/chat_backend_request.dart';
import '../models/chat_backend_response.dart';

abstract interface class ChatBackendClient {
  Future<ChatBackendResponse> send(ChatBackendRequest request);
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
