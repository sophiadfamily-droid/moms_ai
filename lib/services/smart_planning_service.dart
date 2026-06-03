import '../models/event_model.dart';
import '../models/task_model.dart';
import 'event_service.dart';
import 'task_service.dart';

class SmartPlanningProposal {
  final bool canPropose;
  final String taskTitle;
  final String taskType;
  final bool needsTravel;
  final String date;
  final String startTime;
  final String endTime;
  final int actionMinutes;
  final int travelGoMinutes;
  final int travelBackMinutes;
  final int marginMinutes;
  final int totalMinutes;
  final String explanation;
  final String confirmationMessage;

  const SmartPlanningProposal({
    required this.canPropose,
    required this.taskTitle,
    required this.taskType,
    required this.needsTravel,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.actionMinutes,
    required this.travelGoMinutes,
    required this.travelBackMinutes,
    required this.marginMinutes,
    required this.totalMinutes,
    required this.explanation,
    required this.confirmationMessage,
  });

  Map<String, dynamic> toJson() {
    return {
      "canPropose": canPropose,
      "taskTitle": taskTitle,
      "taskType": taskType,
      "needsTravel": needsTravel,
      "date": date,
      "startTime": startTime,
      "endTime": endTime,
      "actionMinutes": actionMinutes,
      "travelGoMinutes": travelGoMinutes,
      "travelBackMinutes": travelBackMinutes,
      "marginMinutes": marginMinutes,
      "totalMinutes": totalMinutes,
      "explanation": explanation,
      "confirmationMessage": confirmationMessage,
    };
  }

  static SmartPlanningProposal empty() {
    return const SmartPlanningProposal(
      canPropose: false,
      taskTitle: "",
      taskType: "",
      needsTravel: false,
      date: "",
      startTime: "",
      endTime: "",
      actionMinutes: 0,
      travelGoMinutes: 0,
      travelBackMinutes: 0,
      marginMinutes: 0,
      totalMinutes: 0,
      explanation: "",
      confirmationMessage: "",
    );
  }
}

class SmartPlanningService {
  static const int dayStartHour = 9;
  static const int dayEndHour = 17;

  static const List<String> positiveAnswers = [
    "oui",
    "ok",
    "vas y",
    "vas-y",
    "d'accord",
    "daccord",
    "ajoute",
    "reserve",
    "réserve",
    "planifie",
    "bloque",
    "c'est bon",
    "parfait",
  ];

  static const List<String> negativeAnswers = [
    "non",
    "pas maintenant",
    "laisse",
    "annule",
    "non merci",
  ];

  static bool isPositiveAnswer(String text) {
    final value = text.trim().toLowerCase();
    return positiveAnswers.any((answer) => value.contains(answer));
  }

  static bool isNegativeAnswer(String text) {
    final value = text.trim().toLowerCase();
    return negativeAnswers.any((answer) => value.contains(answer));
  }

  static int parseTravelMinutes(String text) {
    final lower = text.toLowerCase().trim();

    final hourMinuteMatch = RegExp(r"(\d+)\s*h\s*(\d+)").firstMatch(lower);
    if (hourMinuteMatch != null) {
      final hours = int.tryParse(hourMinuteMatch.group(1) ?? "0") ?? 0;
      final minutes = int.tryParse(hourMinuteMatch.group(2) ?? "0") ?? 0;
      return (hours * 60) + minutes;
    }

    final hourMatch = RegExp(r"(\d+)\s*h").firstMatch(lower);
    if (hourMatch != null) {
      final hours = int.tryParse(hourMatch.group(1) ?? "0") ?? 0;
      return hours * 60;
    }

    final minuteMatch = RegExp(r"(\d+)\s*(min|minutes)").firstMatch(lower);
    if (minuteMatch != null) {
      return int.tryParse(minuteMatch.group(1) ?? "0") ?? 0;
    }

    final onlyNumber = RegExp(r"^\s*(\d+)\s*$").firstMatch(lower);
    if (onlyNumber != null) {
      return int.tryParse(onlyNumber.group(1) ?? "0") ?? 0;
    }

    return 0;
  }

  static String formatIsoDate(DateTime date) {
    final y = date.year.toString();
    final m = date.month.toString().padLeft(2, "0");
    final d = date.day.toString().padLeft(2, "0");
    return "$y-$m-$d";
  }

  static String formatIsoTime(DateTime date) {
    final h = date.hour.toString().padLeft(2, "0");
    final m = date.minute.toString().padLeft(2, "0");
    return "$h:$m";
  }

  static DateTime startOfToday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static DateTime targetDateFromText(String text, TaskModel task) {
    final lower = "${text.toLowerCase()} ${task.dueDate.toLowerCase()}";
    final today = startOfToday();

    if (lower.contains("après-demain") || lower.contains("apres demain")) {
      return today.add(const Duration(days: 2));
    }

    if (lower.contains("demain")) {
      return today.add(const Duration(days: 1));
    }

    if (lower.contains("aujourd")) {
      return today;
    }

    final weekday = weekdayFromText(lower);
    if (weekday > 0) {
      return nextDateForWeekday(weekday);
    }

    if (task.planning == "Aujourd’hui") {
      return today;
    }

    return today.add(const Duration(days: 1));
  }

  static int weekdayFromText(String lower) {
    if (lower.contains("lundi")) return 1;
    if (lower.contains("mardi")) return 2;
    if (lower.contains("mercredi")) return 3;
    if (lower.contains("jeudi")) return 4;
    if (lower.contains("vendredi")) return 5;
    if (lower.contains("samedi")) return 6;
    if (lower.contains("dimanche")) return 7;
    return 0;
  }

  static DateTime nextDateForWeekday(int weekday) {
    final today = startOfToday();
    var daysToAdd = weekday - today.weekday;

    if (daysToAdd < 0) {
      daysToAdd += 7;
    }

    return today.add(Duration(days: daysToAdd));
  }

  static String detectTaskType(String text, TaskModel task) {
    final value =
        "${text.toLowerCase()} ${task.title.toLowerCase()} ${task.notes.toLowerCase()}";

    if (value.contains("course") ||
        value.contains("courses") ||
        value.contains("supermarché") ||
        value.contains("supermarche") ||
        value.contains("carrefour") ||
        value.contains("auchan") ||
        value.contains("leclerc") ||
        value.contains("lidl")) {
      return "courses";
    }

    if (value.contains("appeler") ||
        value.contains("appel") ||
        value.contains("téléphone") ||
        value.contains("telephone") ||
        value.contains("contacter")) {
      return "appel";
    }

    if (value.contains("dentiste")) return "dentiste";

    if (value.contains("médecin") ||
        value.contains("medecin") ||
        value.contains("docteur") ||
        value.contains("pédiatre") ||
        value.contains("pediatre") ||
        value.contains("rdv santé") ||
        value.contains("santé") ||
        value.contains("sante")) {
      return "santé";
    }

    if (value.contains("ménage") ||
        value.contains("menage") ||
        value.contains("rangement") ||
        value.contains("linge") ||
        value.contains("nettoyer")) {
      return "maison";
    }

    if (value.contains("sport") ||
        value.contains("salle") ||
        value.contains("fitness") ||
        value.contains("paddle") ||
        value.contains("yoga")) {
      return "sport";
    }

    if (value.contains("payer") ||
        value.contains("facture") ||
        value.contains("edf") ||
        value.contains("banque") ||
        value.contains("caf") ||
        value.contains("impôt") ||
        value.contains("impot") ||
        value.contains("dossier") ||
        value.contains("administratif") ||
        value.contains("papier")) {
      return "administratif";
    }

    if (value.contains("école") ||
        value.contains("ecole") ||
        value.contains("crèche") ||
        value.contains("creche") ||
        value.contains("kassim") ||
        value.contains("kasim") ||
        value.contains("enfant")) {
      return "enfant";
    }

    if (value.contains("pharmacie") ||
        value.contains("récupérer") ||
        value.contains("recuperer") ||
        value.contains("colis") ||
        value.contains("acheter") ||
        value.contains("aller chercher") ||
        value.contains("prendre")) {
      return "achat";
    }

    return "general";
  }

  static bool isOutsideTask({
    required String type,
    required String originalMessage,
    required TaskModel task,
  }) {
    final value =
        "${originalMessage.toLowerCase()} ${task.title.toLowerCase()} ${task.notes.toLowerCase()}";

    if (value.contains("à la maison") ||
        value.contains("a la maison") ||
        value.contains("chez moi") ||
        value.contains("depuis la maison") ||
        value.contains("en ligne") ||
        value.contains("visio") ||
        value.contains("mail") ||
        value.contains("email") ||
        value.contains("par téléphone") ||
        value.contains("par telephone") ||
        value.contains("appeler") ||
        value.contains("appel")) {
      return false;
    }

    if (value.contains("aller") ||
        value.contains("me rendre") ||
        value.contains("sur place")) {
      return true;
    }

    return type == "courses" ||
        type == "dentiste" ||
        type == "santé" ||
        type == "sport" ||
        type == "achat" ||
        type == "enfant";
  }

  static int actionDurationForType(String type, String text, TaskModel task) {
    final value =
        "${text.toLowerCase()} ${task.title.toLowerCase()} ${task.notes.toLowerCase()}";

    final explicit = parseExplicitDurationMinutes(value);
    if (explicit > 0) return explicit;

    switch (type) {
      case "appel":
        return 15;
      case "courses":
        if (value.contains("grosses courses") ||
            value.contains("courses semaine") ||
            value.contains("plein de courses")) {
          return 90;
        }
        return 45;
      case "dentiste":
        return 60;
      case "santé":
        return 45;
      case "administratif":
        return 30;
      case "maison":
        if (value.contains("complet") || value.contains("grand ménage")) {
          return 120;
        }
        return 45;
      case "sport":
        return 60;
      case "enfant":
        return 30;
      case "achat":
        return 30;
      default:
        return 30;
    }
  }

  static int parseExplicitDurationMinutes(String text) {
    final lower = text.toLowerCase().trim();

    final hourMinuteMatch = RegExp(r"(\d+)\s*h\s*(\d+)").firstMatch(lower);
    if (hourMinuteMatch != null) {
      final hours = int.tryParse(hourMinuteMatch.group(1) ?? "0") ?? 0;
      final minutes = int.tryParse(hourMinuteMatch.group(2) ?? "0") ?? 0;
      return (hours * 60) + minutes;
    }

    final hourMatch = RegExp(r"(\d+)\s*h").firstMatch(lower);
    if (hourMatch != null) {
      final hours = int.tryParse(hourMatch.group(1) ?? "0") ?? 0;
      return hours * 60;
    }

    final minuteMatch = RegExp(r"(\d+)\s*(min|minutes)").firstMatch(lower);
    if (minuteMatch != null) {
      return int.tryParse(minuteMatch.group(1) ?? "0") ?? 0;
    }

    return 0;
  }

  static int defaultMarginMinutes(String type) {
    if (type == "courses") return 10;
    if (type == "dentiste" || type == "santé") return 10;
    if (type == "enfant") return 10;
    return 5;
  }

  static bool isBusyBecauseFamilyRoutine(DateTime start, DateTime end) {
    final eveningStart = DateTime(start.year, start.month, start.day, 18, 30);
    final eveningEnd = DateTime(start.year, start.month, start.day, 21, 0);
    return start.isBefore(eveningEnd) && eveningStart.isBefore(end);
  }

  static bool overlapsExistingEvent({
    required DateTime start,
    required DateTime end,
    required List<EventModel> events,
  }) {
    for (final event in events) {
      final eventStart = EventService.parseStart(event);
      final eventEnd = EventService.parseEnd(event);

      if (eventStart == null || eventEnd == null) continue;

      final overlaps = start.isBefore(eventEnd) && eventStart.isBefore(end);
      if (overlaps) return true;
    }

    return false;
  }

  static bool shouldAvoidMorning(
    List<Map<String, dynamic>> memoryReasoning,
  ) {
    return memoryReasoning.any((reasoning) {
      return reasoning["type"] == "schedule_constraint" &&
          reasoning["avoidMorning"] == true;
    });
  }

  static bool prefersAfternoon(
    List<Map<String, dynamic>> memoryReasoning,
  ) {
    return memoryReasoning.any((reasoning) {
      return reasoning["type"] == "schedule_preference" &&
          reasoning["preferredPeriod"] == "afternoon";
    });
  }

  static DateTime? findBestSlot({
    required DateTime targetDate,
    required int totalMinutes,
    required List<EventModel> events,
    int? preferredStartHour,
    int? preferredEndHour,
    bool avoidMorning = false,
  }) {
    final effectiveStartHour =
        preferredStartHour ?? (avoidMorning ? 12 : dayStartHour);
    final effectiveEndHour = preferredEndHour ?? dayEndHour;

    final start = DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
      effectiveStartHour,
      0,
    );

    final endLimit = DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
      effectiveEndHour,
      0,
    );

    var cursor = start;

    while (cursor.add(Duration(minutes: totalMinutes)).isBefore(endLimit) ||
        cursor
            .add(Duration(minutes: totalMinutes))
            .isAtSameMomentAs(endLimit)) {
      final slotEnd = cursor.add(Duration(minutes: totalMinutes));

      final hasEventConflict = overlapsExistingEvent(
        start: cursor,
        end: slotEnd,
        events: events,
      );

      final hasFamilyConflict = isBusyBecauseFamilyRoutine(cursor, slotEnd);

      if (!hasEventConflict && !hasFamilyConflict) {
        return cursor;
      }

      cursor = cursor.add(const Duration(minutes: 15));
    }

    return null;
  }

  static String durationLabel(int minutes) {
    if (minutes <= 0) return "0 min";
    if (minutes < 60) return "$minutes min";

    final hours = minutes ~/ 60;
    final rest = minutes % 60;

    if (rest == 0) return "${hours}h";

    return "${hours}h${rest.toString().padLeft(2, "0")}";
  }

  static String humanDateLabel(DateTime date) {
    final today = startOfToday();
    final tomorrow = today.add(const Duration(days: 1));

    if (formatIsoDate(date) == formatIsoDate(today)) return "aujourd’hui";
    if (formatIsoDate(date) == formatIsoDate(tomorrow)) return "demain";

    const days = [
      "lundi",
      "mardi",
      "mercredi",
      "jeudi",
      "vendredi",
      "samedi",
      "dimanche",
    ];

    return days[date.weekday - 1];
  }

  static bool isOutsideTypeGroup(String type) {
    return type == "courses" ||
        type == "achat" ||
        type == "santé" ||
        type == "dentiste" ||
        type == "enfant";
  }

  static String normalizedTaskTitle(String title) {
    return title.trim().toLowerCase();
  }

  static int estimateGroupedActionMinutes(List<TaskModel> tasks) {
    var total = 0;
    final sortedTasks = sortTasksByPriority(tasks);

    for (final task in sortedTasks) {
      final type = detectTaskType(task.title, task);
      total += actionDurationForType(type, task.title, task);
    }

    if (sortedTasks.length > 1) {
      total += (sortedTasks.length - 1) * 5;
    }

    return total;
  }

  static String groupedTasksLabel(List<TaskModel> tasks) {
    if (tasks.isEmpty) return "Sortie to-do";

    final titles = tasks.map((task) => task.title.trim()).where((title) {
      return title.isNotEmpty;
    }).toList();

    if (titles.isEmpty) return "Sortie to-do";

    if (titles.length == 1) return titles.first;

    final preview = titles.take(3).join(", ");

    if (titles.length > 3) {
      return "Sortie to-do : $preview...";
    }

    return "Sortie to-do : $preview";
  }

  static String groupedTasksBulletList(List<TaskModel> tasks) {
    final sortedTasks = sortTasksByPriority(tasks);
    final titles = sortedTasks.map((task) => task.title.trim()).where((title) {
      return title.isNotEmpty;
    }).toList();

    if (titles.isEmpty) return "";

    return titles.map((title) => "• $title").join("\n");
  }

  static int priorityScore(TaskModel task) {
    final value =
        "${task.title.toLowerCase()} ${task.category.toLowerCase()} ${task.notes.toLowerCase()} ${task.priority.toLowerCase()} ${task.planning.toLowerCase()}";

    var score = 0;

    if (task.isImportant) score += 35;

    if (value.contains("urgente") ||
        value.contains("urgent") ||
        value.contains("rapidement") ||
        value.contains("aujourd") ||
        value.contains("avant ce soir") ||
        value.contains("dernier délai") ||
        value.contains("deadline") ||
        value.contains("échéance") ||
        value.contains("echeance") ||
        value.contains("retard") ||
        value.contains("impayé") ||
        value.contains("impaye")) {
      score += 45;
    }

    if (value.contains("importante") ||
        value.contains("important") ||
        value.contains("comptable") ||
        value.contains("banque") ||
        value.contains("impôt") ||
        value.contains("impot") ||
        value.contains("caf") ||
        value.contains("assurance") ||
        value.contains("edf") ||
        value.contains("facture") ||
        value.contains("passeport") ||
        value.contains("visa") ||
        value.contains("loyer")) {
      score += 30;
    }

    if (value.contains("médecin") ||
        value.contains("medecin") ||
        value.contains("dentiste") ||
        value.contains("pédiatre") ||
        value.contains("pediatre") ||
        value.contains("ordonnance") ||
        value.contains("pharmacie") ||
        value.contains("santé") ||
        value.contains("sante")) {
      score += 35;
    }

    if (value.contains("école") ||
        value.contains("ecole") ||
        value.contains("crèche") ||
        value.contains("creche") ||
        value.contains("kassim") ||
        value.contains("kasim") ||
        value.contains("enfant") ||
        value.contains("inscription")) {
      score += 25;
    }

    if (value.contains("courses") ||
        value.contains("course") ||
        value.contains("lait") ||
        value.contains("couches") ||
        value.contains("repas") ||
        value.contains("pharmacie")) {
      score += 15;
    }

    if (value.contains("cadeau") ||
        value.contains("déco") ||
        value.contains("deco") ||
        value.contains("shopping plaisir") ||
        value.contains("plus tard") ||
        value.contains("quand j'ai le temps")) {
      score -= 15;
    }

    if (task.dueDate.trim().isNotEmpty) {
      final dueDate = DateTime.tryParse(task.dueDate.trim());
      final today = startOfToday();

      if (dueDate != null) {
        final days = dueDate.difference(today).inDays;

        if (days <= 0) {
          score += 40;
        } else if (days == 1) {
          score += 30;
        } else if (days <= 3) {
          score += 20;
        } else if (days <= 7) {
          score += 10;
        }
      }
    }

    return score.clamp(0, 100);
  }

  static String priorityLabel(TaskModel task) {
    final score = priorityScore(task);

    if (score >= 75) return "Urgent";
    if (score >= 50) return "Important";
    if (score >= 25) return "À faire";
    return "Flexible";
  }

  static List<TaskModel> sortTasksByPriority(List<TaskModel> tasks) {
    final sorted = [...tasks];

    sorted.sort((a, b) {
      final scoreCompare = priorityScore(b).compareTo(priorityScore(a));

      if (scoreCompare != 0) return scoreCompare;

      return a.createdAt.compareTo(b.createdAt);
    });

    return sorted;
  }

  static String priorityBulletList(List<TaskModel> tasks) {
    final sorted = sortTasksByPriority(tasks);

    return sorted.map((task) {
      return "• ${task.title} — ${priorityLabel(task)}";
    }).join("\n");
  }

  static Future<List<TaskModel>> getRelatedOutsideTasks({
    required TaskModel mainTask,
    required String originalMessage,
  }) async {
    final allTasks = await TaskService.getTasks();

    final mainType = detectTaskType(originalMessage, mainTask);

    if (!isOutsideTypeGroup(mainType)) {
      return [mainTask];
    }

    final related = <TaskModel>[];
    final seenTitles = <String>{};

    void addTask(TaskModel task) {
      final key = normalizedTaskTitle(task.title);
      if (key.isEmpty || seenTitles.contains(key)) return;

      seenTitles.add(key);
      related.add(task);
    }

    addTask(mainTask);

    for (final task in allTasks) {
      if (task.isDone) continue;

      final type = detectTaskType(task.title, task);

      if (!isOutsideTypeGroup(type)) continue;

      final outside = isOutsideTask(
        type: type,
        originalMessage: task.title,
        task: task,
      );

      if (!outside) continue;

      addTask(task);
    }

    return sortTasksByPriority(related).take(6).toList();
  }

  static Future<SmartPlanningProposal> buildGroupedProposal({
    required TaskModel mainTask,
    required String originalMessage,
    required List<TaskModel> groupedTasks,
    int travelGoMinutes = 0,
    int travelBackMinutes = 0,
    int? actionMinutesOverride,
    List<Map<String, dynamic>> memoryReasoning = const [],
  }) async {
    final events = await EventService.getEvents();
    final safeTasks = groupedTasks.isEmpty ? [mainTask] : groupedTasks;

    final type = detectTaskType(originalMessage, mainTask);
    final targetDate = targetDateFromText(originalMessage, mainTask);
    final actionMinutes =
        actionMinutesOverride ?? estimateGroupedActionMinutes(safeTasks);
    final marginMinutes =
        defaultMarginMinutes(type) + ((safeTasks.length - 1) * 5);
    final totalMinutes =
        actionMinutes + travelGoMinutes + travelBackMinutes + marginMinutes;

    final slot = findBestSlot(
      targetDate: targetDate,
      totalMinutes: totalMinutes,
      events: events,
      avoidMorning: shouldAvoidMorning(memoryReasoning),
      preferredStartHour: prefersAfternoon(memoryReasoning) ? 13 : null,
      preferredEndHour: prefersAfternoon(memoryReasoning) ? 17 : null,
    );

    final title = groupedTasksLabel(safeTasks);

    if (slot == null) {
      final explanation = "J’ai regroupé ${safeTasks.length} to-do, "
          "mais je n’ai pas trouvé de créneau libre réaliste sur la journée demandée.";

      return SmartPlanningProposal(
        canPropose: false,
        taskTitle: title,
        taskType: type,
        needsTravel: true,
        date: formatIsoDate(targetDate),
        startTime: "",
        endTime: "",
        actionMinutes: actionMinutes,
        travelGoMinutes: travelGoMinutes,
        travelBackMinutes: travelBackMinutes,
        marginMinutes: marginMinutes,
        totalMinutes: totalMinutes,
        explanation: explanation,
        confirmationMessage:
            "$explanation\n\nTu veux que je cherche un autre jour ?",
      );
    }

    final slotEnd = slot.add(Duration(minutes: totalMinutes));
    final dateLabel = humanDateLabel(targetDate);
    final startTime = formatIsoTime(slot);
    final endTime = formatIsoTime(slotEnd);

    final explanation = "Je peux regrouper ces to-do $dateLabel de "
        "$startTime à $endTime.\n\n"
        "Tu veux que je réserve ce bloc dans ton agenda ?";

    return SmartPlanningProposal(
      canPropose: true,
      taskTitle: title,
      taskType: type,
      needsTravel: true,
      date: formatIsoDate(targetDate),
      startTime: startTime,
      endTime: endTime,
      actionMinutes: actionMinutes,
      travelGoMinutes: travelGoMinutes,
      travelBackMinutes: travelBackMinutes,
      marginMinutes: marginMinutes,
      totalMinutes: totalMinutes,
      explanation: explanation,
      confirmationMessage: explanation,
    );
  }

  static Future<SmartPlanningProposal> buildProposal({
    required TaskModel task,
    required String originalMessage,
    int travelGoMinutes = 0,
    int travelBackMinutes = 0,
    int? actionMinutesOverride,
    List<Map<String, dynamic>> memoryReasoning = const [],
  }) async {
    final events = await EventService.getEvents();

    final type = detectTaskType(originalMessage, task);
    final outside = isOutsideTask(
      type: type,
      originalMessage: originalMessage,
      task: task,
    );

    final targetDate = targetDateFromText(originalMessage, task);
    final actionMinutes = actionMinutesOverride ??
        actionDurationForType(type, originalMessage, task);
    final marginMinutes = defaultMarginMinutes(type);
    final totalMinutes =
        actionMinutes + travelGoMinutes + travelBackMinutes + marginMinutes;

    final slot = findBestSlot(
      targetDate: targetDate,
      totalMinutes: totalMinutes,
      events: events,
    );

    if (slot == null) {
      final explanation = "J’ai créé la tâche « ${task.title} ».\n\n"
          "J’estime qu’il faut environ ${durationLabel(totalMinutes)} au total, "
          "mais je n’ai pas trouvé de créneau libre réaliste sur la journée demandée.";

      return SmartPlanningProposal(
        canPropose: false,
        taskTitle: task.title,
        taskType: type,
        needsTravel: outside,
        date: formatIsoDate(targetDate),
        startTime: "",
        endTime: "",
        actionMinutes: actionMinutes,
        travelGoMinutes: travelGoMinutes,
        travelBackMinutes: travelBackMinutes,
        marginMinutes: marginMinutes,
        totalMinutes: totalMinutes,
        explanation: explanation,
        confirmationMessage:
            "$explanation\n\nTu veux que je cherche un autre jour ?",
      );
    }

    final slotEnd = slot.add(Duration(minutes: totalMinutes));
    final dateLabel = humanDateLabel(targetDate);
    final startTime = formatIsoTime(slot);
    final endTime = formatIsoTime(slotEnd);

    final explanation = "Je peux te proposer $dateLabel de "
        "$startTime à $endTime.\n\n"
        "Tu veux que je réserve ce créneau dans ton agenda ?";

    return SmartPlanningProposal(
      canPropose: true,
      taskTitle: task.title,
      taskType: type,
      needsTravel: outside,
      date: formatIsoDate(targetDate),
      startTime: startTime,
      endTime: endTime,
      actionMinutes: actionMinutes,
      travelGoMinutes: travelGoMinutes,
      travelBackMinutes: travelBackMinutes,
      marginMinutes: marginMinutes,
      totalMinutes: totalMinutes,
      explanation: explanation,
      confirmationMessage: explanation,
    );
  }

  static EventModel eventFromProposal(SmartPlanningProposal proposal) {
    final startIso = "${proposal.date}T${proposal.startTime}:00";
    final endIso = "${proposal.date}T${proposal.endTime}:00";

    return EventModel(
      title: proposal.taskTitle,
      date: proposal.date,
      time: proposal.startTime,
      notes: "Planifié par Zelia depuis une tâche.\n"
          "Type : ${proposal.taskType}\n"
          "Durée action : ${durationLabel(proposal.actionMinutes)}\n"
          "Trajet aller : ${durationLabel(proposal.travelGoMinutes)}\n"
          "Trajet retour : ${durationLabel(proposal.travelBackMinutes)}\n"
          "Marge : ${durationLabel(proposal.marginMinutes)}",
      category: "Personnel",
      createdAt: DateTime.now(),
      startDateTimeIso: startIso,
      endTime: proposal.endTime,
      endDateTimeIso: endIso,
      durationMinutes: proposal.totalMinutes,
      travelMinutes: proposal.travelGoMinutes + proposal.travelBackMinutes,
      isRecurring: false,
      recurringType: "",
      recurringWeekday: 0,
      recurringUntil: "",
      parentRecurringId: "",
    );
  }
}
