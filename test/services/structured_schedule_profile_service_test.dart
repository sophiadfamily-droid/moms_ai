import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/human/human_model.dart';
import 'package:moms_ai/services/structured_schedule_profile_service.dart';

void main() {
  test('conserve les horaires futurs et retire les horaires datés passés', () {
    final model = _model([
      _record('past', '2026-08-16', '09:00', '17:00'),
      _record('future', '2026-08-18', '21:00', '09:00', nextDay: true),
      _weeklyRecord(),
    ]);

    final cleaned = StructuredScheduleProfileService.pruneExpired(
      model,
      at: DateTime(2026, 8, 17, 12),
    );
    final entries = StructuredScheduleProfileService.entriesForPerson(
      cleaned.persons.single,
      at: DateTime(2026, 8, 17, 12),
    );

    expect(entries.map((entry) => entry.sourceKey), ['weekly', 'future']);
    expect(entries.last.endsNextDay, isTrue);
  });

  test('ne retire une plage de nuit qu’après sa fin le lendemain', () {
    final model = _model([
      _record('night', '2026-08-17', '21:00', '09:00', nextDay: true),
    ]);

    expect(
      StructuredScheduleProfileService.entriesForPerson(
        model.persons.single,
        at: DateTime(2026, 8, 18, 8, 59),
      ),
      hasLength(1),
    );
    expect(
      StructuredScheduleProfileService.entriesForPerson(
        model.persons.single,
        at: DateTime(2026, 8, 18, 9, 1),
      ),
      isEmpty,
    );
  });
}

HumanModel _model(List<Map<String, Object?>> schedules) => HumanModel(
      accountScopeId: 'account-a',
      primaryPersonId: 'person-a',
      persons: [
        HumanPerson(
          id: 'person-a',
          accountScopeId: 'account-a',
          displayName: 'Willy',
          evidence: const HumanEvidence(
            source: HumanInformationSource.imported,
            confirmation: HumanConfirmationStatus.confirmed,
          ),
          customFields: {'structuredSchedulesV1': schedules},
        ),
      ],
    );

Map<String, Object?> _record(
  String key,
  String date,
  String start,
  String end, {
  bool nextDay = false,
}) =>
    {
      'sourceKey': key,
      'target': 'workSchedule',
      'temporalKind': 'dated',
      'title': 'Travail',
      'dateIso': date,
      'weekdays': const <int>[],
      'startTime': start,
      'endTime': end,
      if (nextDay) 'endsNextDay': true,
    };

Map<String, Object?> _weeklyRecord() => {
      'sourceKey': 'weekly',
      'target': 'workSchedule',
      'temporalKind': 'recurringWeekly',
      'title': 'Travail habituel',
      'weekdays': const [DateTime.monday],
      'startTime': '09:00',
      'endTime': '17:00',
    };
