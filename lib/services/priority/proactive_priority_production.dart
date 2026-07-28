import '../../models/life_context/life_context_projection.dart';
import '../life_context_production_factory.dart';

/// Production read boundary for the local Priority 2C consumer.
abstract final class ProactivePriorityProduction {
  static Future<LifeContextProjection> loadProjection(
    String accountScopeId,
  ) async {
    final production = await LifeContextProductionFactory.production();
    production.handleAccountScopeChanged(accountScopeId);
    return production.getCurrentProjection(
      LifeContextConsumerPurpose.proactivePriority,
    );
  }
}
