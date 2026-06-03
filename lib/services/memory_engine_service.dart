class MemoryEngineService {
  static bool looksLikePersistentMemory(String text) {
    return importanceScore(text) >= 2;
  }

  static bool shouldSaveMemory(String text) {
    return importanceScore(text) >= 2;
  }

  static int importanceScore(String text) {
    final lower = text.trim().toLowerCase();

    if (lower.isEmpty) return 0;

    if (_hasExplicitMemoryTrigger(lower)) return 3;
    if (_hasRoutineTrigger(lower) && _hasPersonalAnchor(lower)) return 3;
    if (_hasFamilyAnchor(lower) && _hasStableFact(lower)) return 3;
    if (_hasWorkAnchor(lower) && _hasStableFact(lower)) return 2;
    if (_hasPreferenceTrigger(lower)) return 2;

    return 0;
  }

  static String categorizeMemory(String text) {
    final lower = text.trim().toLowerCase();

    if (_containsAny(lower, [
      "famille",
      "enfant",
      "mari",
      "femme",
      "conjoint",
      "conjointe",
      "fils",
      "fille",
      "parent",
      "parents",
      "école",
      "ecole",
      "crèche",
      "creche",
      "nounou",
    ])) {
      return "family";
    }

    if (_containsAny(lower, [
      "travail",
      "business",
      "projet",
      "client",
      "cliente",
      "rdv pro",
      "entreprise",
      "formation",
      "réunion",
      "reunion",
    ])) {
      return "work";
    }

    if (_containsAny(lower, [
      "santé",
      "sante",
      "médecin",
      "medecin",
      "kiné",
      "kine",
      "dentiste",
      "sport",
      "entraînement",
      "entrainement",
      "activité physique",
      "activite physique",
    ])) {
      return "health";
    }

    if (_containsAny(lower, [
      "maison",
      "ménage",
      "menage",
      "linge",
      "courses",
      "repas",
      "rangement",
      "administratif",
    ])) {
      return "home";
    }

    if (_hasPreferenceTrigger(lower)) {
      return "preferences";
    }

    if (_containsAny(lower, [
      "voyage",
      "vacances",
      "hôtel",
      "hotel",
      "vol",
      "train",
      "déplacement",
      "deplacement",
    ])) {
      return "travel";
    }

    return "personal";
  }

  static Map<String, dynamic> buildMemory(String text) {
    final cleanText = text.trim();

    return {
      "text": cleanText,
      "category": categorizeMemory(cleanText),
      "importance": importanceScore(cleanText),
    };
  }

  static bool _hasExplicitMemoryTrigger(String lower) {
    return _containsAny(lower, [
      "souviens-toi",
      "rappelle-toi",
      "mémorise",
      "memorise",
      "garde en mémoire",
      "garde en memoire",
      "à partir de maintenant",
      "a partir de maintenant",
      "dorénavant",
      "dorenavant",
    ]);
  }

  static bool _hasRoutineTrigger(String lower) {
    return _containsAny(lower, [
      "tous les jours",
      "toutes les semaines",
      "chaque semaine",
      "chaque mois",
      "tous les lundis",
      "tous les mardis",
      "tous les mercredis",
      "tous les jeudis",
      "tous les vendredis",
      "tous les samedis",
      "tous les dimanches",
      "habituellement",
      "régulièrement",
      "regulierement",
    ]);
  }

  static bool _hasPersonalAnchor(String lower) {
    return _containsAny(lower, [
      "je ",
      "j'",
      "j’",
      "mon ",
      "ma ",
      "mes ",
      "nous ",
      "notre ",
      "nos ",
      "mon enfant",
      "ma fille",
      "mon fils",
      "mon mari",
      "ma femme",
    ]);
  }

  static bool _hasFamilyAnchor(String lower) {
    return _containsAny(lower, [
      "mon enfant",
      "mes enfants",
      "ma fille",
      "mon fils",
      "mon mari",
      "ma femme",
      "conjoint",
      "conjointe",
      "famille",
      "école",
      "ecole",
      "crèche",
      "creche",
      "nounou",
    ]);
  }

  static bool _hasWorkAnchor(String lower) {
    return _containsAny(lower, [
      "travail",
      "business",
      "projet",
      "client",
      "cliente",
      "entreprise",
      "réunion",
      "reunion",
      "formation",
      "rdv pro",
    ]);
  }

  static bool _hasStableFact(String lower) {
    return _containsAny(lower, [
      "a ",
      "est ",
      "fait ",
      "travaille",
      "commence",
      "termine",
      "va ",
      "doit ",
      "tous",
      "chaque",
      "habituellement",
    ]);
  }

  static bool _hasPreferenceTrigger(String lower) {
    return _containsAny(lower, [
      "j'aime",
      "j’aime",
      "je préfère",
      "je prefere",
      "je veux toujours",
      "je n'aime pas",
      "je n’aime pas",
      "je déteste",
      "je deteste",
    ]);
  }

  static bool _containsAny(String lower, List<String> keywords) {
    return keywords.any((keyword) => lower.contains(keyword));
  }
}
