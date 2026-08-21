import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('profile persistence adds stable non-name-derived human record IDs',
      () async {
    SharedPreferences.setMockInitialValues({});
    final profile = UserProfile(
      firstName: 'Alex',
      familyStatus: '',
      workStatus: '',
      partnerName: 'Alex',
      wantsNotifications: true,
      children: [
        ChildProfile(
          firstName: 'Camille',
          age: '',
          birthDate: '',
          gender: '',
          school: '',
          notes: '',
        ),
        ChildProfile(
          firstName: 'Camille',
          age: '',
          birthDate: '',
          gender: '',
          school: '',
          notes: '',
        ),
      ],
    );
    final first = await StorageService.saveUserProfile(profile);
    final second = await StorageService.saveUserProfile(
      first.copyWith(
        firstName: 'Nouveau prénom',
        children: first.children.reversed.toList(),
      ),
    );

    expect(first.humanPersonId, isNotEmpty);
    expect(first.partnerHumanPersonId, isNotEmpty);
    expect(first.children.map((child) => child.humanPersonId).toSet(),
        hasLength(2));
    expect(second.humanPersonId, first.humanPersonId);
    expect(second.partnerHumanPersonId, first.partnerHumanPersonId);
    expect(
      second.children.map((child) => child.humanPersonId).toSet(),
      first.children.map((child) => child.humanPersonId).toSet(),
    );
    expect(second.humanPersonId, isNot('Alex'));
  });

  test('historical profile JSON without human IDs remains readable', () {
    final profile = UserProfile.fromJson({
      'firstName': 'Legacy',
      'familyStatus': '',
      'workStatus': '',
      'partnerName': '',
      'wantsNotifications': true,
      'historicalTopLevel': {'retained': true},
      'children': [
        {
          'firstName': 'Enfant',
          'historicalChildField': 'retained',
        },
      ],
    });
    expect(profile.humanPersonId, isEmpty);
    expect(profile.partnerHumanPersonId, isEmpty);
    expect(profile.toJson()['historicalTopLevel'], {'retained': true});
    expect(
      (profile.toJson()['children'] as List).single['historicalChildField'],
      'retained',
    );
  });

  test('preparing compatibility identifiers does not persist a profile',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prepared = StorageService.prepareCompatibilityProfile(
      UserProfile(
        firstName: 'Profil préparé',
        familyStatus: '',
        workStatus: '',
        partnerName: '',
        wantsNotifications: true,
        children: const [],
      ),
    );

    expect(prepared.humanPersonId, isNotEmpty);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(StorageService.userProfileKey), isNull);
  });
}
