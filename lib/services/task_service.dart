import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/task_model.dart';

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
    notifyTasksChanged();
  }

  static Future<List<TaskModel>> getTasks() async {
    final prefs = await SharedPreferences.getInstance();

    final data = prefs.getStringList(tasksKey);

    if (data == null) {
      return [];
    }

    return data.map((task) {
      return TaskModel.fromJson(jsonDecode(task));
    }).toList();
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
    notifyTasksChanged();
  }
}
