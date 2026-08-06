final class AgendaConflictMoveSuggestion {
  const AgendaConflictMoveSuggestion({
    required this.eventId,
    required this.eventTitle,
    required this.dateIso,
    required this.time,
    required this.label,
  });

  final String eventId;
  final String eventTitle;
  final String dateIso;
  final String time;
  final String label;
}
