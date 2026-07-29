import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/conversation_epistemic_models.dart';

void main() {
  test('decodes a closed non-executable Event clarification draft', () {
    final draft = ConversationClarificationDraft.fromJson(_draft());

    expect(
      draft.draftType,
      ConversationClarificationDraftType.eventCreation,
    );
    expect(draft.title, 'Consultation médecin');
    expect(draft.date, '2026-07-30');
    expect(draft.startTime, '15:00');
    expect(
      draft.expectedField,
      ConversationEventDraftExpectedField.duration,
    );
    expect(draft.durationMinutes, isNull);
  });

  test('invalid Event clarification drafts fail closed', () {
    for (final value in [
      {..._draft(), 'draftType': 'unknown'},
      {..._draft(), 'expectedField': 'unknown'},
      {..._draft(), 'date': '2026-02-31'},
      {..._draft(), 'startTime': '25:90'},
      {..._draft(), 'uid': 'forbidden'},
      {..._draft(), 'title': List.filled(121, 'x').join()},
    ]) {
      expect(
        () => ConversationClarificationDraft.fromJson(value),
        throwsFormatException,
      );
    }
  });
}

Map<String, dynamic> _draft() => {
      'schemaVersion': 1,
      'draftType': 'eventCreation',
      'logicalRequestId': 'logical-event',
      'draftId': 'event-draft',
      'title': 'Consultation médecin',
      'date': '2026-07-30',
      'startTime': '15:00',
      'durationMinutes': null,
      'travelGoMinutes': null,
      'travelBackMinutes': null,
      'marginMinutes': null,
      'expectedField': 'duration',
      'createdAt': '2026-07-29T12:00:00.000Z',
      'expiresAt': '2026-07-29T12:15:00.000Z',
      'sessionGeneration': 0,
    };
