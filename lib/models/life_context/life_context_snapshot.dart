import 'identity_context.dart';
import 'intent_context.dart';
import 'memory_context.dart';
import 'notes_context.dart';
import 'schedule_context.dart';

final class LifeContextSnapshot {
  static const int currentSchemaVersion = 3;

  final int schemaVersion;
  final DateTime generatedAt;
  final IdentityContext identity;
  final HouseholdContext household;
  final PlaceContext places;
  final MobilityContext mobility;
  final WorkContext work;
  final AgendaContext agenda;
  final RoutineContext routines;
  final GoalContext goals;
  final PreferenceContext preferences;
  final ConstraintContext constraints;
  final NotesContext notes;
  final MemoryContext memory;

  LifeContextSnapshot({
    this.schemaVersion = currentSchemaVersion,
    required this.generatedAt,
    required this.identity,
    required this.household,
    required this.places,
    required this.mobility,
    required this.work,
    required this.agenda,
    required this.routines,
    required this.goals,
    required this.preferences,
    required this.constraints,
    this.notes = const NotesContext(),
    MemoryContext? memory,
  }) : memory = memory ?? MemoryContext.empty;

  LifeContextSnapshot withMemory(MemoryContext memory) {
    return LifeContextSnapshot(
      schemaVersion: currentSchemaVersion,
      generatedAt: generatedAt,
      identity: identity,
      household: household,
      places: places,
      mobility: mobility,
      work: work,
      agenda: agenda,
      routines: routines,
      goals: goals,
      preferences: preferences,
      constraints: constraints,
      notes: notes,
      memory: memory,
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'generatedAt': generatedAt.toIso8601String(),
        'identity': identity.toJson(),
        'household': household.toJson(),
        'places': places.toJson(),
        'mobility': mobility.toJson(),
        'work': work.toJson(),
        'agenda': agenda.toJson(),
        'routines': routines.toJson(),
        'goals': goals.toJson(),
        'preferences': preferences.toJson(),
        'constraints': constraints.toJson(),
        'notes': notes.toJson(),
        'memory': memory.toJson(),
      };
}
