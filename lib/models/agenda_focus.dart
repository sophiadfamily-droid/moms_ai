/// Identifies the Agenda day and, when known, the two items that need attention.
final class AgendaFocus {
  const AgendaFocus({
    required this.date,
    this.eventId,
    this.routineId,
    this.eventTitle,
    this.routineTitle,
  });

  final DateTime? date;
  final String? eventId;
  final String? routineId;
  final String? eventTitle;
  final String? routineTitle;

  bool get hasExactConflict =>
      eventId?.trim().isNotEmpty == true &&
      routineId?.trim().isNotEmpty == true;
}
