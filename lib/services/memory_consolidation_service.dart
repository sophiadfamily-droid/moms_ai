class MemoryConsolidationService {
  static String consolidationDecision({
    required Map<String, dynamic> newMemory,
    required List<Map<String, dynamic>> similarMemories,
  }) {
    if (similarMemories.isEmpty) {
      return "keep";
    }

    final newText = newMemory["text"]?.toString() ?? "";
    final newCategory = newMemory["category"]?.toString() ?? "";

    if (newText.trim().isEmpty) {
      return "ignore";
    }

    final hasExactSameText = similarMemories.any((memory) {
      final existingText = memory["text"]?.toString() ?? "";
      return _normalize(existingText) == _normalize(newText);
    });

    if (hasExactSameText) {
      return "ignore";
    }

    final hasSameCategory = similarMemories.any((memory) {
      final existingCategory = memory["category"]?.toString() ?? "";
      return existingCategory == newCategory;
    });

    if (hasSameCategory) {
      return "merge";
    }

    return "keep";
  }

  static Map<String, dynamic> buildConsolidatedMemory({
    required Map<String, dynamic> newMemory,
    required List<Map<String, dynamic>> similarMemories,
  }) {
    final category = newMemory["category"]?.toString() ?? "personal";

    final items = <String>[];

    for (final memory in similarMemories) {
      final text = memory["text"]?.toString().trim() ?? "";
      if (text.isNotEmpty && !items.contains(text)) {
        items.add(text);
      }
    }

    final newText = newMemory["text"]?.toString().trim() ?? "";
    if (newText.isNotEmpty && !items.contains(newText)) {
      items.add(newText);
    }

    return {
      "text": items.join(" | "),
      "category": category,
      "importance": _highestImportance(newMemory, similarMemories),
      "sourceCount": items.length,
      "consolidated": true,
    };
  }

  static int _highestImportance(
    Map<String, dynamic> newMemory,
    List<Map<String, dynamic>> similarMemories,
  ) {
    final scores = <int>[
      int.tryParse(newMemory["importance"]?.toString() ?? "0") ?? 0,
      ...similarMemories.map(
        (memory) => int.tryParse(memory["importance"]?.toString() ?? "0") ?? 0,
      ),
    ];

    scores.sort((a, b) => b.compareTo(a));
    return scores.isEmpty ? 0 : scores.first;
  }

  static String _normalize(String text) {
    return text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}
