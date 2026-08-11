class MemoryEngineService {
  static bool looksLikePersistentMemory(String text) {
    return importanceScore(text) >= 2;
  }

  static bool shouldSaveMemory(String text) {
    final lower = text.trim().toLowerCase();

    if (_isQuestion(lower)) return false;

    return importanceScore(text) >= 2;
  }

  static bool hasExplicitMemoryRequest(String text) {
    return _hasExplicitMemoryTrigger(text.trim().toLowerCase());
  }

  static int importanceScore(String text) {
    final lower = text.trim().toLowerCase();

    if (lower.isEmpty) return 0;

    if (_hasExplicitMemoryTrigger(lower)) return 3;
    if (_hasRoutineTrigger(lower) && _hasPersonalAnchor(lower)) return 3;
    if (_hasConstraintTrigger(lower) && _hasPersonalAnchor(lower)) return 3;
    if (_hasFamilyAnchor(lower) && _hasStableFact(lower)) return 3;
    if (_hasWorkAnchor(lower) && _hasStableFact(lower)) return 2;
    if (_hasPreferenceTrigger(lower)) return 2;

    return 0;
  }

  static String categorizeMemory(String text) {
    final lower = text.trim().toLowerCase();

    // Meaning takes precedence over topic: a shopping preference is still a
    // preference, and a family birthday is still an important date.
    if (_hasConstraintTrigger(lower)) {
      return "constraint";
    }

    if (_hasRoutineTrigger(lower)) {
      return "routine";
    }

    if (_hasPreferenceTrigger(lower)) {
      return "preference";
    }

    if (_containsAny(lower, [
      "anniversaire",
      "date importante",
      "rappel important",
      "échéance",
      "echeance",
      "deadline",
    ])) {
      return "important_date";
    }

    if (_containsAny(lower, [
      "bébé",
      "bebe",
      "enfant",
      "enfants",
      "fils",
      "fille",
      "école",
      "ecole",
      "crèche",
      "creche",
      "nounou",
      "devoirs",
      "cantine",
      "garderie",
    ])) {
      return "children";
    }

    if (_containsAny(lower, [
      "mari",
      "femme",
      "conjoint",
      "conjointe",
      "époux",
      "epoux",
      "épouse",
      "epouse",
      "partenaire",
    ])) {
      return "partner";
    }

    if (_containsAny(lower, [
      "famille",
      "parent",
      "parents",
      "frère",
      "frere",
      "soeur",
      "sœur",
      "grand-mère",
      "grand-mere",
      "grand-père",
      "grand-pere",
      "mère",
      "mere",
      "père",
      "pere",
    ])) {
      return "family";
    }

    if (_containsAny(lower, [
      "travail",
      "poste",
      "emploi",
      "collègue",
      "collegue",
      "manager",
      "bureau",
      "rdv pro",
      "réunion",
      "reunion",
      "formation",
    ])) {
      return "work";
    }

    if (_containsAny(lower, [
      "business",
      "entreprise",
      "société",
      "societe",
      "projet",
      "client",
      "cliente",
      "devis",
      "facture",
      "marque",
      "startup",
    ])) {
      return "business";
    }

    if (_containsAny(lower, [
      "santé",
      "sante",
      "médecin",
      "medecin",
      "dentiste",
      "kiné",
      "kine",
      "pharmacie",
      "traitement",
      "médicament",
      "medicament",
      "allergie",
    ])) {
      return "health";
    }

    if (_containsAny(lower, [
      "sport",
      "entraînement",
      "entrainement",
      "fitness",
      "musculation",
      "foot",
      "football",
      "paddle",
      "pilates",
      "activité physique",
      "activite physique",
    ])) {
      return "sport";
    }

    if (_containsAny(lower, [
      "cours",
      "formation",
      "apprendre",
      "étude",
      "etude",
      "examen",
      "école",
      "ecole",
      "université",
      "universite",
    ])) {
      return "education";
    }

    if (_containsAny(lower, [
      "courses",
      "acheter",
      "racheter",
      "liste de courses",
      "supermarché",
      "supermarche",
      "alimentaire",
    ])) {
      return "shopping";
    }

    if (_containsAny(lower, [
      "voyage",
      "vacances",
      "hôtel",
      "hotel",
      "vol",
      "train",
      "aéroport",
      "aeroport",
      "déplacement",
      "deplacement",
      "séjour",
      "sejour",
    ])) {
      return "travel";
    }

    if (_containsAny(lower, [
      "banque",
      "argent",
      "budget",
      "loyer",
      "facture",
      "crédit",
      "credit",
      "impôt",
      "impot",
      "salaire",
      "paiement",
      "dette",
    ])) {
      return "finance";
    }

    if (_containsAny(lower, [
      "maison",
      "appartement",
      "logement",
      "déménagement",
      "demenagement",
      "ménage",
      "menage",
      "linge",
      "rangement",
      "travaux",
    ])) {
      return "housing";
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

  static bool _isQuestion(String lower) {
    return lower.endsWith("?") ||
        lower.startsWith("quand ") ||
        lower.startsWith("pourquoi ") ||
        lower.startsWith("comment ") ||
        lower.startsWith("où ") ||
        lower.startsWith("ou ") ||
        lower.startsWith("qui ") ||
        lower.startsWith("quoi ") ||
        lower.startsWith("est-ce que ") ||
        lower.startsWith("est ce que ") ||
        lower.startsWith("est-ce qu") ||
        lower.startsWith("est ce qu") ||
        lower.startsWith("peux-tu ") ||
        lower.startsWith("peux tu ") ||
        lower.startsWith("tu peux ") ||
        lower.startsWith("est-ce") ||
        lower.contains("?");
  }

  static bool _hasExplicitMemoryTrigger(String lower) {
    return _containsAny(lower, [
      "souviens-toi",
      "souviens toi",
      "rappelle-toi",
      "rappelle toi",
      "retiens que",
      "retiens bien",
      "retiens ceci",
      "retiens cette information",
      "mémorise",
      "memorise",
      "mémorises",
      "memorises",
      "garde en mémoire",
      "garde en memoire",
      "garde ça en mémoire",
      "garde ca en memoire",
      "note bien que",
      "n’oublie pas que",
      "n'oublie pas que",
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

  static bool _hasConstraintTrigger(String lower) {
    return _containsAny(lower, [
      "je ne peux jamais",
      "je ne suis jamais disponible",
      "je ne peux pas tous les",
      "je ne peux pas le ",
      "je suis indisponible tous les",
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
      "ma mère",
      "ma mere",
      "mon père",
      "mon pere",
      "ma sœur",
      "ma soeur",
      "mon frère",
      "mon frere",
      "ma grand-mère",
      "ma grand-mere",
      "mon grand-père",
      "mon grand-pere",
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
