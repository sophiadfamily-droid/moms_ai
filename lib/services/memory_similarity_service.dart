class MemorySimilarityService {
  static bool areSimilar({
    required String firstText,
    required String secondText,
    String? firstCategory,
    String? secondCategory,
  }) {
    final score = similarityScore(
      firstText: firstText,
      secondText: secondText,
      firstCategory: firstCategory,
      secondCategory: secondCategory,
    );

    return score >= 6;
  }

  static int similarityScore({
    required String firstText,
    required String secondText,
    String? firstCategory,
    String? secondCategory,
  }) {
    final first = _normalize(firstText);
    final second = _normalize(secondText);

    if (first.isEmpty || second.isEmpty) return 0;

    var score = 0;

    if (first == second) return 10;

    if (firstCategory != null &&
        secondCategory != null &&
        firstCategory == secondCategory) {
      score += 3;
    }

    final sharedKeywords = _sharedKeywords(first, second);
    score += sharedKeywords.length.clamp(0, 4);

    if (_shareRoutinePattern(first, second)) {
      score += 2;
    }

    if (_shareTimeReference(first, second)) {
      score += 2;
    }

    if (_shareSubjectAnchor(first, second)) {
      score += 2;
    }

    return score.clamp(0, 10);
  }

  static String _normalize(String text) {
    return text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  static Set<String> _keywords(String text) {
    final stopWords = {
      "dans",
      "avec",
      "pour",
      "que",
      "qui",
      "quoi",
      "quand",
      "comment",
      "est",
      "suis",
      "fait",
      "faire",
      "tous",
      "toutes",
      "chaque",
      "les",
      "des",
      "mon",
      "ma",
      "mes",
      "notre",
      "nos",
      "je",
      "j",
    };

    return text
        .split(RegExp(r"[^a-zA-ZÀ-ÿ0-9]+"))
        .where((word) => word.length >= 4)
        .where((word) => !stopWords.contains(word))
        .toSet();
  }

  static Set<String> _sharedKeywords(String first, String second) {
    final firstKeywords = _keywords(first);
    final secondKeywords = _keywords(second);

    return firstKeywords.intersection(secondKeywords);
  }

  static bool _shareRoutinePattern(String first, String second) {
    return _containsRoutinePattern(first) && _containsRoutinePattern(second);
  }

  static bool _containsRoutinePattern(String text) {
    return text.contains("tous les") ||
        text.contains("toutes les") ||
        text.contains("chaque") ||
        text.contains("habituellement") ||
        text.contains("régulièrement") ||
        text.contains("regulierement");
  }

  static bool _shareTimeReference(String first, String second) {
    final timeReferences = [
      "lundi",
      "mardi",
      "mercredi",
      "jeudi",
      "vendredi",
      "samedi",
      "dimanche",
      "matin",
      "midi",
      "soir",
      "semaine",
      "mois",
    ];

    return timeReferences.any(
      (reference) => first.contains(reference) && second.contains(reference),
    );
  }

  static bool _shareSubjectAnchor(String first, String second) {
    final subjectAnchors = [
      "sport",
      "entraînement",
      "entrainement",
      "fitness",
      "paddle",
      "foot",
      "football",
      "travail",
      "projet",
      "enfant",
      "fils",
      "fille",
      "école",
      "ecole",
      "santé",
      "sante",
      "maison",
      "courses",
    ];

    return subjectAnchors.any(
      (anchor) => first.contains(anchor) && second.contains(anchor),
    );
  }
}
