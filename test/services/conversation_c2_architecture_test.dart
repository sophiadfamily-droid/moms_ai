import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('request contains no raw multi-domain source model', () {
    final source =
        File('lib/models/chat_backend_request.dart').readAsStringSync();
    for (final forbidden in [
      'UserProfile',
      'LifeContextSnapshot',
      'LifeContextGraph',
      'MemoryContext',
      'PriorityScore',
      'PriorityExplanation',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(source, contains('ConversationContextEnvelope'));
    expect(source, contains('maximumRequestUtf8Bytes'));
  });

  test('production provider uses the single canonical LC projection path', () {
    final source = File('lib/services/conversation_context_service.dart')
        .readAsStringSync();
    expect(source, contains('LifeContextProductionFactory.create'));
    expect(source, contains('LifeContextProjectionEngine'));
    expect(source, contains('ConversationContextAssembler.assemble'));
    for (final forbidden in [
      'MemoryService.getMemories',
      'EventService.getEvents',
      'ProfileContextBuilder',
      'MemoryProjectionBackendSerializer',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test('there is one canonical conversation context assembler', () {
    final definitions = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where(
          (file) => file
              .readAsStringSync()
              .contains('final class ConversationContextAssembler'),
        );
    expect(definitions, hasLength(1));
  });

  test('ChatScreen defines neither transport budgets nor redaction', () {
    final source = File('lib/screens/chat_screen.dart').readAsStringSync();
    for (final forbidden in [
      'ConversationTransportContract',
      'redactionVersion',
      'maximumRequestUtf8Bytes',
      'LifeContextProjection',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test('Functions validates and redacts before model orchestration', () {
    final transport =
        File('functions/services/chatTransportAdapters.js').readAsStringSync();
    final handler =
        File('functions/services/chatRequestHandler.js').readAsStringSync();
    final validator = File(
      'functions/services/conversationContextContract.js',
    ).readAsStringSync();
    expect(transport, contains('validateConversationRequest'));
    expect(handler, contains('validateConversationRequest'));
    expect(validator, contains('REQUEST_KEYS'));
    expect(validator, contains('FORBIDDEN_KEYS'));
    expect(validator, contains('MAX_REQUEST_BYTES'));
    expect(validator, isNot(contains('console.log')));
  });
}
