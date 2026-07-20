import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/chat_backend_request.dart';
import 'package:moms_ai/services/callable_chat_backend_client.dart';
import 'package:moms_ai/services/chat_backend_client.dart';
import 'package:moms_ai/services/http_chat_backend_client.dart';

void main() {
  const request = ChatBackendRequest(
    message: 'Organise ma journée',
    profile: {'firstName': 'Sophie'},
    profileContext: {'work': {}},
    memories: [
      {'text': 'Routine'},
    ],
    memoryReasoning: [
      {'type': 'routine'},
    ],
    events: [
      {'title': 'École'},
    ],
  );

  test('wires production callable metadata, timeout, payload and result',
      () async {
    late String capturedRegion;
    late String capturedFunctionName;
    late Duration capturedTimeout;
    late Map<String, dynamic> capturedPayload;
    final backend = CallableChatBackendClient(
      callableFactory: ({
        required region,
        required functionName,
        required timeout,
        functions,
      }) {
        capturedRegion = region;
        capturedFunctionName = functionName;
        capturedTimeout = timeout;
        return (payload) async {
          capturedPayload = payload;
          return {'reply': 'Réponse', 'actions': [], 'memories': []};
        };
      },
    );

    final response = await backend.send(request);

    expect(capturedRegion, 'us-central1');
    expect(capturedFunctionName, 'chatWithZeliaCallable');
    expect(capturedTimeout, const Duration(seconds: 30));
    expect(capturedPayload, request.toJson());
    expect(response.reply, 'Réponse');
  });

  test('sends the exact existing request contract', () async {
    late Map<String, dynamic> sentData;
    final backend = CallableChatBackendClient.withInvoker((data) async {
      sentData = data;
      return {'reply': 'Réponse', 'actions': [], 'memories': []};
    });

    await backend.send(request);

    expect(sentData, request.toJson());
    expect(sentData.keys, {
      'message',
      'profile',
      'profileContext',
      'memories',
      'memoryReasoning',
      'events',
    });
  });

  test('normalizes callable result maps', () async {
    final backend = CallableChatBackendClient.withInvoker((_) async {
      return <Object?, Object?>{
        'reply': 'Voici la réponse',
        'actions': [
          {'type': 'task', 'title': 'Appeler'},
        ],
        'memories': [],
      };
    });

    final response = await backend.send(request);

    expect(response.reply, 'Voici la réponse');
    expect(response.actions, hasLength(1));
    expect(response.memories, isEmpty);
  });

  test('preserves response fallbacks for missing fields', () async {
    final backend = CallableChatBackendClient.withInvoker((_) async => {});

    final response = await backend.send(request);

    expect(response.reply, 'C’est noté 💕');
    expect(response.actions, isEmpty);
    expect(response.memories, isEmpty);
  });

  test('rejects malformed callable result data', () async {
    final backend = CallableChatBackendClient.withInvoker(
      (_) async => 'invalid',
    );

    await expectLater(
      backend.send(request),
      throwsA(isA<ChatBackendMalformedResponseException>()),
    );
  });

  test('maps callable deadline errors to timeout', () async {
    final backend = CallableChatBackendClient.withInvoker((_) async {
      throw FirebaseFunctionsException(
        message: 'deadline detail',
        code: 'deadline-exceeded',
      );
    });

    await expectLater(
      backend.send(request),
      throwsA(isA<ChatBackendTimeoutException>()),
    );
  });

  test('maps callable unavailability to connection failure', () async {
    final backend = CallableChatBackendClient.withInvoker((_) async {
      throw FirebaseFunctionsException(
        message: 'network detail',
        code: 'unavailable',
      );
    });

    await expectLater(
      backend.send(request),
      throwsA(isA<ChatBackendConnectionException>()),
    );
  });

  test('maps callable internal errors like the legacy HTTP 500', () async {
    final backend = CallableChatBackendClient.withInvoker((_) async {
      throw FirebaseFunctionsException(
        message: 'private detail',
        code: 'internal',
      );
    });

    await expectLater(
      backend.send(request),
      throwsA(
        isA<ChatBackendHttpException>()
            .having((error) => error.statusCode, 'statusCode', 500),
      ),
    );
  });

  test('maps other callable errors without exposing details', () async {
    final backend = CallableChatBackendClient.withInvoker((_) async {
      throw FirebaseFunctionsException(
        message: 'private auth detail',
        code: 'invalid-argument',
      );
    });

    await expectLater(
      backend.send(request),
      throwsA(
        isA<ChatBackendCallableException>()
            .having((error) => error.code, 'code', 'invalid-argument')
            .having(
              (error) => error.safeMessage,
              'safeMessage',
              isNot(contains('private auth detail')),
            ),
      ),
    );
  });

  test('maps injected invoker timeouts', () async {
    final backend = CallableChatBackendClient.withInvoker((_) async {
      throw TimeoutException('timeout detail');
    });

    await expectLater(
      backend.send(request),
      throwsA(isA<ChatBackendTimeoutException>()),
    );
  });

  test('allows unexpected exceptions to propagate unchanged', () async {
    final error = StateError('programming failure');
    final backend = CallableChatBackendClient.withInvoker((_) async {
      throw error;
    });

    await expectLater(backend.send(request), throwsA(same(error)));
  });

  test('uses callable as the single default transport seam', () {
    final factorySource = File('lib/services/chat_backend_client_factory.dart')
        .readAsStringSync();
    expect(factorySource, contains('return CallableChatBackendClient();'));
    expect(factorySource, isNot(contains('return HttpChatBackendClient();')));

    final screenSources = Directory('lib/screens')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');
    expect(screenSources, contains('createDefaultChatBackendClient()'));
    expect(screenSources, isNot(contains('HttpChatBackendClient(')));
    expect(screenSources, isNot(contains('CallableChatBackendClient(')));

    final defaultSelectionOccurrences = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n')
        .split('createDefaultChatBackendClient')
        .length;
    expect(defaultSelectionOccurrences, 3);
  });

  test('keeps HTTP independently constructible for rollback', () {
    final backend = HttpChatBackendClient();

    expect(backend, isA<HttpChatBackendClient>());
    backend.close();
  });
}
