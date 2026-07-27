import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/routine_model.dart';
import 'package:moms_ai/services/recurrence_date_match_service.dart';
import 'package:moms_ai/services/routine_conversation_service.dart';
import 'package:moms_ai/services/routine_repository.dart';

void main() {
  final now = DateTime.utc(2026, 7, 27, 10);

  group('normalisation horaire interne', () {
    test('canonicalise uniquement les expressions horaires prises en charge',
        () {
      const original =
          'Tous les mardis de neuf heures à dix heures, je vais au sport.';

      expect(
        RoutineTimeExpressionNormalizer.normalizeForAnalysis(original),
        'tous les mardis de 09:00 a 10:00, je vais au sport.',
      );
      expect(original, contains('neuf heures'));
      expect(
        RoutineTimeExpressionNormalizer.normalizeForAnalysis(
          'à neuf heure, neuf heures trente, neuf heures et demie',
        ),
        'a 09:00, 09:30, 09:30',
      );
      expect(
        RoutineTimeExpressionNormalizer.normalizeForAnalysis(
          '9 heures, 9 h, 9h, 09:00, dix heures trente',
        ),
        '09:00, 09:00, 09:00, 09:00, 10:30',
      );
      expect(
        RoutineTimeExpressionNormalizer.normalizeForAnalysis(
          'J’ai vingt-trois pommes.',
        ),
        'j ai vingt trois pommes.',
      );
    });

    test('recognises every French clock hour from zero to twenty-three', () {
      const words = [
        'zéro',
        'un',
        'deux',
        'trois',
        'quatre',
        'cinq',
        'six',
        'sept',
        'huit',
        'neuf',
        'dix',
        'onze',
        'douze',
        'treize',
        'quatorze',
        'quinze',
        'seize',
        'dix-sept',
        'dix-huit',
        'dix-neuf',
        'vingt',
        'vingt et un',
        'vingt-deux',
        'vingt-trois',
      ];

      for (var hour = 0; hour < words.length; hour += 1) {
        expect(
          RoutineTimeExpressionNormalizer.normalizeForAnalysis(
            'à ${words[hour]} heures',
          ),
          'a ${hour.toString().padLeft(2, '0')}:00',
          reason: words[hour],
        );
      }
    });
  });

  test('all supported dictated and typed ranges build the same routine',
      () async {
    const messages = [
      'Tous les mardis de 9 h à 10 h, je vais au sport.',
      'Tous les mardis de neuf heures à 10h je vais au sport.',
      'Tous les mardis de neuf heures à dix heures je vais au sport.',
      'Tous les mardis de 09:00 à 10:00, je vais au sport.',
    ];

    for (var index = 0; index < messages.length; index += 1) {
      final repository = _Repository();
      final service = RoutineConversationService(
        repository: repository,
        currentAccountScopeId: () => 'account-a',
        clock: () => now,
      );
      final visibleMessage = messages[index];

      final proposal = await service.process(
        visibleMessage,
        logicalRequestId: 'range-$index',
      );

      expect(proposal.type, RoutineConversationResultType.confirmation);
      expect(visibleMessage, messages[index]);
      expect(repository.routines, isEmpty);
      final pending = repository.proposals.values.single;
      expect(pending.title, 'sport');
      expect(pending.days, [DateTime.tuesday]);
      expect(pending.startTime, '09:00');
      expect(pending.durationMinutes, 60);

      final created = await service.process(
        'oui',
        logicalRequestId: 'confirmation-$index',
      );
      expect(created.type, RoutineConversationResultType.created);
      expect(repository.routines, hasLength(1));
    }
  });

  test('unknown clock expression clarifies without persistence', () async {
    final repository = _Repository();
    final service = RoutineConversationService(
      repository: repository,
      currentAccountScopeId: () => 'account-a',
      clock: () => now,
    );

    final result = await service.process(
      'Tous les mardis de neuf heures moins le quart à 10h, '
      'je vais au sport.',
      logicalRequestId: 'unknown-time',
    );

    expect(result.type, RoutineConversationResultType.clarification);
    expect(result.message, 'À quelle heure commence cette routine ?');
    expect(service.hasPending, isFalse);
    expect(repository.proposals, isEmpty);
    expect(repository.routines, isEmpty);
  });

  test('complete weekly routine requires confirmation and persists once',
      () async {
    final repository = _Repository();
    final service = RoutineConversationService(
      repository: repository,
      currentAccountScopeId: () => 'account-a',
      clock: () => now,
    );

    final proposal = await service.process(
      'Tous les mardis de 9 h à 10 h, je vais au sport.',
      logicalRequestId: 'request-1',
    );
    expect(proposal.type, RoutineConversationResultType.confirmation);
    expect(repository.routines, isEmpty);

    final created = await service.process(
      'oui',
      logicalRequestId: 'request-1',
    );
    expect(created.type, RoutineConversationResultType.created);
    expect(repository.routines, hasLength(1));
    final routine = repository.routines.single;
    expect(routine.days, [DateTime.tuesday]);
    expect(routine.startTime, '09:00');
    expect(routine.durationMinutes, 60);
    expect(
      RecurrenceDateMatchService.appliesToDate(
        routine.toBlockedPeriod(),
        DateTime.utc(2026, 7, 28),
      ),
      isTrue,
    );
    expect(
      RecurrenceDateMatchService.appliesToDate(
        routine.toBlockedPeriod(),
        DateTime.utc(2026, 7, 29),
      ),
      isFalse,
    );
  });

  test('negative and ambiguous answers never persist', () async {
    for (final answer in ['non', 'peut-être']) {
      final repository = _Repository();
      final service = RoutineConversationService(
        repository: repository,
        currentAccountScopeId: () => 'account-a',
        clock: () => now,
      );
      await service.process(
        'Tous les mardis de 9 h à 10 h, je vais au sport.',
        logicalRequestId: 'request-$answer',
      );
      final result = await service.process(
        answer,
        logicalRequestId: 'request-$answer',
      );
      expect(repository.routines, isEmpty);
      expect(
        result.type,
        answer == 'non'
            ? RoutineConversationResultType.cancelled
            : RoutineConversationResultType.ambiguous,
      );
    }
  });

  test('missing time asks only for time then keeps supplied facts', () async {
    final repository = _Repository();
    final service = RoutineConversationService(
      repository: repository,
      currentAccountScopeId: () => 'account-a',
      clock: () => now,
    );
    final missing = await service.process(
      'Tous les mardis, je vais au sport.',
      logicalRequestId: 'request-2',
    );
    expect(missing.message, contains('heure'));
    final completed = await service.process(
      'de 9 h à 10 h',
      logicalRequestId: 'request-2',
    );
    expect(completed.type, RoutineConversationResultType.confirmation);
    expect(completed.message, contains('sport'));
  });

  test('non explicit evidence is not interpreted as a routine', () async {
    for (final message in [
      'Peut-être que je ferai du sport tous les mardis.',
      'Avant, je travaillais tous les samedis.',
      'Est-ce que je devrais faire du sport tous les mardis ?',
      'Ma sœur fait du sport tous les mardis.',
    ]) {
      final service = RoutineConversationService(
        repository: _Repository(),
        currentAccountScopeId: () => 'account-a',
      );
      expect(
        (await service.process(message, logicalRequestId: 'request')).type,
        RoutineConversationResultType.notRoutine,
        reason: message,
      );
    }
  });

  test('weekdays and monthly recurrence reuse existing vocabulary', () async {
    final weekdays = RoutineModel(
      id: 'weekdays',
      accountScopeId: 'account-a',
      logicalRequestId: 'one',
      title: 'Travail',
      recurrenceType: RoutineRecurrenceType.weekdays,
      days: const [],
      startTime: '08:00',
      durationMinutes: 480,
      travelGoMinutes: 10,
      travelBackMinutes: 20,
      marginMinutes: 5,
      createdAt: now,
      updatedAt: now,
    );
    expect(
      RecurrenceDateMatchService.appliesToDate(
        weekdays.toBlockedPeriod(),
        DateTime.utc(2026, 8, 1),
      ),
      isFalse,
    );
    final monthly = RoutineModel(
      id: 'monthly',
      accountScopeId: 'account-a',
      logicalRequestId: 'two',
      title: 'Réunion',
      recurrenceType: RoutineRecurrenceType.monthlyNthWeekday,
      days: const [DateTime.tuesday],
      startTime: '09:00',
      durationMinutes: 60,
      weekOfMonth: 2,
      travelGoMinutes: 0,
      travelBackMinutes: 0,
      marginMinutes: 0,
      createdAt: now,
      updatedAt: now,
    );
    expect(
      RecurrenceDateMatchService.appliesToDate(
        monthly.toBlockedPeriod(),
        DateTime.utc(2026, 8, 11),
      ),
      isTrue,
    );
  });

  test('awaiting confirmation survives service reconstruction', () async {
    final repository = _Repository();
    final first = RoutineConversationService(
      repository: repository,
      currentAccountScopeId: () => 'account-a',
      clock: () => now,
    );
    await first.process(
      'Tous les mardis de 9 h à 10 h, je vais au sport.',
      logicalRequestId: 'durable-1',
    );

    final restored = RoutineConversationService(
      repository: repository,
      currentAccountScopeId: () => 'account-a',
      clock: () => now.add(const Duration(minutes: 1)),
    );
    expect(await restored.restoreActive(), isTrue);
    final result = await restored.process(
      'oui',
      logicalRequestId: 'confirmation-message',
    );

    expect(result.type, RoutineConversationResultType.created);
    expect(repository.routines, hasLength(1));
    expect(
      repository.proposals.values.single.state,
      RoutineProposalState.committed,
    );
  });

  test('collecting proposal restores already known facts', () async {
    final repository = _Repository();
    await RoutineConversationService(
      repository: repository,
      currentAccountScopeId: () => 'account-a',
      clock: () => now,
    ).process(
      'Tous les mardis, je vais au sport.',
      logicalRequestId: 'durable-2',
    );
    final restored = RoutineConversationService(
      repository: repository,
      currentAccountScopeId: () => 'account-a',
      clock: () => now.add(const Duration(minutes: 1)),
    );

    final result = await restored.process(
      'de 9 h à 10 h',
      logicalRequestId: 'clarification-message',
    );

    expect(result.type, RoutineConversationResultType.confirmation);
    final proposal = repository.proposals.values.single;
    expect(proposal.title, 'sport');
    expect(proposal.days, [DateTime.tuesday]);
    expect(proposal.startTime, '09:00');
  });

  test('retry after committed proposal is idempotent', () async {
    final repository = _Repository();
    final service = RoutineConversationService(
      repository: repository,
      currentAccountScopeId: () => 'account-a',
      clock: () => now,
    );
    const message = 'Tous les mardis de 9 h à 10 h, je vais au sport.';
    await service.process(message, logicalRequestId: 'durable-3');
    await service.process('oui', logicalRequestId: 'confirmation');

    final reconstructed = RoutineConversationService(
      repository: repository,
      currentAccountScopeId: () => 'account-a',
      clock: () => now.add(const Duration(minutes: 2)),
    );
    final retry = await reconstructed.process(
      message,
      logicalRequestId: 'durable-3',
    );

    expect(retry.type, RoutineConversationResultType.created);
    expect(repository.routines, hasLength(1));
    expect(repository.commitCount, 1);
  });

  test('positive retry after commit and reconstruction is idempotent',
      () async {
    final repository = _Repository();
    final service = RoutineConversationService(
      repository: repository,
      currentAccountScopeId: () => 'account-a',
      clock: () => now,
    );
    await service.process(
      'Tous les mardis de 9 h à 10 h, je vais au sport.',
      logicalRequestId: 'durable-network-loss',
    );
    await service.process('oui', logicalRequestId: 'first-confirmation');

    final reconstructed = RoutineConversationService(
      repository: repository,
      currentAccountScopeId: () => 'account-a',
      clock: () => now.add(const Duration(minutes: 2)),
    );
    final retry = await reconstructed.process(
      'oui',
      logicalRequestId: 'retried-confirmation',
    );

    expect(retry.type, RoutineConversationResultType.created);
    expect(repository.routines, hasLength(1));
    expect(repository.commitCount, 1);
  });

  test('decline is durable and ambiguous answer leaves proposal unchanged',
      () async {
    final repository = _Repository();
    final service = RoutineConversationService(
      repository: repository,
      currentAccountScopeId: () => 'account-a',
      clock: () => now,
    );
    const message = 'Tous les mardis de 9 h à 10 h, je vais au sport.';
    await service.process(message, logicalRequestId: 'durable-4');
    await service.process('peut-être', logicalRequestId: 'answer-1');
    expect(
      repository.proposals.values.single.state,
      RoutineProposalState.awaitingConfirmation,
    );
    await service.process('non', logicalRequestId: 'answer-2');
    expect(
      repository.proposals.values.single.state,
      RoutineProposalState.declined,
    );
    expect(repository.routines, isEmpty);
  });

  test('logical request controls proposal identity', () async {
    final repository = _Repository();
    const message = 'Tous les mardis de 9 h à 10 h, je vais au sport.';
    for (final request in ['request-a', 'request-b']) {
      await RoutineConversationService(
        repository: repository,
        currentAccountScopeId: () => 'account-a',
        clock: () => now,
      ).process(message, logicalRequestId: request);
    }
    expect(repository.proposals, hasLength(2));
    expect(
      repository.proposals.values.map((item) => item.proposalId).toSet(),
      hasLength(2),
    );
  });
}

final class _Repository implements RoutineRepository {
  final List<RoutineModel> routines = [];
  final Map<String, RoutineProposal> proposals = {};
  int commitCount = 0;

  @override
  Future<RoutineProposal?> createOrVerifyProposal(
    RoutineProposal proposal,
  ) async {
    final current = proposals[proposal.proposalId];
    if (current != null) {
      return current.logicalRequestId == proposal.logicalRequestId
          ? current
          : null;
    }
    proposals[proposal.proposalId] = proposal;
    return proposal;
  }

  @override
  Future<RoutineProposal?> findActiveProposal(String accountScopeId) async {
    final active = proposals.values
        .where(
          (proposal) =>
              proposal.accountScopeId == accountScopeId &&
              !proposal.isTerminal &&
              proposal.expiresAt.isAfter(DateTime.utc(2026, 7, 27)),
        )
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return active.firstOrNull;
  }

  @override
  Future<RoutineProposal?> findLatestProposal(String accountScopeId) async {
    final values = proposals.values
        .where((proposal) => proposal.accountScopeId == accountScopeId)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return values.firstOrNull;
  }

  @override
  Future<RoutineProposal?> findProposal({
    required String accountScopeId,
    required String proposalId,
  }) async {
    final proposal = proposals[proposalId];
    return proposal?.accountScopeId == accountScopeId ? proposal : null;
  }

  @override
  Future<RoutineProposal?> updateProposal(RoutineProposal proposal) async {
    final current = proposals[proposal.proposalId];
    if (current == null || current.isTerminal) return null;
    proposals[proposal.proposalId] = proposal;
    return proposal;
  }

  @override
  Future<RoutineCommitResult> commitProposal(
    RoutineProposal proposal,
    DateTime committedAt,
  ) async {
    final current = proposals[proposal.proposalId];
    if (current == null) {
      return const RoutineCommitResult(RoutineCommitCode.conflict);
    }
    if (current.state == RoutineProposalState.committed) {
      return RoutineCommitResult(
        RoutineCommitCode.alreadyCommitted,
        routine: routines
            .where((routine) => routine.id == current.proposalId)
            .firstOrNull,
      );
    }
    if (current.state != RoutineProposalState.awaitingConfirmation) {
      return const RoutineCommitResult(RoutineCommitCode.conflict);
    }
    final routine = current.toRoutine(committedAt);
    if (!routines.any((item) => item.id == routine.id)) {
      routines.add(routine);
      commitCount += 1;
    }
    proposals[current.proposalId] = current.copyWith(
      state: RoutineProposalState.committed,
      updatedAt: committedAt,
    );
    return RoutineCommitResult(RoutineCommitCode.committed, routine: routine);
  }

  @override
  Future<RoutineModel?> createOrVerify(RoutineModel routine) async {
    final existing =
        routines.where((item) => item.id == routine.id).firstOrNull;
    if (existing != null) return existing;
    routines.add(routine);
    return routine;
  }

  @override
  Future<List<RoutineModel>> listForAccount(String accountScopeId) async =>
      routines
          .where((routine) => routine.accountScopeId == accountScopeId)
          .toList(growable: false);
}
