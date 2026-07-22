final class EventMutationTarget {
  final String? title;
  final String? date;
  final String? time;
  final String? category;

  EventMutationTarget({this.title, this.date, this.time, this.category}) {
    if ([title, date, time, category].every((value) => value == null)) {
      throw const FormatException('empty_event_mutation_target');
    }
  }
}

final class EventMutationChanges {
  final String? title;
  final String? date;
  final String? time;
  final int? durationMinutes;
  final int? travelGoMinutes;
  final int? travelBackMinutes;
  final int? marginMinutes;
  final String? notes;
  final String? category;

  EventMutationChanges({
    this.title,
    this.date,
    this.time,
    this.durationMinutes,
    this.travelGoMinutes,
    this.travelBackMinutes,
    this.marginMinutes,
    this.notes,
    this.category,
  }) {
    if ([
      title,
      date,
      time,
      durationMinutes,
      travelGoMinutes,
      travelBackMinutes,
      marginMinutes,
      notes,
      category,
    ].every((value) => value == null)) {
      throw const FormatException('empty_event_mutation_changes');
    }
  }
}

final class EventMutationRequest {
  final EventMutationTarget target;
  final EventMutationChanges changes;

  const EventMutationRequest({required this.target, required this.changes});
}

final class EventMutationCandidateChoice {
  final String eventId;
  final String displayLabel;

  EventMutationCandidateChoice({
    required this.eventId,
    required String displayLabel,
  }) : displayLabel = displayLabel.trim() {
    if (eventId.trim().isEmpty || this.displayLabel.isEmpty) {
      throw const FormatException('invalid_event_mutation_choice');
    }
  }
}
