import '../models/chat_backend_request.dart';
import '../models/event_model.dart';
import '../models/memory_lifecycle.dart';
import '../models/user_profile.dart';
import 'conversation_context_privacy_filter.dart';
import 'app_diagnostics.dart';
import 'event_service.dart';
import 'memory_pipeline_service.dart';
import 'memory_reasoning_service.dart';
import 'memory_service.dart';
import 'life_context/life_context_engine.dart';
import 'life_context/life_context_memory_payload_builder.dart';
import 'life_context/life_context_memory_serializer.dart';
import 'memory_lifecycle_engine.dart';
import 'memory_lifecycle_repository.dart';
import 'profile_context_builder_service.dart';
import 'memory_proposal_factory.dart';

typedef ConversationMemoryLoader = Future<List<Map<String, dynamic>>>
    Function();
typedef ConversationEventLoader = Future<List<EventModel>> Function();

abstract class ConversationContextProvider {
  Future<ChatBackendRequest> buildRequest({
    required String message,
    required UserProfile profile,
  });

  Future<void> saveResponseMemory(dynamic memory);
}

abstract interface class MemoryConversationContextProvider {
  MemoryLifecycleRepository get memoryLifecycleRepository;

  Future<MemoryConfirmationRequest?> proposeUserMemory(String message);

  Future<MemoryConfirmationRequest?> proposeResponseMemory(dynamic memory);
}

class DefaultConversationContextProvider
    implements ConversationContextProvider, MemoryConversationContextProvider {
  final LifeContextEngine? _lifeContextEngine;
  final LifeContextMemoryPayloadBuilder _memoryPayloadBuilder;
  final ConversationContextPrivacyFilter _privacyFilter;
  final ConversationMemoryLoader? _loadMemories;
  final ConversationEventLoader? _loadEvents;
  final MemoryLifecycleEngine _memoryLifecycleEngine;
  final MemoryProposalFactory _memoryProposalFactory;
  final MemoryLifecycleRepository? _memoryLifecycleRepository;

  const DefaultConversationContextProvider({
    LifeContextEngine? lifeContextEngine,
    LifeContextMemoryPayloadBuilder memoryPayloadBuilder =
        const LifeContextMemoryPayloadBuilder(),
    ConversationContextPrivacyFilter privacyFilter =
        const ConversationContextPrivacyFilter(),
    ConversationMemoryLoader? loadMemories,
    ConversationEventLoader? loadEvents,
    MemoryLifecycleEngine memoryLifecycleEngine = const MemoryLifecycleEngine(),
    MemoryProposalFactory memoryProposalFactory = const MemoryProposalFactory(),
    MemoryLifecycleRepository? memoryLifecycleRepository,
  })  : _lifeContextEngine = lifeContextEngine,
        _memoryPayloadBuilder = memoryPayloadBuilder,
        _privacyFilter = privacyFilter,
        _loadMemories = loadMemories,
        _loadEvents = loadEvents,
        _memoryLifecycleEngine = memoryLifecycleEngine,
        _memoryProposalFactory = memoryProposalFactory,
        _memoryLifecycleRepository = memoryLifecycleRepository;

  @override
  Future<ChatBackendRequest> buildRequest({
    required String message,
    required UserProfile profile,
  }) async {
    final rawMemories = await (_loadMemories ?? MemoryService.getMemories)();
    final snapshot = (_lifeContextEngine ?? LifeContextEngine()).buildSnapshot(
      profile: profile,
      generatedAt: DateTime.now(),
      memories: rawMemories,
    );
    final selectedMemory = _memoryPayloadBuilder.select(
      context: snapshot.memory,
      message: message,
      limit: 12,
    );
    final relevantMemories = selectedMemory.memories
        .map(LifeContextMemorySerializer.toBackendMap)
        .toList(growable: false);
    final memoryReasoning =
        MemoryReasoningService.buildReasoningFromContext(selectedMemory);
    final profileContext = _privacyFilter.filterStructuredProfile(
      profileContext:
          ProfileContextBuilderService.buildStructuredContextFromSnapshot(
        snapshot,
      ),
      message: message,
    );
    final savedEvents = await (_loadEvents ?? EventService.getEvents)();
    final existingEvents = savedEvents.map((event) {
      return {
        'title': event.title,
        'date': event.date,
        'time': event.time,
        'startDateTimeIso': event.startDateTimeIso,
        'endTime': event.endTime,
        'endDateTimeIso': event.endDateTimeIso,
        'durationMinutes': event.durationMinutes,
        'category': event.category,
      };
    }).toList();

    return ChatBackendRequest(
      message: message,
      profile: _privacyFilter.filterProfile(
        profile: profile.toJson(),
        message: message,
      ),
      profileContext: profileContext,
      memories: relevantMemories,
      memoryReasoning: memoryReasoning,
      events: existingEvents,
    );
  }

  @override
  Future<void> saveResponseMemory(dynamic memory) async {
    await proposeResponseMemory(memory);
  }

  @override
  MemoryLifecycleRepository get memoryLifecycleRepository =>
      _memoryLifecycleRepository ?? FirestoreMemoryLifecycleRepository();

  @override
  Future<MemoryConfirmationRequest?> proposeUserMemory(String message) async {
    if (!MemoryPipelineService.shouldProcessMemory(message)) return null;
    final memory = MemoryPipelineService.buildMemory(message);
    final payload = MemoryPipelineService.buildSavePayload(
      memory,
      fallbackText: message,
    );
    return _proposeMemory({
      'text': payload.text,
      'category': payload.category,
      'importance': payload.importance,
    }, source: 'explicit_user_message');
  }

  @override
  Future<MemoryConfirmationRequest?> proposeResponseMemory(
      dynamic memory) async {
    if (memory is! Map) return null;

    final text = memory['text']?.toString() ?? '';
    if (text.trim().isEmpty) return null;
    if (!MemoryPipelineService.shouldProcessMemory(text)) return null;

    final builtMemory = MemoryPipelineService.buildMemory(text);
    final payload = MemoryPipelineService.buildSavePayload(
      builtMemory,
      fallbackText: text,
    );

    return _proposeMemory({
      'text': payload.text,
      'category': payload.category,
      'importance': payload.importance,
    }, source: 'assistant_memory_candidate');
  }

  Future<MemoryConfirmationRequest?> _proposeMemory(
    Map<String, dynamic> payload, {
    required String source,
  }) async {
    try {
      final repository =
          _memoryLifecycleRepository ?? FirestoreMemoryLifecycleRepository();
      final proposalId = await repository.allocateProposalId();
      if (proposalId == null || proposalId.isEmpty) return null;
      final proposedAt = DateTime.now();
      final proposal = _memoryProposalFactory.fromHistoricalPayload(
        id: proposalId,
        payload: payload,
        source: source,
        proposedAt: proposedAt,
        confirmationRequired: true,
      );
      if (proposal == null) return null;
      final existing = await repository.findCandidates(proposal);
      final decision = _memoryLifecycleEngine.evaluateProposal(
        proposal: proposal,
        existingMemories: existing,
        referenceDate: proposedAt,
      );
      if (decision.type ==
          MemoryLifecycleDecisionType.confirmExistingProposal) {
        return decision.confirmationRequest;
      }
      if (decision.type != MemoryLifecycleDecisionType.createProposal ||
          decision.mutations.isEmpty) {
        return null;
      }
      await repository.createProposal(proposal, decision.mutations.single);
      return decision.confirmationRequest;
    } catch (_) {
      AppDiagnostics.record(
        component: 'conversation_memory',
        step: 'proposal_persistence',
        code: AppErrorCode.storageFailure,
      );
      return null;
    }
  }
}
