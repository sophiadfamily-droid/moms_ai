import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/revisioned_domain_models.dart';
import 'package:moms_ai/models/revisioned_sync_protocol.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/services/profile/profile_patch_mutation_adapter.dart';

void main() {
  const adapter = ProfilePatchMutationAdapter();

  test('plans only changed Profile-owned fields through PR.1', () {
    final current = _state(_profile());
    final plan = adapter.plan(
      accountScopeId: 'account-a',
      current: current,
      proposed: current.profile.copyWith(
        planningStyle: 'Souple',
        wantsNotifications: false,
        automaticTravelCalculationEnabled: true,
      ),
    )!;

    expect(plan.changedFields, {
      'planningStyle',
      'wantsNotifications',
      'automaticTravelCalculationEnabled',
    });
    expect(plan.result.expectedRevision, 4);
    expect(plan.result.nextRevision, 5);
    expect(plan.profile.planningStyle, 'Souple');
  });

  test('ignores Human-owned-only changes at the Profile boundary', () {
    final current = _state(_profile());

    expect(
      adapter.plan(
        accountScopeId: 'account-a',
        current: current,
        proposed: current.profile.copyWith(firstName: 'Nouveau prénom'),
      ),
      isNull,
    );
  });

  test('preserves Human-owned fields while applying typed list changes', () {
    final current = _state(_profile());
    final plan = adapter.plan(
      accountScopeId: 'account-a',
      current: current,
      proposed: current.profile.copyWith(
        workDays: const ['lundi', 'mardi'],
        workTimeRanges: [
          TimeRangeModel(startTime: '09:00', endTime: '17:00'),
        ],
      ),
    )!;

    expect(plan.profile.firstName, current.profile.firstName);
    expect(plan.profile.workDays, ['lundi', 'mardi']);
    expect(plan.changedFields, {'workDays', 'workTimeRanges'});
  });
}

UserProfile _profile() => UserProfile(
      humanPersonId: 'person-owner',
      firstName: 'Sophia',
      familyStatus: 'Solo',
      workStatus: 'Active',
      partnerName: '',
      wantsNotifications: true,
      children: const [],
      planningStyle: 'Structuré',
    );

RevisionedProfileState _state(UserProfile profile) => RevisionedProfileState(
      accountScopeId: 'account-a',
      profile: profile,
      revision: 4,
      createdAt: DateTime.utc(2026, 8, 1),
      updatedAt: DateTime.utc(2026, 8, 2),
      lastMutationId: 'mutation-4',
      syncStatus: RevisionedSyncStatus.synced,
    );
