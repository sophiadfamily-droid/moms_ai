import 'routine_schedule_definition.dart';

/// A read-only routine occurrence shown in the Agenda.
///
/// This is a presentation model only. It is never persisted as an Event.
final class RoutineAgendaItem {
  const RoutineAgendaItem({
    required this.occurrenceId,
    required this.routineId,
    required this.dateIso,
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.protectedStart,
    required this.protectedEnd,
    this.kind = RoutineScheduleKind.routine,
    this.blocksPrimaryUser = true,
    this.subjectLabel,
  });

  final String occurrenceId;
  final String routineId;
  final String dateIso;
  final String title;
  final String startTime;
  final String endTime;
  final DateTime protectedStart;
  final DateTime protectedEnd;
  final RoutineScheduleKind kind;
  final bool blocksPrimaryUser;
  final String? subjectLabel;
}
