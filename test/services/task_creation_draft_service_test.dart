import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/services/task_creation_draft_service.dart';

void main() {
  test('extracts known fields and leaves an absent task title absent', () {
    final draft = const TaskCreationDraftService().extract(
      'Crée une tâche prioritaire pour demain.',
      referenceDate: DateTime.utc(2026, 7, 27),
    );

    expect(draft, isNotNull);
    expect(draft!.title, isEmpty);
    expect(draft.dueDate, '2026-07-28');
    expect(draft.priority, 'Haute');
    expect(draft.isImportant, isTrue);
  });

  test('does not treat priority consultation as task creation', () {
    expect(
      const TaskCreationDraftService().extract(
        'Quelles sont mes priorités ?',
        referenceDate: DateTime.utc(2026, 7, 27),
      ),
      isNull,
    );
  });
}
