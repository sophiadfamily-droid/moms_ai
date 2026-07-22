enum EventParticipantEntityType { person }

enum EventParticipantEvidence { explicitUserInput }

final class EventParticipant {
  static const int maxLabelLength = 120;

  final String label;
  final EventParticipantEntityType entityType;
  final EventParticipantEvidence evidence;

  EventParticipant({
    required String label,
    required this.entityType,
    required this.evidence,
  }) : label = label.trim().replaceAll(RegExp(r'\s+'), ' ') {
    if (this.label.isEmpty || this.label.length > maxLabelLength) {
      throw const FormatException('invalid_event_participant_label');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventParticipant &&
          label == other.label &&
          entityType == other.entityType &&
          evidence == other.evidence;

  @override
  int get hashCode => Object.hash(label, entityType, evidence);

  @override
  String toString() => 'EventParticipant(entityType: person)';
}
