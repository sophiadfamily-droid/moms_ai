class ChatBackendResponse {
  final String reply;
  final List<dynamic> actions;
  final List<dynamic> memories;

  const ChatBackendResponse({
    required this.reply,
    required this.actions,
    required this.memories,
  });

  factory ChatBackendResponse.fromJson(Map<String, dynamic> json) {
    return ChatBackendResponse(
      reply: json['reply']?.toString() ?? 'C’est noté 💕',
      actions: json['actions'] is List
          ? List<dynamic>.from(json['actions'] as List)
          : const [],
      memories: json['memories'] is List
          ? List<dynamic>.from(json['memories'] as List)
          : const [],
    );
  }
}
