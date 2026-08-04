import '../../core/identity/entity_id_generator.dart';
import '../../core/identity/uuid_v7_entity_id_generator.dart';
import '../../models/conversation_models.dart';
import '../../models/life_context/life_context_projection.dart';
import '../../models/reasoning/reasoning_input.dart';

/// The V1-RE.1 construction boundary.
///
/// This engine is pure: it does not call a model, persist, confirm, schedule,
/// resolve conflicts or execute a domain action.
final class ReasoningInputEngine {
  ReasoningInputEngine({
    EntityIdGenerator idGenerator = const UuidV7EntityIdGenerator(),
    DateTime Function()? clock,
  })  : _idGenerator = idGenerator,
        _clock = clock ?? DateTime.now;

  final EntityIdGenerator _idGenerator;
  final DateTime Function() _clock;

  ReasoningInput build({
    required String accountScopeId,
    required ReasoningPurpose purpose,
    required ConversationState conversationState,
    required int sessionGeneration,
    required LifeContextProjection lifeContext,
  }) {
    final warnings = <String>{...lifeContext.warningCodes};
    if (lifeContext.state == LifeContextProjectionState.partial) {
      warnings.add('life_context_partial');
    }
    final state = warnings.isEmpty
        ? ReasoningInputState.complete
        : ReasoningInputState.partial;
    return ReasoningInput(
      inputId: _idGenerator.generate(),
      accountScopeId: accountScopeId,
      purpose: purpose,
      generatedAt: _clock().toUtc(),
      state: state,
      conversation: ReasoningConversationState.fromConversationState(
        conversationState,
        sessionGeneration: sessionGeneration,
      ),
      lifeContext: lifeContext,
      warningCodes: warnings.toList(),
    );
  }
}
