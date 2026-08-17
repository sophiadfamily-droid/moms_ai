import 'dart:collection';

import 'proactive_detection.dart';

enum MentalLoadAnticipationReason {
  explicitPreparationBeforeEvent,
}

enum MentalLoadAnticipationPriority {
  important,
  urgent,
}

/// Read-only anticipation produced from facts that the user has explicitly
/// connected. It is not a Task, a notification or an authorization to act.
final class MentalLoadAnticipation {
  MentalLoadAnticipation({
    required this.id,
    required this.accountScopeId,
    required this.reason,
    required this.priority,
    required this.preparationSourceId,
    required this.eventSourceId,
    required this.preparationDeadline,
    required this.eventStart,
    required List<DetectionEvidence> evidence,
  }) : evidence = UnmodifiableListView(evidence) {
    validate();
  }

  final String id;
  final String accountScopeId;
  final MentalLoadAnticipationReason reason;
  final MentalLoadAnticipationPriority priority;
  final String preparationSourceId;
  final String eventSourceId;
  final DateTime preparationDeadline;
  final DateTime eventStart;
  final List<DetectionEvidence> evidence;

  void validate() {
    if (id.trim().isEmpty ||
        accountScopeId.trim().isEmpty ||
        preparationSourceId.trim().isEmpty ||
        eventSourceId.trim().isEmpty ||
        evidence.isEmpty ||
        preparationDeadline.isAfter(eventStart) ||
        evidence.any(
          (item) =>
              !item.confirmed ||
              item.certainty == DetectionEvidenceLevel.insufficient,
        )) {
      throw const FormatException('mental_load_anticipation_invalid');
    }
  }
}
