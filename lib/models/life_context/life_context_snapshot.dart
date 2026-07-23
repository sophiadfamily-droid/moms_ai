import 'identity_context.dart';
import 'intent_context.dart';
import 'memory_context.dart';
import 'notes_context.dart';
import 'schedule_context.dart';
import 'life_context_domains.dart';

final class LifeContextSnapshot {
  static const int currentSchemaVersion = 5;

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
  final String? accountScopeId;
  final String? snapshotId;
  final LifeContextGlobalState? globalState;
  final HumanContextSection? human;
  final IdentityDomainSection? identityDomain;
  final EventDomainSection? eventDomain;
  final TaskDomainSection? taskDomain;
  final RoutineDomainSection? routineDomain;
  final MemoryDomainSection? memoryDomain;

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
    this.accountScopeId,
    this.snapshotId,
    this.globalState,
    this.human,
    this.identityDomain,
    this.eventDomain,
    this.taskDomain,
    this.routineDomain,
    MemoryDomainSection? memoryDomain,
  })  : memory = memory ?? MemoryContext.empty,
        memoryDomain = memoryDomain ??
            (accountScopeId == null
                ? null
                : MemoryDomainSection(
                    metadata: LifeContextSourceMetadata(
                      domain: LifeContextDomain.memory,
                      source: LifeContextSourceKind.memoryFirestore,
                      readAt: generatedAt,
                      availability: LifeContextAvailability.empty,
                      freshness: LifeContextFreshness.unknown,
                      isLocal: false,
                      itemCount: 0,
                      syncStatus: 'notConfigured',
                    ),
                    policyGeneralMode: 'askEveryTime',
                    policyHealthMode: 'disabled',
                    policyConfigured: false,
                  )) {
    if (schemaVersion < 1 || schemaVersion > currentSchemaVersion) {
      throw const FormatException('unsupported_life_context_version');
    }
  }

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
      accountScopeId: accountScopeId,
      snapshotId: snapshotId,
      globalState: globalState,
      human: human,
      identityDomain: identityDomain,
      eventDomain: eventDomain,
      taskDomain: taskDomain,
      routineDomain: routineDomain,
      memoryDomain: memoryDomain,
    );
  }

  void validateCanonical() {
    if (schemaVersion != currentSchemaVersion ||
        accountScopeId == null ||
        accountScopeId!.trim().isEmpty ||
        snapshotId == null ||
        snapshotId!.trim().isEmpty ||
        globalState == null ||
        human == null ||
        identityDomain == null ||
        eventDomain == null ||
        taskDomain == null ||
        routineDomain == null ||
        memoryDomain == null) {
      throw const FormatException('invalid_canonical_life_context');
    }
  }

  Map<String, dynamic> toJson() {
    if (accountScopeId != null) {
      return {
        'schemaVersion': schemaVersion,
        'generatedAt': generatedAt.toUtc().toIso8601String(),
        'accountScopeId': accountScopeId,
        'snapshotId': snapshotId,
        'globalState': globalState?.name,
        'human': human?.toJson(),
        'identityDomain': identityDomain?.toJson(),
        'eventDomain': eventDomain?.toJson(),
        'taskDomain': taskDomain?.toJson(),
        'routineDomain': routineDomain?.toJson(),
        'memoryDomain': memoryDomain?.toJson(),
      };
    }
    return {
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
      if (accountScopeId != null) 'accountScopeId': accountScopeId,
      if (snapshotId != null) 'snapshotId': snapshotId,
      if (globalState != null) 'globalState': globalState!.name,
      if (human != null) 'human': human!.toJson(),
      if (identityDomain != null) 'identityDomain': identityDomain!.toJson(),
      if (eventDomain != null) 'eventDomain': eventDomain!.toJson(),
      if (taskDomain != null) 'taskDomain': taskDomain!.toJson(),
      if (routineDomain != null) 'routineDomain': routineDomain!.toJson(),
      if (memoryDomain != null) 'memoryDomain': memoryDomain!.toJson(),
    };
  }
}
