import '../../models/life_context/life_context_projection.dart';
import '../life_context/life_context_engine.dart';
import '../life_context/life_context_projection_engine.dart';
import '../life_context/life_context_relation_engine.dart';
import '../life_context_production_factory.dart';

/// Production read boundary for the local Priority 2C consumer.
abstract final class ProactivePriorityProduction {
  static Future<LifeContextProjection> loadProjection(
    String accountScopeId,
  ) async {
    final LifeContextEngine engine =
        await LifeContextProductionFactory.create();
    final snapshot = await engine.buildCanonicalSnapshot(
      accountScopeId: accountScopeId,
    );
    final graph = const LifeContextRelationEngine().build(snapshot);
    return LifeContextProjectionEngine().build(
      snapshot: snapshot,
      graph: graph,
      contract: LifeContextConsumerContract.forPurpose(
        LifeContextConsumerPurpose.proactivePriority,
      ),
    );
  }
}
