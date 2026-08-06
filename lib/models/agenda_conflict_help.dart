/// Read-only handoff from an Agenda conflict to the conversation.
final class AgendaConflictHelp {
  const AgendaConflictHelp({
    required this.eventId,
    required this.eventTitle,
    required this.routineTitle,
  });

  final String eventId;
  final String eventTitle;
  final String routineTitle;

  String get assistantMessage =>
      'Je vois que « $eventTitle » et « $routineTitle » se chevauchent. '
      'Je peux t’aider à trouver une solution. Dis-moi ce que tu préfères '
      'déplacer.';
}
