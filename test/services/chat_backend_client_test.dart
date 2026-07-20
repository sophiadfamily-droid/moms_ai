import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moms_ai/models/chat_backend_request.dart';
import 'package:moms_ai/models/chat_backend_response.dart';
import 'package:moms_ai/services/chat_backend_client.dart';
import 'package:moms_ai/services/http_chat_backend_client.dart';

void main() {
  const request = ChatBackendRequest(
    message: 'Organise mon rendez-vous',
    profile: {'firstName': 'Sophie'},
    profileContext: {
      'work': {'workStatus': 'full-time'},
    },
    memories: [
      {'text': 'Je travaille le soir'},
    ],
    memoryReasoning: [
      {'type': 'schedule_constraint'},
    ],
    events: [
      {'title': 'Dentiste'},
    ],
  );

  test('serializes the existing request contract without changing field names',
      () {
    expect(request.toJson(), {
      'message': 'Organise mon rendez-vous',
      'profile': {'firstName': 'Sophie'},
      'profileContext': {
        'work': {'workStatus': 'full-time'},
      },
      'memories': [
        {'text': 'Je travaille le soir'},
      ],
      'memoryReasoning': [
        {'type': 'schedule_constraint'},
      ],
      'events': [
        {'title': 'Dentiste'},
      ],
    });
  });

  test('parses the existing response contract', () {
    final response = ChatBackendResponse.fromJson({
      'reply': 'Voici la proposition',
      'actions': [
        {'type': 'task', 'title': 'Appeler'},
      ],
      'memories': [
        {'text': 'Préfère le matin'},
      ],
    });

    expect(response.reply, 'Voici la proposition');
    expect(response.actions, [
      {'type': 'task', 'title': 'Appeler'},
    ]);
    expect(response.memories, [
      {'text': 'Préfère le matin'},
    ]);
  });

  test('sends the request to the current endpoint and parses the response',
      () async {
    late http.Request capturedRequest;
    final client = MockClient((incomingRequest) async {
      capturedRequest = incomingRequest;
      return http.Response(
        jsonEncode({
          'reply': 'Réponse',
          'actions': [],
          'memories': [],
        }),
        200,
      );
    });
    final backend = HttpChatBackendClient(httpClient: client);

    final response = await backend.send(request);

    expect(capturedRequest.url, HttpChatBackendClient.defaultEndpoint);
    expect(capturedRequest.headers['content-type'], 'application/json');
    expect(jsonDecode(capturedRequest.body), request.toJson());
    expect(response.reply, 'Réponse');
  });

  test('maps a malformed response to a typed safe exception', () async {
    final backend = HttpChatBackendClient(
      httpClient: MockClient((_) async => http.Response('not-json', 200)),
    );

    await expectLater(
      backend.send(request),
      throwsA(isA<ChatBackendMalformedResponseException>()),
    );
  });

  test('maps a timeout to a typed safe exception', () async {
    final backend = HttpChatBackendClient(
      httpClient: MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return http.Response('{}', 200);
      }),
      timeout: const Duration(milliseconds: 1),
    );

    await expectLater(
      backend.send(request),
      throwsA(isA<ChatBackendTimeoutException>()),
    );
  });

  test('maps a non-200 status to an exception carrying the status', () async {
    final backend = HttpChatBackendClient(
      httpClient: MockClient((_) async => http.Response('unavailable', 503)),
    );

    await expectLater(
      backend.send(request),
      throwsA(
        isA<ChatBackendHttpException>()
            .having((error) => error.statusCode, 'statusCode', 503)
            .having(
              (error) => error.safeMessage,
              'safeMessage',
              'Erreur serveur 503',
            ),
      ),
    );
  });

  test('maps HTTP client failures without exposing the raw exception',
      () async {
    final backend = HttpChatBackendClient(
      httpClient: MockClient((_) async {
        throw http.ClientException('private network detail');
      }),
    );

    await expectLater(
      backend.send(request),
      throwsA(
        isA<ChatBackendConnectionException>().having(
          (error) => error.safeMessage,
          'safeMessage',
          isNot(contains('private network detail')),
        ),
      ),
    );
  });

  test('does not close an injected HTTP client', () {
    final httpClient = _TrackingClient();
    final backend = HttpChatBackendClient(httpClient: httpClient);

    backend.close();

    expect(httpClient.wasClosed, isFalse);
  });

  test('allows unexpected client errors to propagate unchanged', () async {
    final error = StateError('programming failure');
    final backend = HttpChatBackendClient(
      httpClient: _ThrowingClient(error),
    );

    await expectLater(backend.send(request), throwsA(same(error)));
  });
}

class _TrackingClient extends http.BaseClient {
  bool wasClosed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnimplementedError();
  }

  @override
  void close() {
    wasClosed = true;
  }
}

class _ThrowingClient extends http.BaseClient {
  final Object error;

  _ThrowingClient(this.error);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw error;
  }
}
