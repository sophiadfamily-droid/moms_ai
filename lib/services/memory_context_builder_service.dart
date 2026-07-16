class MemoryContextBuilderService {
  static List<Map<String, dynamic>> buildRelevantMemoryPayload({
    required List<Map<String, dynamic>> memories,
    int limit = 12,
  }) {
    final cleanMemories = memories.map(_normalizeMemory).where((memory) {
      final text = memory["text"]?.toString().trim() ?? "";
      return text.isNotEmpty;
    }).toList();

    cleanMemories.sort((a, b) {
      final importanceA = int.tryParse(a["importance"]?.toString() ?? "0") ?? 0;
      final importanceB = int.tryParse(b["importance"]?.toString() ?? "0") ?? 0;

      return importanceB.compareTo(importanceA);
    });

    return cleanMemories.take(limit).toList();
  }

  static String buildReadableContext(List<Map<String, dynamic>> memories) {
    if (memories.isEmpty) return "";

    final grouped = <String, List<String>>{};

    for (final memory in memories) {
      final category = memory["category"]?.toString() ?? "personal";
      final text = memory["text"]?.toString().trim() ?? "";

      if (text.isEmpty) continue;

      grouped.putIfAbsent(category, () => []);
      grouped[category]!.add(text);
    }

    final lines = <String>[];

    grouped.forEach((category, items) {
      lines.add("$category:");
      for (final item in items) {
        lines.add("- $item");
      }
      lines.add("");
    });

    return lines.join("\n").trim();
  }

  static Map<String, dynamic> _normalizeMemory(Map<String, dynamic> memory) {
    final createdAtIso = _normalizeDateTime(memory["createdAt"]);

    return {
      "text": memory["text"]?.toString().trim() ?? "",
      "category": memory["category"]?.toString().trim() ?? "personal",
      "importance": int.tryParse(
            memory["importance"]?.toString() ?? "0",
          ) ??
          0,
      if (createdAtIso.isNotEmpty) "createdAtIso": createdAtIso,
    };
  }

  static String _normalizeDateTime(dynamic value) {
    if (value == null) {
      return "";
    }

    if (value is DateTime) {
      return value.toIso8601String();
    }

    try {
      final dynamic converted = value.toDate();

      if (converted is DateTime) {
        return converted.toIso8601String();
      }
    } catch (_) {
      // Valeur non issue d'un Timestamp Firestore.
    }

    final parsed = DateTime.tryParse(value.toString().trim());
    return parsed?.toIso8601String() ?? "";
  }
}
