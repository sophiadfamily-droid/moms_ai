import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/task_model.dart';
import 'cloud_task_service.dart';

class TaskService {
  static const String tasksKey = "tasks";

  static final ValueNotifier<int> tasksVersion = ValueNotifier<int>(0);

  static void notifyTasksChanged() {
    tasksVersion.value++;
  }

  static Future<void> saveTasks(List<TaskModel> tasks) async {
    final prefs = await SharedPreferences.getInstance();

    final List<String> encoded =
        tasks.map((task) => jsonEncode(task.toJson())).toList();

    await prefs.setStringList(tasksKey, encoded);

    try {
      await CloudTaskService.saveTasks(tasks);
    } catch (_) {
      // Les tâches restent disponibles hors ligne ou sans compte connecté.
    }

    notifyTasksChanged();
  }

  static Future<List<TaskModel>> getTasks() async {
    final prefs = await SharedPreferences.getInstance();

    final data = prefs.getStringList(tasksKey);

    final localTasks = data == null
        ? <TaskModel>[]
        : data.map((task) {
            return TaskModel.fromJson(jsonDecode(task));
          }).toList();

    try {
      final cloudTasks = await CloudTaskService.getTasks();

      if (cloudTasks.isNotEmpty) {
        final encoded =
            cloudTasks.map((task) => jsonEncode(task.toJson())).toList();

        await prefs.setStringList(tasksKey, encoded);

        return cloudTasks;
      }

      if (localTasks.isNotEmpty) {
        await CloudTaskService.saveTasks(localTasks);
      }
    } catch (_) {
      // Si Firestore est indisponible, on utilise les tâches locales.
    }

    return localTasks;
  }

  static Future<void> addTask(TaskModel task) async {
    final tasks = await getTasks();
    tasks.add(task);
    await saveTasks(tasks);
  }

  static Future<void> updateTasks(List<TaskModel> tasks) async {
    await saveTasks(tasks);
  }

  static Future<void> clearTasks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(tasksKey);

    try {
      await CloudTaskService.clearTasks();
    } catch (_) {
      // Suppression cloud ignorée si hors ligne.
    }

    notifyTasksChanged();
  }
}
