import 'callable_chat_backend_client.dart';
import 'chat_backend_client.dart';
// ignore: unused_import
import 'http_chat_backend_client.dart';

ChatBackendClient createDefaultChatBackendClient() {
  return CallableChatBackendClient();
}
