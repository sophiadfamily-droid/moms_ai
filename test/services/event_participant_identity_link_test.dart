import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_types.dart';
import 'package:moms_ai/core/identity/persisted_identity_link.dart';
import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/models/event_participant_identity_link.dart';
import 'package:moms_ai/services/event_service.dart';

void main() {
  EventModel event({EventParticipantIdentityLink? link}) => EventModel(
        title: 'Rendez-vous',
        date: '2026-07-23',
        time: '10:00',
        notes: '',
        createdAt: DateTime.utc(2026, 7, 22),
        startDateTimeIso: '2026-07-23T10:00:00.000Z',
        durationMinutes: 45,
        participantIdentity: link,
      );

  final link = EventParticipantIdentityLink(
    identity: PersistedIdentityLink(
      entityId: 'entity-1',
      entityType: EntityType.person,
    ),
    accountScopeId: 'account-a',
  );

  test('legacy events remain readable without an Identity link', () {
    final restored = EventModel.fromJson(event().toJson());
    expect(restored.participantIdentity, isNull);
  });

  test('valid participant links round-trip with only minimal fields', () {
    final map = event(link: link).toJson();
    expect(map['participantIdentity'], {
      'entityId': 'entity-1',
      'entityType': 'person',
      'schemaVersion': 1,
      'role': 'participant',
      'accountScopeId': 'account-a',
    });
    expect(EventModel.fromJson(map).participantIdentity, link);
  });

  test('the typed link rejects invalid scope and non-person identities', () {
    expect(
      () => EventParticipantIdentityLink(
        identity: PersistedIdentityLink(
          entityId: 'entity-1',
          entityType: EntityType.person,
        ),
        accountScopeId: '   ',
      ),
      throwsA(isA<EntityDomainException>()),
    );
    expect(
      () => EventParticipantIdentityLink(
        identity: PersistedIdentityLink(
          entityId: 'entity-1',
          entityType: EntityType.place,
        ),
        accountScopeId: 'account-a',
      ),
      throwsA(isA<EntityDomainException>()),
    );
  });

  test('invalid persisted links are ignored defensively', () {
    for (final invalid in [
      'entity-1',
      <String, Object?>{},
      {
        'entityId': '',
        'entityType': 'person',
        'schemaVersion': 1,
        'role': 'participant',
        'accountScopeId': 'account-a',
      },
      {
        'entityId': 'entity-1',
        'entityType': 'person',
        'schemaVersion': 1,
        'role': 'owner',
        'accountScopeId': 'account-a',
      },
      {
        'entityId': 'entity-1',
        'entityType': 'person',
        'schemaVersion': 1,
        'role': 'participant',
        'accountScopeId': 'account-a',
        'label': 'not allowed',
      },
    ]) {
      expect(
        EventModel.fromJson(
                {...event().toJson(), 'participantIdentity': invalid})
            .participantIdentity,
        isNull,
      );
    }
  });

  test('copyWith and recurring copies preserve the link', () {
    final original = event(link: link);
    expect(original.copyWith(title: 'Autre').participantIdentity, link);
    final occurrences = EventService.buildWeeklyOccurrences(
      baseEvent: original.copyWith(
        isRecurring: true,
        recurringType: 'weekly',
      ),
      count: 2,
    );
    expect(occurrences.every((item) => item.participantIdentity == link), true);
  });

  test('the link does not affect planning time calculations', () {
    final without = event();
    final withLink = event(link: link);
    expect(EventService.parseStart(withLink), EventService.parseStart(without));
    expect(EventService.parseEnd(withLink), EventService.parseEnd(without));
    expect(withLink.totalProtectedMinutes, without.totalProtectedMinutes);
  });
}
