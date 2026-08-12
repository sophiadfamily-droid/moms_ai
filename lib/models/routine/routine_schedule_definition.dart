import '../routine_model.dart';

/// The human meaning of a recurring schedule item shown in the Agenda.
enum RoutineScheduleKind {
  routine,
  personalActivity,
  work,
  school,
  householdActivity,
}

/// A canonical routine enriched with the minimum presentation and reasoning
/// metadata needed by the Agenda.
final class RoutineScheduleDefinition {
  const RoutineScheduleDefinition({
    required this.routine,
    required this.kind,
    required this.blocksPrimaryUser,
    this.subjectLabel,
  });

  final RoutineModel routine;
  final RoutineScheduleKind kind;
  final bool blocksPrimaryUser;
  final String? subjectLabel;

  RoutineScheduleDefinition copyWith({
    RoutineModel? routine,
    RoutineScheduleKind? kind,
    bool? blocksPrimaryUser,
    String? subjectLabel,
  }) =>
      RoutineScheduleDefinition(
        routine: routine ?? this.routine,
        kind: kind ?? this.kind,
        blocksPrimaryUser: blocksPrimaryUser ?? this.blocksPrimaryUser,
        subjectLabel: subjectLabel ?? this.subjectLabel,
      );
}
