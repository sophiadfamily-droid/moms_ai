import 'auth_service.dart';
import 'event_service.dart';
import 'human/human_model_service.dart';
import '../models/human/human_model_persistence.dart';
import 'life_context/life_context_domain_adapters.dart';
import 'life_context/life_context_engine.dart';
import 'task_service.dart';

abstract final class LifeContextProductionFactory {
  static Future<LifeContextEngine> create() async {
    final humanService = await HumanModelService.createLocal();
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
        TaskLifeContextAdapter(load: TaskService.getTasksForLifeContext),
        RoutineLifeContextAdapter(loadHuman: loadHuman),
      ],
    );
  }
}
