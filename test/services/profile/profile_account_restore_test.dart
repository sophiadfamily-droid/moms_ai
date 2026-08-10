import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/services/storage_service.dart';

void main() {
  test('reconnecting keeps human details while refreshing profile settings',
      () {
    final local = UserProfile(
      firstName: 'Sophia',
      age: '39',
      birthDate: '01/02/1987',
      familyStatus: 'Je vis en couple',
      partnerName: 'Alex',
      workStatus: 'Ancien travail',
      planningStyle: 'Ancienne organisation',
      wantsNotifications: false,
      children: [
        ChildProfile(
          firstName: 'Camille',
          age: '8',
          birthDate: '',
          gender: '',
          school: '',
          notes: '',
        ),
      ],
    );
    final cloud = UserProfile(
      firstName: '',
      familyStatus: '',
      partnerName: '',
      workStatus: 'Nouveau travail',
      planningStyle: 'Organisation souple',
      wantsNotifications: true,
      children: const [],
    );

    final restored = StorageService.mergeProfileOwnedCloudWithCompatibility(
      cloud: cloud,
      localCompatibility: local,
    );

    expect(restored.firstName, 'Sophia');
    expect(restored.age, '39');
    expect(restored.birthDate, '01/02/1987');
    expect(restored.familyStatus, 'Je vis en couple');
    expect(restored.partnerName, 'Alex');
    expect(restored.children.single.firstName, 'Camille');
    expect(restored.workStatus, 'Nouveau travail');
    expect(restored.planningStyle, 'Organisation souple');
    expect(restored.wantsNotifications, isTrue);
  });

  test('a first connection without a local profile uses the cloud profile', () {
    final cloud = UserProfile(
      firstName: '',
      familyStatus: '',
      partnerName: '',
      workStatus: 'Temps plein',
      wantsNotifications: true,
      children: const [],
    );

    final restored = StorageService.mergeProfileOwnedCloudWithCompatibility(
      cloud: cloud,
      localCompatibility: null,
    );

    expect(identical(restored, cloud), isTrue);
  });
}
