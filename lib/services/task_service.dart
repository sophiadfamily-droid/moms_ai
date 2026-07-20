import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/identity/entity_id_generator.dart';
import '../core/identity/entity_identity.dart';
import '../core/identity/entity_matcher.dart';
import '../core/identity/uuid_v7_entity_id_generator.dart';
import '../models/task_model.dart';
import 'cloud_task_service.dart';

class TaskService {
  static const String tasksKey = "tasks";

  static final EntityMatcher<TaskModel> _taskMatcher = EntityMatcher(
    idOf: (task) => task.id,
    legacyEquals: (first, second) => first == second,
  );

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
    } catch (error, stackTrace) {
      debugPrint('Cloud tasks sync failed: $error');
      debugPrint('$stackTrace');
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
    } catch (error, stackTrace) {
      debugPrint('Cloud tasks load failed: $error');
      debugPrint('$stackTrace');
    }

    return localTasks;
  }

  static Future<void> addTask(
    TaskModel task, {
    EntityIdGenerator idGenerator = const UuidV7EntityIdGenerator(),
  }) async {
    final tasks = await getTasks();
    tasks.add(_withIdForCreation(task, idGenerator));
    await saveTasks(tasks);
  }

  static TaskModel _withIdForCreation(
    TaskModel task,
    EntityIdGenerator idGenerator,
  ) {
    if (EntityIdentity.isValid(task.id)) return task;
    final generatedId = idGenerator.generate();
    return task.copyWith(id: generatedId);
  }

  static bool areSameTask(TaskModel first, TaskModel second) {
    return _taskMatcher.matches(first, second);
  }

  static Future<void> updateTasks(List<TaskModel> tasks) async {
    await saveTasks(tasks);
  }

  static Future<void> clearTasks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(tasksKey);

    try {
      await CloudTaskService.clearTasks();
    } catch (error, stackTrace) {
      debugPrint('Cloud tasks clear failed: $error');
      debugPrint('$stackTrace');
    }

    notifyTasksChanged();
  }
}
