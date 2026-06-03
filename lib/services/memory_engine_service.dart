class MemoryEngineService {
  static bool looksLikePersistentMemory(String text) {
    final lower = text.trim().toLowerCase();

    if (lower.isEmpty) return false;

    return lower.contains("souviens-toi") ||
        lower.contains("rappelle-toi") ||
        lower.contains("mémorise") ||
        lower.contains("memorise") ||
        lower.contains("garde en mémoire") ||
        lower.contains("garde en memoire") ||
        lower.contains("à partir de maintenant") ||
        lower.contains("a partir de maintenant") ||
        lower.contains("dorénavant") ||
        lower.contains("dorenavant") ||
        lower.contains("habituellement") ||
        lower.contains("tous les jours") ||
        lower.contains("toutes les semaines") ||
        lower.contains("chaque semaine") ||
        lower.contains("chaque mois");
  }

  static String categorizeMemory(String text) {
    final lower = text.trim().toLowerCase();

    if (lower.contains("école") ||
        lower.contains("ecole") ||
        lower.contains("enfant") ||
        lower.contains("famille") ||
        lower.contains("mari") ||
        lower.contains("fils") ||
        lower.contains("fille")) {
      return "family";
    }

    if (lower.contains("travail") ||
        lower.contains("business") ||
        lower.contains("projet") ||
        lower.contains("client") ||
        lower.contains("rdv pro")) {
      return "work";
    }

    if (lower.contains("sport") ||
        lower.contains("santé") ||
        lower.contains("sante") ||
        lower.contains("médecin") ||
        lower.contains("medecin") ||
        lower.contains("kiné") ||
        lower.contains("kine")) {
      return "health";
    }

    if (lower.contains("maison") ||
        lower.contains("ménage") ||
        lower.contains("menage") ||
        lower.contains("linge") ||
        lower.contains("courses")) {
      return "home";
    }

    return "personal";
  }

  static Map<String, dynamic> buildMemory(String text) {
    return {
      "text": text.trim(),
      "category": categorizeMemory(text),
    };
  }
}
