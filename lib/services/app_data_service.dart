import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AppDataService {
  static const String tasksKey =
      "tasks";

  static const String shoppingKey =
      "shopping";

  static const String agendaKey =
      "agenda";

  // TASKS

  static Future<void> saveTasks(
    List<String> tasks,
  ) async {
    final prefs =
        await SharedPreferences.getInstance();

    await prefs.setString(
      tasksKey,
      jsonEncode(tasks),
    );
  }

  static Future<List<String>>
      getTasks() async {
    final prefs =
        await SharedPreferences.getInstance();

    final data =
        prefs.getString(tasksKey);

    if (data == null) {
      return [];
    }

    return List<String>.from(
      jsonDecode(data),
    );
  }

  // SHOPPING

  static Future<void> saveShopping(
    List<String> shopping,
  ) async {
    final prefs =
        await SharedPreferences.getInstance();

    await prefs.setString(
      shoppingKey,
      jsonEncode(shopping),
    );
  }

  static Future<List<String>>
      getShopping() async {
    final prefs =
        await SharedPreferences.getInstance();

    final data =
        prefs.getString(shoppingKey);

    if (data == null) {
      return [];
    }

    return List<String>.from(
      jsonDecode(data),
    );
  }

  // AGENDA

  static Future<void> saveAgenda(
    List<Map<String, String>> agenda,
  ) async {
    final prefs =
        await SharedPreferences.getInstance();

    await prefs.setString(
      agendaKey,
      jsonEncode(agenda),
    );
  }

  static Future<
      List<Map<String, String>>>
      getAgenda() async {
    final prefs =
        await SharedPreferences.getInstance();

    final data =
        prefs.getString(agendaKey);

    if (data == null) {
      return [];
    }

    final decoded =
        jsonDecode(data) as List;

    return decoded.map((item) {
      return Map<String, String>.from(
          item);
    }).toList();
  }
}

