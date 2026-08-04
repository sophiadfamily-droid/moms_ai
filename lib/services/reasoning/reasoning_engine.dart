import '../../core/identity/entity_id_generator.dart';
import '../../core/identity/uuid_v7_entity_id_generator.dart';
import '../../models/conversation_models.dart';
import '../../models/life_context/life_context_projection.dart';
import '../../models/reasoning/reasoning_input.dart';
import '../../models/reasoning/reasoning_result.dart';
import 'reasoning_assessment_engine.dart';
import 'reasoning_input_engine.dart';
import 'reasoning_observation_engine.dart';

/// V1-RE.4 is the single pure composition boundary for RE.1 through RE.3.
final class ReasoningEngine {
  ReasoningEngine({
    EntityIdGenerator idGenerator = const UuidV7EntityIdGenerator(),
    DateTime Function()? clock,
  }) : _inputEngine = ReasoningInputEngine(
          idGenerator: idGenerator,
          clock: clock,
        );

  final ReasoningInputEngine _inputEngine;

  ReasoningResult evaluate({
    required String accountScopeId,
    required ReasoningPurpose purpose,
    required ConversationState conversationState,
    required int sessionGeneration,
    required LifeContextProjection lifeContext,
  }) {
    final input = _inputEngine.build(
      accountScopeId: accountScopeId,
      purpose: purpose,
      conversationState: conversationState,
      sessionGeneration: sessionGeneration,
      lifeContext: lifeContext,
    );
    final observations = const ReasoningObservationEngine().observe(input);
    final assessment = const ReasoningAssessmentEngine().assess(
      input: input,
      observations: observations,
    );
    return ReasoningResult(
      input: input,
      observations: observations,
      assessment: assessment,
    );
  }
}
