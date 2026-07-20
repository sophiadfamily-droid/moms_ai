class ChatBackendRequest {
  final String message;
  final Map<String, dynamic> profile;
  final Map<String, dynamic> profileContext;
  final List<Map<String, dynamic>> memories;
  final List<Map<String, dynamic>> memoryReasoning;
  final List<Map<String, dynamic>> events;

  const ChatBackendRequest({
    required this.message,
    required this.profile,
    required this.profileContext,
    required this.memories,
    required this.memoryReasoning,
    required this.events,
  });

  Map<String, dynamic> toJson() {
    return {
      'message': message,
      'profile': profile,
      'profileContext': profileContext,
      'memories': memories,
      'memoryReasoning': memoryReasoning,
      'events': events,
    };
  }
}
