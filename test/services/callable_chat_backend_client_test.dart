import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/chat_backend_request.dart';
import 'package:moms_ai/models/conversation_context_envelope.dart';
import 'package:moms_ai/services/callable_chat_backend_client.dart';
import 'package:moms_ai/services/chat_backend_client.dart';

void main() {
  final request = ChatBackendRequest(
    message: 'Organise ma journée',
    context: ConversationContextEnvelope.unavailable(
      state: ConversationContextState.unavailable,
      generatedAt: DateTime.utc(2026, 7, 23),
      warningCode: 'test_context_unavailable',
    ),
  );

  test('wires production callable metadata, timeout, payload and result',
      () async {
    late String capturedRegion;
    late String capturedFunctionName;
    late Duration capturedTimeout;
    late Map<String, dynamic> capturedPayload;
    final backend = CallableChatBackendClient(
      ensureAuthenticatedUid: () async => 'test-authenticated-uid',
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
          return _response('Réponse');
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
      return _response('Réponse');
    });

    await backend.send(request);

    expect(sentData, request.toJson());
    expect(sentData.keys, {
      'schemaVersion',
      'message',
      'sessionGeneration',
      'conversationContext',
      'conversationHistory',
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
        ..._response('Voici la réponse'),
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

  test('refuses missing response fields without an invented fallback',
      () async {
    final backend = CallableChatBackendClient.withInvoker((_) async => {});

    await expectLater(
      backend.send(request),
      throwsA(isA<ChatBackendMalformedResponseException>()),
    );
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

  test('maps callable quota exhaustion to a stable safe exception', () async {
    final backend = CallableChatBackendClient.withInvoker((_) async {
      throw FirebaseFunctionsException(
        message: 'private quota detail',
        code: 'resource-exhausted',
      );
    });

    await expectLater(
      backend.send(request),
      throwsA(isA<ChatBackendQuotaExceededException>()),
    );
  });

  test('maps missing Firebase authentication to a stable safe exception',
      () async {
    final backend = CallableChatBackendClient.withInvoker((_) async {
      throw FirebaseFunctionsException(
        message: 'private authentication detail',
        code: 'unauthenticated',
      );
    });

    await expectLater(
      backend.send(request),
      throwsA(isA<ChatBackendAuthenticationException>()),
    );
  });

  test('waits for authentication bootstrap before invoking callable', () async {
    final order = <String>[];
    final backend = CallableChatBackendClient.withInvoker(
      (_) async {
        order.add('callable');
        return _response('Réponse');
      },
      ensureAuthenticatedUid: () async {
        order.add('auth');
        return 'uid';
      },
    );

    await backend.send(request);
    expect(order, ['auth', 'callable']);
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
    expect(screenSources, isNot(contains('createDefaultChatBackendClient()')));
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

  test('contains no legacy HTTP production endpoint', () {
    final serviceSources = Directory('lib/services')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');
    expect(serviceSources, isNot(contains('chatWithZeliaHttp')));
  });
}

Map<String, dynamic> _response(String reply) => {
      'reply': reply,
      'actions': const [],
      'memories': const [],
      'epistemic': {
        'schemaVersion': 1,
        'responseKind': 'answer',
        'epistemicState': 'grounded',
        'confidenceLevel': 'high',
        'usedSourceTypes': const ['currentUserMessage'],
        'groundingReferences': const [
          {
            'schemaVersion': 1,
            'sourceType': 'currentUserMessage',
            'section': null,
            'factKey': null,
            'freshness': 'current',
            'confirmation': 'confirmed',
            'projectionVersion': 0,
          },
        ],
        'personalClaims': const [],
        'missingInformation': const [],
        'contradictions': const [],
        'clarification': null,
        'uncertaintyCodes': const [],
        'contextStateObserved': 'unavailable',
        'warningCodes': const [],
        'responseId': 'response-test',
      },
    };
