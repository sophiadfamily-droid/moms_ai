import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/services/conversation_context_privacy_filter.dart';

void main() {
  const filter = ConversationContextPrivacyFilter();

  test('always excludes local photo paths recursively', () {
    final result = filter.filterProfile(
      profile: {
        'firstName': 'Sophia',
        'profilePhotoPath': '/local/sophia.jpg',
        'partnerPhotoPath': '/local/partner.jpg',
        'children': [
          {'firstName': 'Lina', 'photoPath': '/local/lina.jpg'},
        ],
      },
      message: 'Parle-moi de mon enfant',
    );

    expect(result.toString(), isNot(contains('/local/')));
    expect(result.toString().toLowerCase(), isNot(contains('photopath')));
  });

  test('excludes health and minor data from unrelated requests', () {
    final result = filter.filterProfile(
      profile: {
        'firstName': 'Sophia',
        'allergies': 'Pénicilline',
        'children': [
          {'firstName': 'Lina', 'school': 'École du Centre'},
        ],
      },
      message: 'Quel temps fait-il ?',
    );

    expect(result['allergies'], isNull);
    expect(result['children'], isNull);
    expect(result['firstName'], 'Sophia');
  });

  test('excludes child planning reasoning from unrelated requests', () {
    final result = filter.filterStructuredProfile(
      profileContext: {
        'family': {
          'childrenCount': 1,
          'childcareInfo': 'Nounou le jeudi',
        },
        'children': [
          {'firstName': 'Lina', 'school': 'École du Centre'},
        ],
        'planningReasoning': [
          {
            'type': 'blocked_period',
            'sourceType': 'child_school',
            'label': 'École Lina',
          },
          {
            'type': 'blocked_period',
            'sourceType': 'work',
            'label': 'Travail',
            'source': 'note interne',
          },
        ],
      },
      message: 'Parle-moi de mon travail',
    );

    expect(result.toString(), isNot(contains('Lina')));
    expect(result.toString(), isNot(contains('École')));
    expect(result.toString(), isNot(contains('Nounou')));
    expect(result.toString(), isNot(contains('note interne')));
    expect(result.toString(), contains('Travail'));
  });
}
