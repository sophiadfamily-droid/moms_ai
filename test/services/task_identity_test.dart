import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/task_model.dart';
import 'package:moms_ai/services/action_handler_service.dart';
import 'package:moms_ai/services/cloud_task_service.dart';
import 'package:moms_ai/services/planning_draft_service.dart';
import 'package:moms_ai/services/task_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_entity_id_generator.dart';

void main() {
  TaskModel buildTask({
    String? id,
    String title = 'Appeler l’école',
    String category = 'Famille',
  }) {
    return TaskModel(
      id: id,
      title: title,
      category: category,
      isDone: false,
      createdAt: DateTime(2026, 7, 20, 9, 30),
      isImportant: true,
      dueDate: '2026-07-22',
      notes: 'Demander les horaires',
      planning: 'Cette semaine',
      priority: 'Haute',
    );
  }

  group('TaskModel stable identity', () {
    test('copyWith preserves ID across all editable business fields', () {
      final task = buildTask(id: 'task-1');

      final updated = task.copyWith(
        title: 'Nouveau titre',
        category: 'Admin',
        notes: 'Nouvelle description',
        dueDate: '2026-08-01',
        priority: 'Basse',
      );

      expect(updated.id, 'task-1');
      expect(updated.title, 'Nouveau titre');
      expect(updated.category, 'Admin');
      expect(updated.notes, 'Nouvelle description');
      expect(updated.dueDate, '2026-08-01');
      expect(updated.priority, 'Basse');
    });

    test('JSON round trip preserves an existing ID', () {
      final task = buildTask(id: 'task-1');

      expect(task.toJson()['id'], 'task-1');
      expect(TaskModel.fromJson(task.toJson()).id, 'task-1');
    });

    test('legacy JSON remains readable without inventing an ID', () {
      final json = buildTask().toJson();
      final restored = TaskModel.fromJson(json);

      expect(json, isNot(containsPair('id', anything)));
      expect(restored.id, isNull);
      expect(restored.title, 'Appeler l’école');
    });
  });

  group('TaskService identity comparison', () {
    test('same valid IDs identify the same task after editing', () {
      final task = buildTask(id: 'task-1');
      final edited = task.copyWith(title: 'Titre modifié');

      expect(TaskService.areSameTask(task, edited), isTrue);
    });

    test('different valid IDs override identical business fields', () {
      final first = buildTask(id: 'task-1');
      final second = buildTask(id: 'task-2');

      expect(TaskService.areSameTask(first, second), isFalse);
    });

    test('legacy fallback keeps historical instance equality', () {
      final task = buildTask();
      final separateCopy = buildTask();

      expect(TaskService.areSameTask(task, task), isTrue);
      expect(TaskService.areSameTask(task, separateCopy), isFalse);
    });

    test('ID-first deletion removes only the selected task', () {
      final selected = buildTask(id: 'task-1');
      final duplicate = buildTask(id: 'task-2');
      final tasks = [selected, duplicate]..removeWhere(
          (task) => TaskService.areSameTask(task, selected),
        );

      expect(tasks, [same(duplicate)]);
    });
  });

  group('TaskService creation identity', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('generates exactly one ID at the persistence boundary', () async {
      final generator = FakeEntityIdGenerator(['task-generated']);

      await TaskService.addTask(buildTask(), idGenerator: generator);

      final stored = await _storedTasks();
      expect(generator.callCount, 1);
      expect(stored.single.id, 'task-generated');
    });

    test('preserves a valid ID without calling the generator', () async {
      final generator = FakeEntityIdGenerator(['unused']);

      await TaskService.addTask(
        buildTask(id: 'task-existing'),
        idGenerator: generator,
      );

      final stored = await _storedTasks();
      expect(generator.callCount, 0);
      expect(stored.single.id, 'task-existing');
    });

    test('copies an authenticated fixed-length snapshot before appending',
        () async {
      final existing = List<TaskModel>.unmodifiable([
        buildTask(id: 'existing-task'),
      ]);
      List<TaskModel>? persisted;

      await TaskService.addTask(
        buildTask(id: 'conversation-action-id', title: 'Nouvelle tâche'),
        loadTasks: () async => existing,
        persistTasks: (tasks) async {
          persisted = tasks;
        },
      );

      expect(existing, hasLength(1));
      expect(persisted, hasLength(2));
      expect(persisted!.last.id, 'conversation-action-id');
      expect(() => persisted!.add(buildTask()), returnsNormally);
    });

    test('preserves the technical persistence cause without task content',
        () async {
      final failure = StateError('synthetic_store_unavailable');

      await expectLater(
        TaskService.addTask(
          buildTask(id: 'conversation-action-id'),
          loadTasks: () async => const [],
          persistTasks: (_) async => throw failure,
        ),
        throwsA(
          isA<TaskStorageException>()
              .having((error) => error.step, 'step', 'persist')
              .having(
                (error) => error.code,
                'code',
                'task_persist_failed',
              )
              .having((error) => error.cause, 'cause', same(failure)),
        ),
      );
    });

    test('replaces empty and whitespace IDs exactly once each', () async {
      final generator = FakeEntityIdGenerator(['from-empty', 'from-blank']);

      await TaskService.addTask(
        buildTask(id: ''),
        idGenerator: generator,
      );
      await TaskService.addTask(
        buildTask(id: '   ', title: 'Deuxième tâche'),
        idGenerator: generator,
      );

      final stored = await _storedTasks();
      expect(generator.callCount, 2);
      expect(stored.map((task) => task.id).toSet(), {
        'from-empty',
        'from-blank',
      });
    });

    test('SharedPreferences preserves IDs and legacy null IDs', () async {
      await TaskService.saveTasks([
        buildTask(id: 'task-local'),
        buildTask(title: 'Legacy'),
      ]);

      final stored = await _storedTasks();
      expect(stored.first.id, 'task-local');
      expect(stored.last.id, isNull);
    });

    test('chat creation receives an ID only through TaskService', () async {
      final result = await ActionHandlerService.handleAction(
        action: {'type': 'task', 'title': 'Tâche du chat'},
        currentUserMessage: 'Ajoute une tâche',
        normalizeTime: (value) => value,
        parseDurationMinutes: (value) => 0,
        weekdayFromText: () => 0,
        messageLooksRecurringWeekly: () => false,
        nextDateForWeekday: (weekday) => '',
        eventNeedsTravel: (action) => false,
        buildStartDateTimeIso: ({required date, required time}) => '',
        buildEndDateTimeIso: ({
          required date,
          required time,
          required durationMinutes,
        }) =>
            '',
        endTimeFromDuration: ({
          required date,
          required time,
          required durationMinutes,
        }) =>
            '',
      );

      final pendingTask = result.pendingSmartPlanningTask?['task'];
      final stored = await _storedTasks();
      expect(pendingTask, isA<TaskModel>());
      expect((pendingTask as TaskModel).id, isNull);
      expect(stored.single.id, isNotNull);
      expect(stored.single.id, isNotEmpty);
    });

    test('planning draft tasks remain unpersisted and unidentified', () async {
      final pending = PlanningDraftService.toPendingDurationPlanningTask(
        PlanningDraftService.buildFromAction(
          action: {
            'type': 'event',
            'title': 'Préparer le rendez-vous',
            'date': '2026-07-24',
          },
          sourceMessage: 'Préparer le rendez-vous vendredi',
          needsTravel: false,
        ),
      );

      final task = pending['task'] as TaskModel;
      expect(task.id, isNull);
      expect(await _storedTasks(), isEmpty);
    });
  });

  group('CloudTaskService identity compatibility', () {
    test('Firestore loading injects the document ID', () {
      final task = CloudTaskService.taskFromDocument(
        documentId: 'firestore-task-id',
        data: buildTask().toJson(),
      );

      expect(task.id, 'firestore-task-id');
    });

    test('valid ID selects the document and stays out of cloud data', () {
      final task = buildTask(id: 'task-1');
      final expectedPayload = Map<String, dynamic>.from(task.toJson())
        ..remove('id');

      expect(CloudTaskService.documentIdForTask(task), 'task-1');
      expect(CloudTaskService.firestoreDataForTask(task), expectedPayload);
      expect(
        CloudTaskService.firestoreDataForTask(task),
        isNot(containsPair('id', anything)),
      );
    });

    test('missing, empty and whitespace IDs use the exact legacy hash', () {
      final task = buildTask();
      final raw = [
        task.createdAt.toIso8601String(),
        task.title,
        task.category,
      ].join('|');
      final legacyId = base64Url.encode(utf8.encode(raw)).replaceAll('=', '');

      expect(CloudTaskService.documentIdForTask(task), legacyId);
      expect(
        CloudTaskService.documentIdForTask(task.copyWith(id: '')),
        legacyId,
      );
      expect(
        CloudTaskService.documentIdForTask(task.copyWith(id: '   ')),
        legacyId,
      );
    });
  });
}

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
