class MemoryRetrievalService {
  static List<Map<String, dynamic>> selectRelevantMemories({
    required String message,
    required List<Map<String, dynamic>> memories,
    int limit = 12,
  }) {
    final lowerMessage = message.trim().toLowerCase();

    if (lowerMessage.isEmpty || memories.isEmpty) {
      return [];
    }

    final scoredMemories = memories.map((memory) {
      final text = memory["text"]?.toString() ?? "";
      final category = memory["category"]?.toString() ?? "personal";

      final score = _scoreMemory(
        message: lowerMessage,
        memoryText: text.toLowerCase(),
        category: category,
      );

      return {
        ...memory,
        "_score": score,
      };
    }).where((memory) {
      final score = int.tryParse(memory["_score"]?.toString() ?? "0") ?? 0;
      return score > 0;
    }).toList();

    scoredMemories.sort((a, b) {
      final scoreA = int.tryParse(a["_score"]?.toString() ?? "0") ?? 0;
      final scoreB = int.tryParse(b["_score"]?.toString() ?? "0") ?? 0;
      return scoreB.compareTo(scoreA);
    });

    return scoredMemories.take(limit).map((memory) {
      final cleanMemory = Map<String, dynamic>.from(memory);
      cleanMemory.remove("_score");
      return cleanMemory;
    }).toList();
  }

  static int _scoreMemory({
    required String message,
    required String memoryText,
    required String category,
  }) {
    var score = 0;

    if (_sharesKeyword(message, memoryText)) {
      score += 3;
    }

    if (_categoryMatchesMessage(message, category)) {
      score += 3;
    }

    if (memoryText.contains("tous les") ||
        memoryText.contains("chaque") ||
        memoryText.contains("habituellement")) {
      score += 2;
    }

    return score;
  }

  static bool _sharesKeyword(String message, String memoryText) {
    final words = message
        .split(RegExp(r"\\s+"))
        .where((word) => word.length >= 4)
        .toSet();

    return words.any((word) => memoryText.contains(word));
  }

  static bool _categoryMatchesMessage(String message, String category) {
    final categoryKeywords = <String, List<String>>{
      "children": ["enfant", "fils", "fille", "école", "ecole", "crèche"],
      "partner": ["mari", "femme", "conjoint", "conjointe"],
      "family": ["famille", "parents", "frère", "soeur"],
      "work": ["travail", "bureau", "réunion", "emploi"],
      "business": ["business", "projet", "client", "entreprise"],
      "health": ["santé", "médecin", "dentiste", "rdv médical"],
      "sport": ["sport", "entraînement", "foot", "fitness"],
      "education": ["cours", "formation", "examen", "apprendre"],
      "shopping": ["courses", "acheter", "supermarché"],
      "travel": ["voyage", "vacances", "vol", "train", "hôtel"],
      "finance": ["budget", "facture", "loyer", "paiement", "banque"],
      "housing": ["maison", "logement", "ménage", "travaux"],
      "routine": ["routine", "habitude", "tous les", "chaque"],
      "preferences": ["préférence", "j'aime", "je préfère"],
      "important_date": ["anniversaire", "date", "deadline", "échéance"],
    };

    final keywords = categoryKeywords[category] ?? [];
    return keywords.any((keyword) => message.contains(keyword));
  }
}
