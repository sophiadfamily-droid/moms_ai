import '../models/task_model.dart';
import 'priority_engine_service.dart';
import 'time_priority_service.dart';

class AiPriorityService {
  static int calculatePriority(TaskModel task) {
    int score = 40;

    final planning = task.planning.toLowerCase();
    final priority = task.priority.toLowerCase();

    final text = '${task.title} ${task.notes} ${task.dueDate}'.toLowerCase();

    final analysis = PriorityEngineService.analyze(text);

    if (task.isImportant || priority == 'haute') {
      score += 25;
    }

    if (task.dueDate.trim().isNotEmpty) {
      score += 15;
    }

    score += (analysis['score'] as int) * 3;

    score += TimePriorityService.urgencyScore(text) * 4;

    if (planning == 'aujourd’hui' || planning == "aujourd'hui") {
      score += 15;
    }

    if (planning == 'cette semaine') {
      score += 8;
    }

    if (planning == 'plus tard') {
      score -= 15;
    }

    return score.clamp(0, 100);
  }

  static String priorityLabel(TaskModel task) {
    final score = calculatePriority(task);

    if (score >= 85) return 'Priorité très haute';
    if (score >= 70) return 'Priorité haute';
    if (score >= 45) return 'Priorité normale';

    return 'Faible priorité';
  }

  static String smartSection(TaskModel task) {
    final score = calculatePriority(task);

    if (score >= 85) return '🔥 Urgent';
    if (score >= 70) return '⚡ À faire rapidement';
    if (task.isImportant) return '🧠 Important';
    if (task.planning == 'Plus tard') return '🌙 Plus tard';

    return '✨ À organiser';
  }

  static List<TaskModel> sortTasks(List<TaskModel> tasks) {
    final sorted = [...tasks];

    sorted.sort((a, b) {
      if (a.isDone != b.isDone) return a.isDone ? 1 : -1;

      final priorityCompare =
          calculatePriority(b).compareTo(calculatePriority(a));

      if (priorityCompare != 0) return priorityCompare;

      return b.createdAt.compareTo(a.createdAt);
    });

    return sorted;
  }

  static String homeSuggestion(List<TaskModel> tasks) {
    return quickSuggestion(tasks);
  }

  static String quickSuggestion(List<TaskModel> tasks) {
    final openTasks = sortTasks(
      tasks.where((task) => !task.isDone).toList(),
    );

    if (openTasks.isEmpty) {
      return 'Aucune tâche urgente pour le moment.';
    }

    final topTask = openTasks.first;

    final urgentCount = openTasks.where((task) {
      return calculatePriority(task) >= 85;
    }).length;

    if (urgentCount > 0) {
      return urgentCount == 1
          ? '1 urgence : ${topTask.title}'
          : '$urgentCount urgences : ${topTask.title}';
    }

    if (topTask.isImportant || topTask.priority == 'Haute') {
      return 'Important : ${topTask.title}';
    }

    return 'Priorité : ${topTask.title}';
  }

  static String detailedSuggestion(List<TaskModel> tasks) {
    final openTasks = sortTasks(
      tasks.where((task) => !task.isDone).toList(),
    );

    if (openTasks.isEmpty) {
      return "Tu n’as aucune tâche urgente pour le moment 💕\n\n"
          "Tu peux souffler un peu, ajouter une prochaine action, ou me demander de t’aider à organiser ta journée.";
    }

    final topTask = openTasks.first;

    final todayTasks = openTasks.where((task) {
      return task.planning == 'Aujourd’hui';
    }).toList();

    final importantTasks = openTasks.where((task) {
      return task.isImportant || task.priority == 'Haute';
    }).toList();

    final urgentTasks = openTasks.where((task) {
      return calculatePriority(task) >= 85;
    }).toList();

    final buffer = StringBuffer();

    buffer.writeln('Voici ma suggestion complète 💕');
    buffer.writeln();

    if (urgentTasks.isNotEmpty) {
      buffer.writeln(
        urgentTasks.length == 1
            ? 'Tu as 1 tâche urgente.'
            : 'Tu as ${urgentTasks.length} tâches urgentes.',
      );
    } else if (importantTasks.isNotEmpty) {
      buffer.writeln(
        importantTasks.length == 1
            ? 'Tu as 1 tâche importante.'
            : 'Tu as ${importantTasks.length} tâches importantes.',
      );
    } else if (todayTasks.isNotEmpty) {
      buffer.writeln(
        todayTasks.length == 1
            ? 'Tu as 1 tâche prévue aujourd’hui.'
            : 'Tu as ${todayTasks.length} tâches prévues aujourd’hui.',
      );
    } else {
      buffer.writeln('Tu as ${openTasks.length} tâche(s) en attente.');
    }

    buffer.writeln();
    buffer.writeln('La priorité maintenant :');
    buffer.writeln('• ${topTask.title}');
    buffer.writeln();

    if (topTask.dueDate.trim().isNotEmpty) {
      buffer.writeln('Pourquoi : il y a une échéance à surveiller.');
    } else if (topTask.isImportant || topTask.priority == 'Haute') {
      buffer.writeln(
        'Pourquoi : cette tâche a un impact important sur ton organisation.',
      );
    } else if (topTask.planning == 'Aujourd’hui') {
      buffer.writeln('Pourquoi : elle est prévue aujourd’hui.');
    } else {
      buffer.writeln(
        'Pourquoi : c’est la prochaine action la plus logique à avancer.',
      );
    }

    buffer.writeln();
    buffer.writeln(
      'Je te conseille de commencer par celle-ci, puis d’avancer une tâche après l’autre.',
    );

    return buffer.toString().trim();
  }
}
