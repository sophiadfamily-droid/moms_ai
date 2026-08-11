import 'memory_engine_service.dart';

class MemorySavePayload {
  final String text;
  final String category;
  final int importance;

  const MemorySavePayload({
    required this.text,
    required this.category,
    required this.importance,
  });
}

class MemoryPipelineService {
  static bool shouldProcessMemory(String text) {
    return MemoryEngineService.shouldSaveMemory(text);
  }

  static bool hasExplicitMemoryRequest(String text) {
    return MemoryEngineService.hasExplicitMemoryRequest(text);
  }

  static Map<String, dynamic> buildMemory(String text) {
    return MemoryEngineService.buildMemory(text);
  }

  static MemorySavePayload buildSavePayload(
    Map<String, dynamic> memory, {
    required String fallbackText,
  }) {
    final text = memory["text"]?.toString().trim() ?? "";
    final category = memory["category"]?.toString().trim() ?? "";
    final parsedImportance =
        int.tryParse(memory["importance"]?.toString() ?? "0") ?? 0;

    return MemorySavePayload(
      text: text.isNotEmpty ? text : fallbackText.trim(),
      category: category.isNotEmpty ? category : "personal",
      importance: parsedImportance.clamp(0, 3),
    );
  }
}
