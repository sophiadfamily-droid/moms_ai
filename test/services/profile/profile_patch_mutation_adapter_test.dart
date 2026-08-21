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
        mainLifePriority: 'Famille',
        workHours: '08:00-16:00',
      ),
    )!;

    expect(plan.changedFields, {'mainLifePriority'});
    expect(plan.result.expectedRevision, 4);
    expect(plan.result.nextRevision, 5);
    expect(plan.profile.mainLifePriority, 'Famille');
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

  test('ignores Settings-owned-only changes at the Profile boundary', () {
    final current = _state(_profile());

    expect(
      adapter.plan(
        accountScopeId: 'account-a',
        current: current,
        proposed: current.profile.copyWith(
          planningStyle: 'Souple',
          automaticTravelCalculationEnabled: true,
        ),
      ),
      isNull,
    );
  });

  test('ignores schedule-owned changes at the Profile boundary', () {
    final current = _state(_profile());
    expect(
      adapter.plan(
        accountScopeId: 'account-a',
        current: current,
        proposed: current.profile.copyWith(
          workDays: const ['lundi', 'mardi'],
          workTimeRanges: [
            TimeRangeModel(startTime: '09:00', endTime: '17:00'),
          ],
        ),
      ),
      isNull,
    );
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
