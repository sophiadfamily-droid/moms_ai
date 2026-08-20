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

  testWidgets('contextual task card uses the shared compact height',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const MaterialApp(home: TasksScreen()),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const Key('proactive-priority-card'))).height,
      106,
    );
  });

  testWidgets('task page exposes only Toutes and Urgentes filters',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MaterialApp(home: TasksScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Toutes'), findsOneWidget);
    expect(find.text('Urgentes'), findsOneWidget);
    expect(find.text('Semaine'), findsNothing);
    expect(find.text('Important'), findsNothing);
    expect(find.text('Terminé'), findsNothing);
  });

  testWidgets('task editor keeps only useful visible fields', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MaterialApp(home: TasksScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('Titre'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Date limite'), findsOneWidget);
    expect(find.text('Temps nécessaire'), findsOneWidget);
    expect(find.text('Urgent'), findsOneWidget);
    expect(find.text('À faire'), findsNothing);
    expect(find.text('Priorité'), findsNothing);
    expect(find.text('Catégorie'), findsNothing);
    expect(find.text('Marquer comme important'), findsNothing);
  });

  testWidgets('optional duration is stored and remains editable',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MaterialApp(home: TasksScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(_titleField, 'Faire ma valise');
    await tester.enterText(_durationField, '1 h');
    final addButton = find.widgetWithText(ElevatedButton, 'Ajouter');
    await tester.ensureVisible(addButton);
    tester.widget<ElevatedButton>(addButton).onPressed!();
    await tester.pumpAndSettle();

    final stored = await _storedTasks();
    expect(stored.single.durationMinutes, 60);
    expect(find.text('1 h'), findsOneWidget);
  });

  testWidgets('urgent toggle persists the canonical urgent signal',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MaterialApp(home: TasksScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(_titleField, 'Appeler le médecin');
    final urgentToggle = find.text('Urgent');
    await tester.ensureVisible(urgentToggle);
    await tester.tap(urgentToggle);
    await tester.pumpAndSettle();
    final addButton = find.widgetWithText(ElevatedButton, 'Ajouter');
    await tester.ensureVisible(addButton);
    tester.widget<ElevatedButton>(addButton).onPressed!();
    await tester.pumpAndSettle();

    final stored = await _storedTasks();
    expect(stored.single.isImportant, isTrue);
    expect(stored.single.priority, 'Haute');
  });

  testWidgets('task dates are displayed in French in the list and editor',
      (tester) async {
    final task = TaskModel(
      id: 'task-french-date',
      title: 'Faire ma valise',
      category: 'Perso',
      isDone: false,
      createdAt: DateTime(2026, 8, 20),
      dueDate: '2026-10-01',
    );
    SharedPreferences.setMockInitialValues({
      TaskService.tasksKey: [jsonEncode(task.toJson())],
    });

    await tester.pumpWidget(const MaterialApp(home: TasksScreen()));
    await tester.pumpAndSettle();

    expect(find.text('01/10/2026'), findsOneWidget);
    expect(find.text('2026-10-01'), findsNothing);

    await tester.tap(find.text('Faire ma valise'));
    await tester.pumpAndSettle();

    final dateField = tester.widget<TextField>(_dueDateField);
    expect(dateField.controller!.text, '01/10/2026');

    await tester.enterText(_dueDateField, 'ab02102026cd');
    await tester.pump();
    expect(
      tester.widget<TextField>(_dueDateField).controller!.text,
      '02/10/2026',
    );
    expect(
      tester.widget<TextField>(_dueDateField).keyboardType,
      TextInputType.number,
    );
    final saveButton = find.widgetWithText(ElevatedButton, 'Enregistrer');
    await tester.ensureVisible(saveButton);
    tester.widget<ElevatedButton>(saveButton).onPressed!();
    await tester.pumpAndSettle();

    final stored = await _storedTasks();
    expect(stored.single.dueDate, '2026-10-02');
    expect(find.text('02/10/2026'), findsOneWidget);
    expect(find.text('2026-10-02'), findsNothing);
  });

  testWidgets('an open urgent task always remains visible in the suggestion',
      (tester) async {
    final task = TaskModel(
      id: 'urgent-dentist',
      title: 'Appeler le dentiste',
      category: 'Perso',
      isDone: false,
      createdAt: DateTime(2026, 8, 20),
      isImportant: true,
      priority: 'Haute',
    );
    SharedPreferences.setMockInitialValues({
      TaskService.tasksKey: [jsonEncode(task.toJson())],
    });

    await tester.pumpWidget(const MaterialApp(home: TasksScreen()));
    await tester.pumpAndSettle();

    expect(find.text('À ne pas oublier'), findsOneWidget);
    expect(
      find.text('Pense à « Appeler le dentiste » en priorité.'),
      findsOneWidget,
    );
    expect(find.text('Voir la tâche'), findsOneWidget);

    await tester.tap(find.text('Voir la tâche'));
    await tester.pumpAndSettle();
    expect(find.text('Modifier la tâche'), findsOneWidget);
    expect(
      tester.widget<TextField>(_titleField).controller!.text,
      'Appeler le dentiste',
    );
  });
}

final Finder _titleField = find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == 'Titre',
);

final Finder _durationField = find.byWidgetPredicate(
  (widget) =>
      widget is TextField && widget.decoration?.labelText == 'Temps nécessaire',
);

final Finder _dueDateField = find.byWidgetPredicate(
  (widget) =>
      widget is TextField && widget.decoration?.labelText == 'Date limite',
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
