import 'memory_engine_service.dart';

class MemoryPipelineService {
  static bool shouldProcessMemory(String text) {
    return MemoryEngineService.shouldSaveMemory(text);
  }

  static Map<String, dynamic> buildMemory(String text) {
    return MemoryEngineService.buildMemory(text);
  }
}
