import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/routine_model.dart';

void main() {
  final now = DateTime.utc(2026, 7, 27, 10);

  RoutineProposal proposal({
    RoutineProposalState state = RoutineProposalState.awaitingConfirmation,
  }) =>
      RoutineProposal(
        proposalId: 'proposal-a',
        logicalRequestId: 'request-a',
        accountScopeId: 'account-a',
        state: state,
        title: 'Sport',
        recurrenceType: RoutineRecurrenceType.weekly,
        days: const [DateTime.tuesday],
        startTime: '09:00',
        durationMinutes: 60,
        travelGoMinutes: 10,
        travelBackMinutes: 20,
        marginMinutes: 5,
        createdAt: now,
        updatedAt: now,
        expiresAt: now.add(const Duration(days: 30)),
      );

  test('durable proposal serialization is closed and contains no raw text', () {
    final encoded = proposal().toJson();
    expect(RoutineProposal.fromJson(encoded).toJson(), encoded);
    expect(encoded, isNot(contains('text')));
    expect(encoded, isNot(contains('userMessage')));
    expect(encoded['travelGoMinutes'], 10);
    expect(encoded['travelBackMinutes'], 20);
    expect(encoded['marginMinutes'], 5);
  });

  test('unknown durable proposal state fails closed', () {
    final invalid = proposal().toJson()..['state'] = 'unknown';
    expect(
      () => RoutineProposal.fromJson(invalid),
      throwsA(isA<FormatException>()),
    );
  });

  test('calendar-impossible ISO anchor fails closed in the Dart model', () {
    final invalid = proposal().toJson()
      ..['recurrenceType'] = RoutineRecurrenceType.biweekly.name
      ..['anchorDateIso'] = '2026-02-31';
    expect(
      () => RoutineProposal.fromJson(invalid),
      throwsA(isA<FormatException>()),
    );
  });

  test('expiration is closed immediately at the boundary', () {
    final value = proposal();
    expect(
      value.isExpiredAt(
          value.expiresAt.subtract(const Duration(microseconds: 1))),
      isFalse,
    );
    expect(value.isExpiredAt(value.expiresAt), isTrue);
    expect(
      value.isExpiredAt(value.expiresAt.add(const Duration(microseconds: 1))),
      isTrue,
    );
  });

  test('canonical retry comparison rejects every changed business field', () {
    final base = RoutineModel(
      id: 'routine-a',
      accountScopeId: 'account-a',
      logicalRequestId: 'request-a',
      title: 'Activité',
      humanPersonId: 'person-a',
      recurrenceType: RoutineRecurrenceType.weekly,
      days: const [DateTime.tuesday],
      startTime: '09:00',
      durationMinutes: 60,
      travelGoMinutes: 10,
      travelBackMinutes: 20,
      marginMinutes: 5,
      locationEntityId: 'place-a',
      createdAt: now,
      updatedAt: now,
    );
    RoutineModel variant({
      String? id,
      String? accountScopeId,
      String? logicalRequestId,
      String? title,
      String? humanPersonId,
      RoutineRecurrenceType? recurrenceType,
      List<int>? days,
      String? startTime,
      int? durationMinutes,
      int? travelGoMinutes,
      int? travelBackMinutes,
      int? marginMinutes,
      String? locationEntityId,
      RoutineStatus? status,
    }) =>
        RoutineModel(
          id: id ?? base.id,
          accountScopeId: accountScopeId ?? base.accountScopeId,
          logicalRequestId: logicalRequestId ?? base.logicalRequestId,
          title: title ?? base.title,
          humanPersonId: humanPersonId ?? base.humanPersonId,
          recurrenceType: recurrenceType ?? base.recurrenceType,
          days: days ?? base.days,
          startTime: startTime ?? base.startTime,
          durationMinutes: durationMinutes ?? base.durationMinutes,
          travelGoMinutes: travelGoMinutes ?? base.travelGoMinutes,
          travelBackMinutes: travelBackMinutes ?? base.travelBackMinutes,
          marginMinutes: marginMinutes ?? base.marginMinutes,
          locationEntityId: locationEntityId ?? base.locationEntityId,
          status: status ?? base.status,
          createdAt: now,
          updatedAt: now,
        );

    final variants = <String, RoutineModel>{
      'id/proposalId': variant(id: 'routine-b'),
      'accountScopeId': variant(accountScopeId: 'account-b'),
      'logicalRequestId': variant(logicalRequestId: 'request-b'),
      'title': variant(title: 'Autre activité'),
      'humanPersonId': variant(humanPersonId: 'person-b'),
      'recurrence': variant(
        recurrenceType: RoutineRecurrenceType.weekdays,
        days: const [],
      ),
      'days': variant(days: const [DateTime.wednesday]),
      'startTime': variant(startTime: '10:00'),
      'durationMinutes': variant(durationMinutes: 61),
      'travelGoMinutes': variant(travelGoMinutes: 11),
      'travelBackMinutes': variant(travelBackMinutes: 21),
      'marginMinutes': variant(marginMinutes: 6),
      'locationEntityId': variant(locationEntityId: 'place-b'),
      'status': variant(status: RoutineStatus.cancelled),
    };
    for (final entry in variants.entries) {
      expect(
        base.hasSameCanonicalPayload(entry.value),
        isFalse,
        reason: entry.key,
      );
    }
    expect(base.hasSameCanonicalPayload(variant()), isTrue);
  });

  test('canonical comparison includes anchor, monthly occurrence and schema',
      () {
    RoutineModel biweekly(String anchor) => RoutineModel(
          id: 'routine-biweekly',
          accountScopeId: 'account-a',
          logicalRequestId: 'request-biweekly',
          title: 'Activité',
          recurrenceType: RoutineRecurrenceType.biweekly,
          days: const [DateTime.tuesday],
          startTime: '09:00',
          durationMinutes: 60,
          anchorDateIso: anchor,
          travelGoMinutes: 0,
          travelBackMinutes: 0,
          marginMinutes: 0,
          createdAt: now,
          updatedAt: now,
        );
    expect(
      biweekly('2026-07-27').hasSameCanonicalPayload(
        biweekly('2026-08-03'),
      ),
      isFalse,
    );
    RoutineModel monthly(int occurrence) => RoutineModel(
          id: 'routine-monthly',
          accountScopeId: 'account-a',
          logicalRequestId: 'request-monthly',
          title: 'Activité',
          recurrenceType: RoutineRecurrenceType.monthlyNthWeekday,
          days: const [DateTime.tuesday],
          startTime: '09:00',
          durationMinutes: 60,
          weekOfMonth: occurrence,
          travelGoMinutes: 0,
          travelBackMinutes: 0,
          marginMinutes: 0,
          createdAt: now,
          updatedAt: now,
        );
    expect(
      monthly(2).hasSameCanonicalPayload(monthly(-1)),
      isFalse,
    );
    final serialized = biweekly('2026-07-27').toJson();
    expect(
      () => RoutineModel.fromJson({...serialized, 'schemaVersion': 2}),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => RoutineModel.fromJson({...serialized, 'proposalId': 'other'}),
      throwsA(isA<FormatException>()),
    );
  });

  test('committed proposal produces the same canonical blocked period', () {
    final routine = proposal(
      state: RoutineProposalState.committed,
    ).toRoutine(now.add(const Duration(minutes: 1)));
    expect(routine.id, 'proposal-a');
    expect(routine.toBlockedPeriod(), {
      'type': 'blocked_period',
      'recurrenceType': 'weekly',
      'days': [DateTime.tuesday],
      'start': '09:00',
      'end': '10:00',
      'travelGoMinutes': 10,
      'travelBackMinutes': 20,
      'marginMinutes': 5,
    });
  });

  test('Firestore rules give Routine collections explicit owner boundaries',
      () {
    final rules = File('firestore.rules').readAsStringSync();
    expect(rules, contains('match /routines/{routineId}'));
    expect(rules, contains('match /routineProposals/{proposalId}'));
    expect(
      rules,
      contains('match /routineOccurrenceOverrides/{overrideId}'),
    );
    expect(rules, contains('data.accountScopeId == userId'));
    expect(rules, contains('allow read: if isOwner(userId);'));
    expect(
      rules,
      contains(
        "request.resource.data.state in [\n"
        "            'collecting', 'awaitingConfirmation'\n"
        '          ]',
      ),
    );
    expect(rules, isNot(contains("collection != 'routines'")));
    expect(
      rules,
      contains(
        'match /{document=**} {\n'
        '        allow read, write: if false;',
      ),
    );
    expect(rules, contains('allow delete: if false;'));
    expect(rules, isNot(contains('allow read: if isSignedIn();')));
  });
}
