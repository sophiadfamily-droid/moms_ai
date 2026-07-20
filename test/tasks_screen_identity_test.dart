import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/task_model.dart';
import 'package:moms_ai/screens/tasks_screen.dart';
import 'package:moms_ai/services/task_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('interface creation persists a task with an ID', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const MaterialApp(home: TasksScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.enterText(_titleField, 'Tâche interface');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final addButton = find.widgetWithText(ElevatedButton, 'Ajouter');
    await tester.ensureVisible(addButton);
    tester.widget<ElevatedButton>(addButton).onPressed!();
    await tester.pumpAndSettle();

    final stored = await _storedTasks();
    expect(stored, hasLength(1));
    expect(stored.single.title, 'Tâche interface');
    expect(stored.single.id, isNotNull);
    expect(stored.single.id, isNotEmpty);
  });

  testWidgets('interface editing preserves the persisted task ID',
      (tester) async {
    final task = TaskModel(
      id: 'task-interface',
      title: 'Titre initial',
      category: 'Perso',
      isDone: false,
      createdAt: DateTime(2026, 7, 20),
    );
    SharedPreferences.setMockInitialValues({
      TaskService.tasksKey: [jsonEncode(task.toJson())],
    });

    await tester.pumpWidget(
      const MaterialApp(home: TasksScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Titre initial'));
    await tester.pumpAndSettle();

    await tester.enterText(_titleField, 'Titre modifié');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final saveButton = find.widgetWithText(ElevatedButton, 'Enregistrer');
    await tester.ensureVisible(saveButton);
    tester.widget<ElevatedButton>(saveButton).onPressed!();
    await tester.pumpAndSettle();

    final stored = await _storedTasks();
    expect(stored, hasLength(1));
    expect(stored.single.title, 'Titre modifié');
    expect(stored.single.id, 'task-interface');
  });
}

final Finder _titleField = find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == 'Titre',
);

Future<List<TaskModel>> _storedTasks() async {
  final prefs = await SharedPreferences.getInstance();
  final stored = prefs.getStringList(TaskService.tasksKey) ?? const [];
  return stored
      .map(
        (task) => TaskModel.fromJson(
          Map<String, dynamic>.from(jsonDecode(task) as Map),
        ),
      )
      .toList();
}
