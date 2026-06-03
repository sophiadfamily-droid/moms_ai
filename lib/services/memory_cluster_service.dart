import 'memory_similarity_service.dart';

class MemoryClusterService {
  static List<Map<String, dynamic>> findSimilarMemories({
    required Map<String, dynamic> newMemory,
    required List<Map<String, dynamic>> existingMemories,
    int minimumScore = 6,
  }) {
    final newText = newMemory["text"]?.toString() ?? "";
    final newCategory = newMemory["category"]?.toString();

    return existingMemories.where((memory) {
      final existingText = memory["text"]?.toString() ?? "";
      final existingCategory = memory["category"]?.toString();

      final score = MemorySimilarityService.similarityScore(
        firstText: newText,
        secondText: existingText,
        firstCategory: newCategory,
        secondCategory: existingCategory,
      );

      return score >= minimumScore;
    }).toList();
  }

  static bool hasSimilarMemory({
    required Map<String, dynamic> newMemory,
    required List<Map<String, dynamic>> existingMemories,
    int minimumScore = 6,
  }) {
    return findSimilarMemories(
      newMemory: newMemory,
      existingMemories: existingMemories,
      minimumScore: minimumScore,
    ).isNotEmpty;
  }

  static Map<String, dynamic> buildClusterPreview({
    required Map<String, dynamic> newMemory,
    required List<Map<String, dynamic>> similarMemories,
  }) {
    final category = newMemory["category"]?.toString() ?? "personal";

    return {
      "category": category,
      "newMemory": newMemory,
      "similarMemories": similarMemories,
      "count": similarMemories.length + 1,
    };
  }
}
