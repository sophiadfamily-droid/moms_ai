import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_backend_request.dart';
import '../models/chat_backend_response.dart';
import 'chat_backend_client.dart';

class HttpChatBackendClient implements ChatBackendClient {
  static final Uri defaultEndpoint = Uri.parse(
    'https://us-central1-zelia-ai-app.cloudfunctions.net/chatWithZeliaHttp',
  );

  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Uri endpoint;
  final Duration timeout;

  HttpChatBackendClient({
    http.Client? httpClient,
    Uri? endpoint,
    this.timeout = const Duration(seconds: 30),
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        endpoint = endpoint ?? defaultEndpoint;

  void close() {
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }

  @override
  Future<ChatBackendResponse> send(ChatBackendRequest request) async {
    try {
      final response = await _httpClient
          .post(
            endpoint,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(request.toJson()),
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        throw ChatBackendHttpException(response.statusCode);
      }

      final dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        throw const ChatBackendMalformedResponseException();
      }

      if (decoded is! Map<String, dynamic>) {
        throw const ChatBackendMalformedResponseException();
      }

      return ChatBackendResponse.fromJson(decoded);
    } on ChatBackendException {
      rethrow;
    } on TimeoutException {
      throw const ChatBackendTimeoutException();
    } on http.ClientException {
      throw const ChatBackendConnectionException();
    }
  }
}
