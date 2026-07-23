import 'conversation_epistemic_models.dart';

class ChatBackendResponse {
  final String reply;
  final List<dynamic> actions;
  final List<dynamic> memories;
  final ConversationEpistemicContract? epistemic;

  const ChatBackendResponse({
    required this.reply,
    required this.actions,
    required this.memories,
    this.epistemic,
  });

  factory ChatBackendResponse.fromJson(Map<String, dynamic> json) {
    if (!_hasExactKeys(
          json,
          const {'reply', 'actions', 'memories', 'epistemic'},
        ) ||
        json['reply'] is! String ||
        (json['reply'] as String).trim().isEmpty ||
        json['actions'] is! List ||
        json['memories'] is! List ||
        json['epistemic'] is! Map) {
      throw const FormatException('invalid_chat_backend_response');
    }
    return ChatBackendResponse(
      reply: (json['reply'] as String).trim(),
      actions: List<dynamic>.from(json['actions'] as List),
      memories: List<dynamic>.from(json['memories'] as List),
      epistemic: ConversationEpistemicContract.fromJson(
        Map<String, dynamic>.from(json['epistemic'] as Map),
      ),
    );
  }

  static bool _hasExactKeys(
    Map<String, dynamic> value,
    Set<String> expected,
  ) =>
      value.length == expected.length && expected.containsAll(value.keys);
}
