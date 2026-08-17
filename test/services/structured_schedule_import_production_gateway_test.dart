import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/models/human/human_model.dart';
import 'package:moms_ai/models/human/human_model_persistence.dart';
import 'package:moms_ai/models/structured_schedule_import.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/repositories/human/human_model_cloud_repository.dart';
import 'package:moms_ai/services/human/human_model_edit_service.dart';
import 'package:moms_ai/services/human/human_model_local_repository.dart';
import 'package:moms_ai/services/human/human_model_service.dart';
import 'package:moms_ai/services/school_schedule_metadata_service.dart';
import 'package:moms_ai/services/structured_schedule_import_application_service.dart';
import 'package:moms_ai/services/structured_schedule_import_production_gateway.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('raccorde activité, école et rendez-vous aux bons domaines', () async {
    SharedPreferences.setMockInitialValues({});
    final fixture = await _Fixture.create();
    var profile = _profile();
    final events = <EventModel>[];
    final gateway = ProductionStructuredScheduleApplicationGateway(
      profileLoader: () async => profile,
      profileWriter: (value) async => profile = value,
      eventLoader: () async => List.of(events),
      eventWriter: (value) async => events.addAll(value),
      humanEditorFactory: () async => fixture.editor,
    );

    final result = await gateway.apply(_batch());

    expect(result.status, StructuredScheduleApplicationStatus.applied);
    expect(profile.personalActivities.single.title, 'Pilates');
    expect(
      SchoolScheduleMetadataService.daysFromRange(
        profile.personalActivities.single.timeRanges.single,
      ),
      ['Mercredi'],
    );
    expect(profile.children.single.schoolTimeRanges.single.startTime, '08:30');
    expect(
      SchoolScheduleMetadataService.daysFromRange(
        profile.children.single.schoolTimeRanges.single,
      ),
      ['Lundi', 'Mardi'],
    );
    expect(events.single.title, 'Dentiste');
    expect(events.single.date, '20/08/2026');
    expect(events.single.durationMinutes, 60);
    expect(events.single.location, 'Clinique');

    final primary = fixture.cloud.current!.model.personById('person-main')!;
    final child = fixture.cloud.current!.model.personById('person-child')!;
    expect(primary.customFields['structuredSchedulesV1'], isA<List>());
    expect(child.customFields['structuredSchedulesV1'], isA<List>());
  });

  test('le même import terminé ne crée aucun doublon', () async {
    SharedPreferences.setMockInitialValues({});
    final fixture = await _Fixture.create();
    var profile = _profile();
    final events = <EventModel>[];
    var profileWrites = 0;
    final gateway = ProductionStructuredScheduleApplicationGateway(
      profileLoader: () async => profile,
      profileWriter: (value) async {
        profileWrites++;
        return profile = value;
      },
      eventLoader: () async => List.of(events),
      eventWriter: (value) async => events.addAll(value),
      humanEditorFactory: () async => fixture.editor,
    );

    expect((await gateway.apply(_batch())).isSuccess, isTrue);
    final second = await gateway.apply(_batch());

    expect(second.status, StructuredScheduleApplicationStatus.alreadyApplied);
    expect(profileWrites, 1);
    expect(profile.personalActivities, hasLength(1));
    expect(profile.children.single.schoolTimeRanges, hasLength(1));
    expect(events, hasLength(1));
  });

  test('un événement de nuit se termine le lendemain', () async {
    SharedPreferences.setMockInitialValues({});
    final fixture = await _Fixture.create();
    var profile = _profile();
    final events = <EventModel>[];
    final gateway = ProductionStructuredScheduleApplicationGateway(
      profileLoader: () async => profile,
      profileWriter: (value) async => profile = value,
      eventLoader: () async => List.of(events),
      eventWriter: (value) async => events.addAll(value),
      humanEditorFactory: () async => fixture.editor,
    );
    final night = StructuredScheduleProposal(
      proposalId: 'night-event',
      target: StructuredScheduleTarget.event,
      temporalKind: StructuredScheduleTemporalKind.dated,
      title: 'Garde de nuit',
      subjectEntityId: 'person-main',
      subjectLabel: 'Sophia',
      dateIso: '2026-08-27',
      startTime: '21:00',
      endTime: '09:00',
      confidence: StructuredScheduleConfidence.high,
      state: StructuredScheduleProposalState.accepted,
    );

    final result = await gateway.apply(
      StructuredScheduleApplicationBatch(
        importId: 'import-night',
        accountScopeId: 'account-a',
        proposals: [night],
      ),
    );

    expect(result.isSuccess, isTrue);
    expect(events.single.durationMinutes, 12 * 60);
    expect(
      DateTime.parse(events.single.endDateTimeIso).day,
      DateTime.parse(events.single.startDateTimeIso).day + 1,
    );
  });

  test('le planning daté d’un proche ne devient pas un rendez-vous personnel',
      () async {
    SharedPreferences.setMockInitialValues({});
    final fixture = await _Fixture.create();
    var profile = _profile();
    final events = <EventModel>[];
    final gateway = ProductionStructuredScheduleApplicationGateway(
      profileLoader: () async => profile,
      profileWriter: (value) async => profile = value,
      eventLoader: () async => List.of(events),
      eventWriter: (value) async => events.addAll(value),
      humanEditorFactory: () async => fixture.editor,
    );
    final result = await gateway.apply(
      StructuredScheduleApplicationBatch(
        importId: 'import-child-event',
        accountScopeId: 'account-a',
        proposals: [
          StructuredScheduleProposal(
            proposalId: 'child-event',
            target: StructuredScheduleTarget.event,
            temporalKind: StructuredScheduleTemporalKind.dated,
            title: 'Activité de Kassim',
            subjectEntityId: 'person-child',
            subjectLabel: 'Kassim',
            dateIso: '2026-08-20',
            startTime: '14:00',
            endTime: '15:00',
            confidence: StructuredScheduleConfidence.high,
            state: StructuredScheduleProposalState.accepted,
          ),
        ],
      ),
    );

    expect(result.isSuccess, isTrue);
    expect(events, isEmpty);
    final child = fixture.cloud.current!.model.personById('person-child')!;
    expect(child.customFields['structuredSchedulesV1'], hasLength(1));
  });
}

StructuredScheduleApplicationBatch _batch() =>
    StructuredScheduleApplicationBatch(
      importId: 'import-a',
      accountScopeId: 'account-a',
      proposals: [
        _proposal(
          id: 'activity-a',
          subjectId: 'person-main',
          subjectLabel: 'Sophia',
          target: StructuredScheduleTarget.activitySchedule,
          title: 'Pilates',
          weekdays: const [DateTime.wednesday],
          start: '09:00',
          end: '10:00',
        ),
        _proposal(
          id: 'school-a',
          subjectId: 'person-child',
          subjectLabel: 'Kassim',
          target: StructuredScheduleTarget.schoolSchedule,
          title: 'École',
          weekdays: const [DateTime.monday, DateTime.tuesday],
          start: '08:30',
          end: '11:50',
        ),
        StructuredScheduleProposal(
          proposalId: 'event-a',
          target: StructuredScheduleTarget.event,
          temporalKind: StructuredScheduleTemporalKind.dated,
          title: 'Dentiste',
          subjectEntityId: 'person-main',
          subjectLabel: 'Sophia',
          dateIso: '2026-08-20',
          startTime: '09:00',
          endTime: '10:00',
          place: 'Clinique',
          confidence: StructuredScheduleConfidence.high,
          state: StructuredScheduleProposalState.accepted,
        ),
      ],
    );

StructuredScheduleProposal _proposal({
  required String id,
  required String subjectId,
  required String subjectLabel,
  required StructuredScheduleTarget target,
  required String title,
  required List<int> weekdays,
  required String start,
  required String end,
}) =>
    StructuredScheduleProposal(
      proposalId: id,
      target: target,
      temporalKind: StructuredScheduleTemporalKind.recurringWeekly,
      title: title,
      subjectEntityId: subjectId,
      subjectLabel: subjectLabel,
      weekdays: weekdays,
      startTime: start,
      endTime: end,
      confidence: StructuredScheduleConfidence.high,
      state: StructuredScheduleProposalState.accepted,
    );

UserProfile _profile() => UserProfile(
      humanPersonId: 'person-main',
      firstName: 'Sophia',
      familyStatus: 'Nous sommes une famille avec enfants',
      workStatus: '',
      partnerName: '',
      wantsNotifications: true,
      children: [
        ChildProfile(
          humanPersonId: 'person-child',
          firstName: 'Kassim',
          age: '4',
          birthDate: '',
          gender: '',
          school: '',
          notes: '',
        ),
      ],
    );

const _evidence = HumanEvidence(
  source: HumanInformationSource.explicitUserInput,
  confirmation: HumanConfirmationStatus.confirmed,
);

final class _Fixture {
  const _Fixture(this.editor, this.cloud);

  final HumanModelEditService editor;
  final _Cloud cloud;

  static Future<_Fixture> create() async {
    final model = HumanModel(
      accountScopeId: 'account-a',
      primaryPersonId: 'person-main',
      persons: [
        HumanPerson(
          id: 'person-main',
          accountScopeId: 'account-a',
          displayName: 'Sophia',
          evidence: _evidence,
        ),
        HumanPerson(
          id: 'person-child',
          accountScopeId: 'account-a',
          displayName: 'Kassim',
          evidence: _evidence,
        ),
      ],
    );
    final local = HumanModelLocalRepository.withStore(_MemoryStore());
    await local.saveState(
      HumanModelLocalState(
        model: model,
        knownCloudRevision: 1,
        syncStatus: HumanModelSyncStatus.synced,
        lastMutationId: 'initial',
        migrationStatus: HumanModelMigrationStatus.complete,
      ),
    );
    final cloud = _Cloud(model);
    return _Fixture(
      HumanModelEditService(
        humanModelService: HumanModelService(
          localRepository: local,
          cloudRepository: cloud,
        ),
      ),
      cloud,
    );
  }
}

final class _MemoryStore implements HumanModelKeyValueStore {
  final values = <String, String>{};

  @override
  String? getString(String key) => values[key];

  @override
  Future<bool> setString(String key, String value) async {
    values[key] = value;
    return true;
  }
}

final class _Cloud implements HumanModelCloudRepository {
  _Cloud(HumanModel model)
      : current = RevisionedHumanModel(
          model: model,
          modelRevision: 1,
          lastMutationId: 'initial',
          migrationVersion: 1,
          migrationStatus: HumanModelMigrationStatus.complete,
        );

  RevisionedHumanModel? current;

  @override
  Future<RevisionedHumanModel?> read(String accountScopeId) async => current;

  @override
  Future<HumanModelWriteResult> createIfAbsent({
    required HumanModel model,
    required String mutationId,
    required String creationSource,
  }) async =>
      const HumanModelWriteResult.status(HumanModelWriteStatus.alreadyExists);

  @override
  Future<HumanModelWriteResult> update({
    required HumanModel model,
    required int expectedRevision,
    required String mutationId,
  }) async {
    if (current?.modelRevision != expectedRevision) {
      return const HumanModelWriteResult.status(
        HumanModelWriteStatus.revisionConflict,
      );
    }
    current = RevisionedHumanModel(
      model: model,
      modelRevision: expectedRevision + 1,
      lastMutationId: mutationId,
      migrationVersion: 1,
      migrationStatus: HumanModelMigrationStatus.complete,
    );
    return HumanModelWriteResult.success(current!);
  }
}
