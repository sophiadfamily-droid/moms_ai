import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/profile/profile_patch_models.dart';
import 'package:moms_ai/models/revisioned_domain_models.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/services/profile/profile_patch_engine.dart';

void main() {
  const engine = ProfilePatchEngine();

  test('applies typed Profile-owned fields and increments revision', () {
    final result = engine.apply(
      accountScopeId: 'account-a',
      current: _profile(),
      patch: ProfilePatch(
        accountScopeId: 'account-a',
        expectedRevision: 4,
        changes: const {
          ProfileOwnedField.planningStyle: 'Souple',
          ProfileOwnedField.wantsNotifications: false,
          ProfileOwnedField.workDays: ['lundi', 'mardi'],
        },
      ),
    );

    expect(result.nextRevision, 5);
    expect(result.profile.planningStyle, 'Souple');
    expect(result.profile.wantsNotifications, isFalse);
    expect(result.profile.workDays, ['lundi', 'mardi']);
  });

  test('preserves Human-owned identity and family fields exactly', () {
    final current = _profile();
    final result = engine.apply(
      accountScopeId: 'account-a',
      current: current,
      patch: ProfilePatch(
        accountScopeId: 'account-a',
        expectedRevision: 1,
        changes: const {ProfileOwnedField.preferences: 'Matin'},
      ),
    );

    for (final field in ProfileFieldOwnership.humanModelFields) {
      expect(result.profile.toJson()[field], current.toJson()[field]);
    }
  });

  test('fails closed on account mismatch and invalid value type', () {
    final patch = ProfilePatch(
      accountScopeId: 'account-a',
      expectedRevision: 1,
      changes: const {ProfileOwnedField.workStatus: true},
    );
    expect(
      () => engine.apply(
        accountScopeId: 'account-b',
        current: _profile(),
        patch: patch,
      ),
      throwsA(isA<ProfilePatchException>()),
    );
    expect(
      () => engine.apply(
        accountScopeId: 'account-a',
        current: _profile(),
        patch: patch,
      ),
      throwsA(
        isA<ProfilePatchException>().having(
          (error) => error.code,
          'code',
          'invalid_profile_patch_value',
        ),
      ),
    );
  });

  test('closed enum stays aligned with persistence ownership', () {
    expect(
      ProfileOwnedField.values.map((field) => field.name).toSet(),
      ProfileFieldOwnership.profileOwnedFields,
    );
  });
}

UserProfile _profile() => UserProfile(
      humanPersonId: 'person-owner',
      partnerHumanPersonId: 'person-partner',
      firstName: 'Sophia',
      familyStatus: 'Couple',
      workStatus: 'Active',
      partnerName: 'Alex',
      wantsNotifications: true,
      children: const [],
      planningStyle: 'Structuré',
    );
