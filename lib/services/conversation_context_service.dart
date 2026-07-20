import '../models/chat_backend_request.dart';
import '../models/user_profile.dart';
import 'event_service.dart';
import 'memory_context_builder_service.dart';
import 'memory_pipeline_service.dart';
import 'memory_reasoning_service.dart';
import 'memory_service.dart';
import 'profile_context_builder_service.dart';

abstract class ConversationContextProvider {
  Future<ChatBackendRequest> buildRequest({
    required String message,
    required UserProfile profile,
  });

  Future<void> saveResponseMemory(dynamic memory);
}

class DefaultConversationContextProvider
    implements ConversationContextProvider {
  const DefaultConversationContextProvider();

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

    final rawMemories = await MemoryService.getMemories();
    final savedMemories = rawMemories.map((memory) {
      return {
        'text': memory['text']?.toString() ?? '',
        'category': memory['category']?.toString() ?? 'personal',
        'importance':
            int.tryParse(memory['importance']?.toString() ?? '0') ?? 0,
        'createdAt': memory['createdAt'],
      };
    }).toList();

    final relevantMemories =
        MemoryContextBuilderService.buildRelevantMemoryPayload(
      memories: savedMemories,
      limit: 12,
    );
    final memoryReasoning =
        MemoryReasoningService.buildReasoning(relevantMemories);
    final profileContext =
        ProfileContextBuilderService.buildStructuredContext(profile);
    final savedEvents = await EventService.getEvents();
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
      profile: profile.toJson(),
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
