import 'dart:convert';

import 'conversation_context_envelope.dart';

final class ChatBackendRequest {
  static const int currentSchemaVersion = 2;

  const ChatBackendRequest({
    this.schemaVersion = currentSchemaVersion,
    required this.message,
    this.context,
    this.history = const [],
    this.profile = const {},
    this.profileContext = const {},
    this.memories = const [],
    this.memoryReasoning = const [],
    this.events = const [],
  });

  factory ChatBackendRequest.withUnavailableContext({
    required String message,
    DateTime? generatedAt,
    String warningCode = 'context_unavailable',
  }) =>
      ChatBackendRequest(
        message: message,
        context: ConversationContextEnvelope.unavailable(
          state: ConversationContextState.unavailable,
          generatedAt: generatedAt ?? DateTime.now().toUtc(),
          warningCode: warningCode,
        ),
      );

  final int schemaVersion;
  final String message;
  final ConversationContextEnvelope? context;
  final List<ConversationHistoryMessage> history;

  /// Source-compatibility fields for existing fakes only. Schema 2 never
  /// serializes their contents.
  final Map<String, dynamic> profile;
  final Map<String, dynamic> profileContext;
  final List<Map<String, dynamic>> memories;
  final List<Map<String, dynamic>> memoryReasoning;
  final List<Map<String, dynamic>> events;

  Map<String, dynamic> toJson() {
    final envelope = context;
    if (schemaVersion != currentSchemaVersion ||
        envelope == null ||
        message.trim().isEmpty ||
        message.length >
            ConversationTransportContract.maximumUserMessageCharacters ||
        utf8.encode(message).length >
            ConversationTransportContract.maximumMessageUtf8Bytes ||
        history.length > ConversationTransportContract.maximumHistoryMessages ||
        _historyBytes(history) >
            ConversationTransportContract.maximumHistoryUtf8Bytes) {
      throw const FormatException('invalid_chat_backend_request');
    }
    final result = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'message': message,
      'conversationContext': envelope.toJson(),
      'conversationHistory':
          history.map((entry) => entry.toJson()).toList(growable: false),
      'profile': const <String, dynamic>{},
      'profileContext': const <String, dynamic>{},
      'memories': const <Map<String, dynamic>>[],
      'memoryReasoning': const <Map<String, dynamic>>[],
      'events': const <Map<String, dynamic>>[],
    };
    if (utf8.encode(jsonEncode(result)).length >
        ConversationTransportContract.maximumRequestUtf8Bytes) {
      throw const FormatException('chat_backend_request_budget_exceeded');
    }
    return result;
  }

  static int _historyBytes(List<ConversationHistoryMessage> history) => utf8
      .encode(jsonEncode(history.map((item) => item.toJson()).toList()))
      .length;
}
