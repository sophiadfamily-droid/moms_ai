import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/life_context/life_context_domains.dart';
import 'package:moms_ai/models/life_context/life_context_graph.dart';
import 'package:moms_ai/models/life_context/life_context_projection.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/services/life_context/life_context_projection_compatibility.dart';
import 'package:moms_ai/services/routine/routine_planning_blocker_service.dart';

void main() {
  test('projects profile schedules with their day and protected travel time',
      () async {
    final service = RoutinePlanningBlockerService(
      loadPlanningContext: (_) async => PlanningProjectionContext(
        events: const [],
        routines: const [
          PlanningProjectionRoutine(
            id: 'workSchedule:0',
            routineKind: 'workSchedule',
            days: ['lundi'],
            startTime: '09:00',
            endTime: '10:00',
            travelMinutes: 15,
          ),
        ],
        temporalResponsibilities: const [],
        warningCodes: const [],
      ),
    );

    final monday = await service.load(
      accountScopeId: 'account-a',
      startDay: DateTime(2026, 8, 17),
    );
    final tuesday = await service.load(
      accountScopeId: 'account-a',
      startDay: DateTime(2026, 8, 18),
    );

    expect(monday, hasLength(1));
    expect(monday.single.title, 'Tes horaires de travail');
    expect(monday.single.startDateTimeIso, '2026-08-17T08:45:00.000');
    expect(monday.single.endDateTimeIso, '2026-08-17T10:15:00.000');
    expect(tuesday, isEmpty);
  });

  test('keeps separate travel and margin around a canonical routine', () async {
    final service = RoutinePlanningBlockerService(
      loadPlanningContext: (_) async => PlanningProjectionContext(
        events: const [],
        routines: const [
          PlanningProjectionRoutine(
            id: 'routine-a',
            routineKind: 'routine',
            days: ['1'],
            startTime: '14:00',
            endTime: '15:00',
            travelMinutes: null,
            recurrenceType: 'weekly',
            travelGoMinutes: 10,
            travelBackMinutes: 5,
            marginMinutes: 5,
          ),
        ],
        temporalResponsibilities: const [],
        warningCodes: const [],
      ),
    );

    final blockers = await service.load(
      accountScopeId: 'account-a',
      startDay: DateTime(2026, 8, 17),
    );

    expect(blockers.single.startDateTimeIso, '2026-08-17T13:50:00.000');
    expect(blockers.single.endDateTimeIso, '2026-08-17T15:10:00.000');
  });

  test('uses profile schedules when only the Event projection is unavailable',
      () async {
    final service = RoutinePlanningBlockerService(
      loadPlanningProjection: (_) async => _partialPlanningProjection(),
    );

    final blockers = await service.load(
      accountScopeId: 'account-a',
      startDay: DateTime(2026, 8, 12),
    );

    expect(blockers, hasLength(1));
    expect(blockers.single.title, 'Une de tes activités');
    expect(blockers.single.time, '09:00');
  });

  test('reads the current profile directly with the activity name', () async {
    var profile = _profileWithPilates();
    final service = RoutinePlanningBlockerService.fromProfile(() => profile);

    final blockers = await service.load(
      accountScopeId: 'account-a',
      startDay: DateTime(2026, 8, 12),
    );

    expect(blockers, hasLength(1));
    expect(blockers.single.title, 'Pilates');
    expect(blockers.single.startDateTimeIso, '2026-08-12T09:00:00.000');
    expect(blockers.single.endDateTimeIso, '2026-08-12T10:00:00.000');

    profile = _profileWithPilates(startTime: '11:00', endTime: '12:00');
    final updated = await service.load(
      accountScopeId: 'account-a',
      startDay: DateTime(2026, 8, 12),
    );
    expect(updated.single.startDateTimeIso, '2026-08-12T11:00:00.000');
  });
}

UserProfile _profileWithPilates({
  String startTime = '09:00',
  String endTime = '10:00',
}) =>
    UserProfile(
      firstName: 'Sophia',
      familyStatus: '',
      workStatus: '',
      partnerName: '',
      wantsNotifications: true,
      children: const [],
      personalActivities: [
        ActivityModel(
          title: 'Pilates',
          days: const ['mercredi'],
          timeRanges: [
            TimeRangeModel(startTime: startTime, endTime: endTime),
          ],
        ),
      ],
    );

LifeContextProjection _partialPlanningProjection() => LifeContextProjection(
      projectionId: 'planning-1',
      sourceSnapshotId: 'snapshot-1',
      accountScopeId: 'account-a',
      purpose: LifeContextConsumerPurpose.planning,
      generatedAt: DateTime.utc(2026, 8, 11),
      state: LifeContextProjectionState.partial,
      budgetRequested: 180,
      budgetUsed: 6,
      sections: [
        LifeContextProjectionSection(
          type: LifeContextProjectionSectionType.event,
          availability: LifeContextAvailability.unavailable,
          freshness: LifeContextFreshness.unknown,
          items: const [],
          budgetLimit: 110,
          budgetUsed: 0,
          omittedCount: 0,
          truncated: false,
        ),
        LifeContextProjectionSection(
          type: LifeContextProjectionSectionType.routine,
          availability: LifeContextAvailability.availableStale,
          freshness: LifeContextFreshness.stale,
          items: [
            LifeContextProjectionItem(
              id: 'personalActivity:0:0',
              domain: LifeContextDomain.routine,
              type: 'routine',
              facts: [
                LifeContextProjectionFact(
                  key: LifeContextProjectionFactKeys.routineKind,
                  value: 'personalActivity',
                  sensitivity: LifeContextSensitivityLevel.publicTechnical,
                ),
                LifeContextProjectionFact(
                  key: LifeContextProjectionFactKeys.days,
                  value: 'mercredi',
                  sensitivity: LifeContextSensitivityLevel.publicTechnical,
                ),
                LifeContextProjectionFact(
                  key: LifeContextProjectionFactKeys.startTime,
                  value: '09:00',
                  sensitivity: LifeContextSensitivityLevel.publicTechnical,
                ),
                LifeContextProjectionFact(
                  key: LifeContextProjectionFactKeys.endTime,
                  value: '10:00',
                  sensitivity: LifeContextSensitivityLevel.publicTechnical,
                ),
                LifeContextProjectionFact(
                  key: LifeContextProjectionFactKeys.travelMinutes,
                  value: '0',
                  sensitivity: LifeContextSensitivityLevel.publicTechnical,
                ),
              ],
              confirmation: LifeContextConfirmation.confirmed,
              freshness: LifeContextFreshness.stale,
              provenance: const LifeContextProjectionProvenance(
                sourceDomain: LifeContextDomain.routine,
                sourceId: 'personalActivity:0:0',
                sourceSnapshotId: 'snapshot-1',
                sourceKind: LifeContextSourceKind.legacyProfileRoutine,
              ),
            ),
          ],
          budgetLimit: 35,
          budgetUsed: 6,
          omittedCount: 0,
          truncated: false,
        ),
      ],
      omittedCount: 0,
      warningCodes: const ['event_unavailable', 'routine_stale'],
    );
