import 'auth_service.dart';
import 'event_service.dart';
import 'human/human_model_service.dart';
import '../models/human/human_model_persistence.dart';
import 'life_context/life_context_domain_adapters.dart';
import 'life_context/life_context_engine.dart';
import 'life_context/life_context_production.dart';
import 'memory_policy_service.dart';
import 'memory_service.dart';
import 'task_service.dart';
import 'memory_sync_local_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'routine_repository.dart';
import '../models/life_context/life_context_domains.dart';

abstract final class LifeContextProductionFactory {
  static Future<LifeContextProduction>? _production;

  static Future<LifeContextProduction> production() {
    return _production ??= _createProduction();
  }

  static Future<LifeContextProduction> _createProduction() async {
    final engine = await create();
    final production = LifeContextProduction(
      loadEngine: () async => engine,
      currentAccountScopeId: () => AuthService.currentUserId,
    );
    EventService.eventsVersion.addListener(
      () => production.invalidateSection(LifeContextDomain.event),
    );
    TaskService.tasksVersion.addListener(
      () => production.invalidateSection(LifeContextDomain.task),
    );
    HumanModelService.modelVersion.addListener(
      () => production.invalidateSection(LifeContextDomain.human),
    );
    routinesVersion.addListener(
      () => production.invalidateSection(LifeContextDomain.routine),
    );
    MemoryService.memoriesVersion.addListener(
      () => production.invalidateSection(LifeContextDomain.memory),
    );
    return production;
  }

  static Future<LifeContextEngine> create() async {
    final humanService = await HumanModelService.createLocal();
    final memoryPolicyService = await MemoryPolicyService.local(
      currentAccountScopeId: () => AuthService.currentUserId,
    );
    final memorySyncLocal =
        MemorySyncLocalRepository(await SharedPreferences.getInstance());
    final routineRepository = FirestoreRoutineRepository();
    Future<HumanModelLocalState?> loadHuman(String scope) =>
        humanService.loadState(scope);

    return LifeContextEngine(
      currentAccountScopeId: () => AuthService.currentUserId,
      adapters: [
        HumanModelLifeContextAdapter(load: loadHuman),
        IdentityLifeContextAdapter(loadHuman: loadHuman),
        EventLifeContextAdapter(
          load: EventService.getEventsForLifeContext,
          loadSyncStatuses: EventService.getEventSyncStatesForLifeContext,
        ),
        TaskLifeContextAdapter(
          load: TaskService.getTasksForLifeContext,
          loadSyncMetadata: TaskService.getTaskSyncMetadataForLifeContext,
        ),
        RoutineLifeContextAdapter(
          loadHuman: loadHuman,
          loadCanonical: routineRepository.listForAccount,
        ),
        MemoryLifeContextAdapter(
          loadMemories: MemoryService.getMemoriesForLifeContext,
          loadSyncState: memorySyncLocal.load,
          loadPolicy: (scope) async {
            if (AuthService.currentUserId != scope) {
              throw StateError('memory_account_mismatch');
            }
            return memoryPolicyService.load();
          },
        ),
      ],
    );
  }
}
