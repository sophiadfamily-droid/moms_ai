class ZeliaResponseBuilder {
  static const _frenchWeekdays = <String>[
    'lundi',
    'mardi',
    'mercredi',
    'jeudi',
    'vendredi',
    'samedi',
    'dimanche',
  ];

  static const _frenchMonths = <String>[
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];

  static String formatDateForUser(String date) {
    final cleanDate = date.trim();
    final parts = cleanDate.split("-");

    if (parts.length == 3 &&
        parts[0].length == 4 &&
        parts[1].length == 2 &&
        parts[2].length == 2) {
      return "${parts[2]}/${parts[1]}/${parts[0]}";
    }

    return cleanDate;
  }

  static String formatLongDateForUser(String date) {
    final parsed = DateTime.tryParse(date.trim());
    if (parsed == null) return formatDateForUser(date);
    return '${_frenchWeekdays[parsed.weekday - 1]} ${parsed.day} '
        '${_frenchMonths[parsed.month - 1]} ${parsed.year}';
  }

  static String joinTitles(List<String> titles) {
    final cleanTitles = titles
        .map((title) => title.trim())
        .where((title) => title.isNotEmpty)
        .toList();

    if (cleanTitles.isEmpty) return "";
    if (cleanTitles.length == 1) return cleanTitles.first;

    if (cleanTitles.length == 2) {
      return "${cleanTitles.first} et ${cleanTitles.last}";
    }

    final firstPart = cleanTitles.sublist(0, cleanTitles.length - 1).join(", ");
    return "$firstPart et ${cleanTitles.last}";
  }

  static bool titleLooksLikeCall(String title) {
    final lower = title.toLowerCase();

    return lower.contains("appeler") ||
        lower.contains("appel") ||
        lower.contains("téléphoner") ||
        lower.contains("telephoner") ||
        lower.contains("contacter") ||
        lower.contains("rappeler");
  }

  static String cleanTaskTitleForSpeech(String title) {
    var clean = title.trim();

    clean = clean.replaceFirst(
      RegExp(r"^appeler\s+", caseSensitive: false),
      "",
    );

    clean = clean.replaceFirst(
      RegExp(r"^contacter\s+", caseSensitive: false),
      "",
    );

    clean = clean.replaceFirst(
      RegExp(r"^rappeler\s+", caseSensitive: false),
      "",
    );

    return clean.trim();
  }

  static String buildGroupedActionReply({
    required List<String> shoppingTitles,
    required List<String> taskTitles,
    required List<String> eventTitles,
    String? planningTitle,
  }) {
    final lines = <String>[];

    if (shoppingTitles.isNotEmpty) {
      final label = joinTitles(shoppingTitles);

      if (shoppingTitles.length == 1) {
        lines.add("Je l’ai ajouté aux courses 💕");
      } else {
        lines.add("J’ai mis $label dans ta liste de courses 💕");
      }
    }

    if (taskTitles.isNotEmpty) {
      if (taskTitles.length == 1) {
        final taskTitle = taskTitles.first;
        final cleanTitle = cleanTaskTitleForSpeech(taskTitle);

        if (titleLooksLikeCall(taskTitle)) {
          lines.add("Je garde l’appel à $cleanTitle dans tes tâches.");
        } else {
          lines.add("Je garde aussi ça dans tes tâches.");
        }
      } else {
        lines.add("J’ai aussi gardé les tâches dans ta liste.");
      }
    }

    if (eventTitles.isNotEmpty) {
      if (eventTitles.length == 1) {
        lines.add("Je prépare aussi le rendez-vous dans ton agenda.");
      } else {
        lines.add("Je prépare aussi les rendez-vous dans ton agenda.");
      }
    }

    if (planningTitle != null && planningTitle.trim().isNotEmpty) {
      lines.add("");

      if (titleLooksLikeCall(planningTitle)) {
        lines.add(
          "Je peux aussi te proposer un moment pour cet appel si tu veux.",
        );
      } else {
        lines.add(
          "Je peux aussi te trouver un petit créneau pour ça si tu veux.",
        );
      }
    }

    if (lines.isEmpty) {
      return "C’est enregistré 💕";
    }

    return lines.join("\n\n");
  }

  static String eventCreated({
    required String title,
    required String date,
    required String time,
    required int durationMinutes,
    required int travelGoMinutes,
    required int travelBackMinutes,
    required int marginMinutes,
    required bool isRecurring,
  }) {
    final lines = <String>[];

    if (isRecurring) {
      lines.add("C’est ajouté à ton agenda chaque semaine 💕");
    } else {
      lines.add("C’est ajouté à ton agenda 💕");
    }

    final displayDate = formatDateForUser(date);

    lines.add("« $title » est prévu le $displayDate à $time.");

    if (durationMinutes > 0) {
      lines.add("Durée du rendez-vous : $durationMinutes min.");
    }

    if (travelGoMinutes > 0) {
      lines.add("Trajet aller prévu : $travelGoMinutes min.");
    }

    if (travelBackMinutes > 0) {
      lines.add("Trajet retour prévu : $travelBackMinutes min.");
    }

    if (marginMinutes > 0) {
      lines.add("Marge de sécurité prévue : $marginMinutes min.");
    }

    return lines.join("\n\n");
  }
}
