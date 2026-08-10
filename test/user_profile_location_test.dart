import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/user_profile.dart';

void main() {
  test('les lieux du profil restent enregistrés', () {
    final profile = UserProfile(
      firstName: 'Sophia',
      familyStatus: 'Je vis seule',
      workStatus: 'Je suis salariée',
      partnerName: '',
      wantsNotifications: true,
      children: const [],
      city: 'Trondheim',
      country: 'Norvège',
      currentCountry: 'Norvège',
      homeAddress: 'Mon domicile',
      workAddress: 'Mon travail',
      importantPlaces: 'École et sport',
    );

    final restored = UserProfile.fromJson(profile.toJson());

    expect(restored.city, 'Trondheim');
    expect(restored.country, 'Norvège');
    expect(restored.currentCountry, 'Norvège');
    expect(restored.homeAddress, 'Mon domicile');
    expect(restored.workAddress, 'Mon travail');
    expect(restored.importantPlaces, 'École et sport');
  });
}
