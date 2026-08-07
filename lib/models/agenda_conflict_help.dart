/// Read-only handoff from an Agenda conflict to the conversation.
final class AgendaConflictHelp {
  const AgendaConflictHelp({
    required this.eventId,
    required this.eventTitle,
    required this.otherTitle,
  });

  final String eventId;
  final String eventTitle;
  final String otherTitle;

  String get assistantMessage =>
      'Je vois que « $eventTitle » et « $otherTitle » se chevauchent. '
      'Je peux t’aider à trouver une solution. Dis-moi ce que tu préfères '
      'déplacer.';
}
