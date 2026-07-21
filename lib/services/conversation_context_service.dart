import '../models/chat_backend_request.dart';
import '../models/event_model.dart';
import '../models/user_profile.dart';
import 'conversation_context_privacy_filter.dart';
import 'event_service.dart';
import 'memory_pipeline_service.dart';
import 'memory_reasoning_service.dart';
import 'memory_service.dart';
import 'life_context/life_context_engine.dart';
import 'life_context/life_context_memory_payload_builder.dart';
import 'life_context/life_context_memory_serializer.dart';
import 'profile_context_builder_service.dart';

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

class DefaultConversationContextProvider
    implements ConversationContextProvider {
  final LifeContextEngine? _lifeContextEngine;
  final LifeContextMemoryPayloadBuilder _memoryPayloadBuilder;
  final ConversationContextPrivacyFilter _privacyFilter;
  final ConversationMemoryLoader? _loadMemories;
  final ConversationEventLoader? _loadEvents;

  const DefaultConversationContextProvider({
    LifeContextEngine? lifeContextEngine,
    LifeContextMemoryPayloadBuilder memoryPayloadBuilder =
        const LifeContextMemoryPayloadBuilder(),
    ConversationContextPrivacyFilter privacyFilter =
        const ConversationContextPrivacyFilter(),
    ConversationMemoryLoader? loadMemories,
    ConversationEventLoader? loadEvents,
  })  : _lifeContextEngine = lifeContextEngine,
        _memoryPayloadBuilder = memoryPayloadBuilder,
        _privacyFilter = privacyFilter,
        _loadMemories = loadMemories,
        _loadEvents = loadEvents;

  @override
  Future<ChatBackendRequest> buildRequest({
    required String message,
    required UserProfile profile,
  }) async {
    if (MemoryPipelineService.shouldProcessMemory(message)) {
      final memory = MemoryPipelineService.buildMemory(message);
      final payload = MemoryPipelineService.buildSavePayload(
        memory,
        fallbackText: message,
      );

      await MemoryService.saveMemory(
        text: payload.text,
        category: payload.category,
        importance: payload.importance,
      );
    }

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
    if (memory is! Map) return;

    final text = memory['text']?.toString() ?? '';
    if (text.trim().isEmpty) return;
    if (!MemoryPipelineService.shouldProcessMemory(text)) return;

    final builtMemory = MemoryPipelineService.buildMemory(text);
    final payload = MemoryPipelineService.buildSavePayload(
      builtMemory,
      fallbackText: text,
    );

    await MemoryService.saveMemory(
      text: payload.text,
      category: payload.category,
      importance: payload.importance,
    );
  }
}
