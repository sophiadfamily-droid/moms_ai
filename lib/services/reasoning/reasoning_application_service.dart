import '../../models/conversation_models.dart';
import '../../models/life_context/life_context_projection.dart';
import '../../models/reasoning/reasoning_input.dart';
import '../../models/reasoning/reasoning_result.dart';
import '../life_context_production_factory.dart';
import 'reasoning_engine.dart';

typedef ReasoningProjectionLoader = Future<LifeContextProjection> Function(
  String accountScopeId,
);

/// RE.5 connects the pure RE.1-4 pipeline to the bounded production context.
/// The result remains read-only and grants no mutation authority.
final class ReasoningApplicationService {
  ReasoningApplicationService({
    required ReasoningProjectionLoader loadProjection,
    ReasoningEngine? engine,
  })  : _loadProjection = loadProjection,
        _engine = engine ?? ReasoningEngine();

  factory ReasoningApplicationService.production() =>
      ReasoningApplicationService(
        loadProjection: (accountScopeId) async {
          final production = await LifeContextProductionFactory.production();
          final projection = await production.getCurrentProjection(
            LifeContextConsumerPurpose.conversation,
          );
          if (projection.accountScopeId != accountScopeId) {
            throw const ReasoningInputException(
              'reasoning_account_scope_mismatch',
            );
          }
          return projection;
        },
      );

  final ReasoningProjectionLoader _loadProjection;
  final ReasoningEngine _engine;

  Future<ReasoningResult> evaluate({
    required String accountScopeId,
    required ReasoningPurpose purpose,
    required ConversationState conversationState,
    required int sessionGeneration,
  }) async {
    if (accountScopeId.trim().isEmpty) {
      throw const ReasoningInputException('invalid_reasoning_identity');
    }
    final projection = await _loadProjection(accountScopeId);
    return _engine.evaluate(
      accountScopeId: accountScopeId,
      purpose: purpose,
      conversationState: conversationState,
      sessionGeneration: sessionGeneration,
      lifeContext: projection,
    );
  }
}
