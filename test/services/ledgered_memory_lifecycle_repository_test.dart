import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/action_autonomy_policy.dart';
import 'package:moms_ai/models/action_ledger.dart';
import 'package:moms_ai/models/life_context/life_context_provenance.dart';
import 'package:moms_ai/models/life_context/memory_context.dart';
import 'package:moms_ai/models/memory_lifecycle.dart';
import 'package:moms_ai/models/memory_lifecycle_state.dart';
import 'package:moms_ai/models/memory_policy.dart';
import 'package:moms_ai/services/action_ledger_repository.dart';
import 'package:moms_ai/services/action_ledger_service.dart';
import 'package:moms_ai/services/ledgered_memory_lifecycle_repository.dart';
import 'package:moms_ai/services/memory_lifecycle_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const scope = 'memory-ledger-scope';
  late _FakeLifecycleRepository delegate;
  late ActionLedgerService ledger;
  late LedgeredMemoryLifecycleRepository repository;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    delegate = _FakeLifecycleRepository();
    ledger = ActionLedgerService(
      local: const LocalActionLedgerRepository(),
      currentScope: () => scope,
      now: () => DateTime.utc(2026, 1, 1),
    );
    repository = LedgeredMemoryLifecycleRepository(
      delegate: delegate,
      ledger: ledger,
      loadAutonomyPolicy: () async => ActionAutonomyPolicy(
        mode: ActionAutonomyMode.normal,
        changedAt: DateTime.utc(2026),
        changeSource: ActionAutonomyChangeSource.explicitUserSetting,
        accountScopeId: scope,
      ),
      loadMemoryPolicy: () async => MemoryPolicy(
        accountScopeId: scope,
        generalMode: MemoryGeneralMode.automatic,
        healthMode: MemoryHealthMode.disabled,
        healthConsentGranted: false,
        changedAt: DateTime.utc(2026),
        changeSource: MemoryPolicyChangeSource.explicitUserSetting,
      ),
    );
  });

  test('proposal is authorized and dispatched before its real success',
      () async {
    final mutation = _mutation(
      action: MemoryLifecycleAction.propose,
      previous: null,
      next: MemoryLifecycleState.proposed,
    );
    await repository.createProposal(_proposal(), mutation);

    final entries = (await ledger.history()).entries;
    expect(delegate.createCalls, 1);
    expect(entries, hasLength(1));
    expect(entries.single.mutationId, mutation.record.idempotencyKey);
    expect(entries.single.status, ActionLedgerStatus.notUndoable);
    expect(entries.single.resultRevision, 1);
  });

  test('confirmation activation batch has one logical ledger entry', () async {
    await repository.createProposal(
      _proposal(),
      _mutation(
        action: MemoryLifecycleAction.propose,
        previous: null,
        next: MemoryLifecycleState.proposed,
      ),
    );
    final confirmation = _mutation(
      action: MemoryLifecycleAction.confirm,
      previous: MemoryLifecycleState.proposed,
      next: MemoryLifecycleState.confirmed,
    );
    final activation = _mutation(
      action: MemoryLifecycleAction.activate,
      previous: MemoryLifecycleState.confirmed,
      next: MemoryLifecycleState.active,
    );
    await repository.applyMutations([confirmation, activation]);

    final entries = (await ledger.history()).entries;
    expect(delegate.applyCalls, 1);
    expect(
      entries.where(
        (entry) => entry.mutationId == activation.record.idempotencyKey,
      ),
      hasLength(1),
    );
    expect(entries.first.resultRevision, 2);
  });

  test('duplicate mutation never dispatches twice', () async {
    final mutation = _mutation(
      action: MemoryLifecycleAction.propose,
      previous: null,
      next: MemoryLifecycleState.proposed,
    );
    await repository.createProposal(_proposal(), mutation);
    await repository.createProposal(_proposal(), mutation);
    expect(delegate.createCalls, 1);
    expect((await ledger.history()).entries, hasLength(1));
  });

  test('paused autonomy blocks before ledger and domain dispatch', () async {
    repository = LedgeredMemoryLifecycleRepository(
      delegate: delegate,
      ledger: ledger,
      loadAutonomyPolicy: () async => ActionAutonomyPolicy(
        mode: ActionAutonomyMode.paused,
        changedAt: DateTime.utc(2026),
        changeSource: ActionAutonomyChangeSource.explicitUserSetting,
        accountScopeId: scope,
      ),
      loadMemoryPolicy: () async => MemoryPolicy.restrictiveDefault(
        accountScopeId: scope,
        changedAt: DateTime.utc(2026),
      ),
    );
    await expectLater(
      repository.createProposal(
        _proposal(),
        _mutation(
          action: MemoryLifecycleAction.propose,
          previous: null,
          next: MemoryLifecycleState.proposed,
        ),
      ),
      throwsFormatException,
    );
    expect(delegate.createCalls, 0);
    expect((await ledger.history()).entries, isEmpty);
  });

  test('domain conflict is never recorded as success', () async {
    delegate.conflict = true;
    await expectLater(
      repository.createProposal(
        _proposal(),
        _mutation(
          action: MemoryLifecycleAction.propose,
          previous: null,
          next: MemoryLifecycleState.proposed,
        ),
      ),
      throwsStateError,
    );
    expect((await ledger.history()).entries.single.status,
        ActionLedgerStatus.conflict);
  });

  test('unknown domain result stays reconcilable', () async {
    delegate.unknown = true;
    await expectLater(
      repository.createProposal(
        _proposal(),
        _mutation(
          action: MemoryLifecycleAction.propose,
          previous: null,
          next: MemoryLifecycleState.proposed,
        ),
      ),
      throwsA(isA<Exception>()),
    );
    expect((await ledger.history()).entries.single.outcome,
        ActionOutcome.unknownResult);
  });
}

MemoryProposal _proposal() => MemoryProposal(
      id: 'memory-1',
      text: 'bounded',
      normalizedText: 'bounded',
      semanticType: LifeMemorySemanticType.preference,
      category: 'preference',
      importance: 2,
      sensitivity: LifeContextSensitivity.standard,
      source: 'explicit_user_message',
      proposedAt: DateTime.utc(2026),
      confirmationRequired: true,
    );

MemoryLifecycleMutation _mutation({
  required MemoryLifecycleAction action,
  required MemoryLifecycleState? previous,
  required MemoryLifecycleState next,
}) =>
    MemoryLifecycleMutation(
      memoryId: 'memory-1',
      newState: next,
      record: MemoryLifecycleRecord(
        action: action,
        previousState: previous,
        newState: next,
        occurredAt: DateTime.utc(2026),
        source: 'test',
        actor: MemoryLifecycleActor.user,
        memoryId: 'memory-1',
      ),
    );

final class _FakeLifecycleRepository
    implements MemoryLifecycleRepository, MemoryLifecycleReceiptReader {
  int createCalls = 0;
  int applyCalls = 0;
  int? revision;
  String? lastMutationId;
  MemoryLifecycleState state = MemoryLifecycleState.proposed;
  bool conflict = false;
  bool unknown = false;

  @override
  Future<String?> allocateProposalId() async => 'memory-1';

  @override
  Future<void> createProposal(
    MemoryProposal proposal,
    MemoryLifecycleMutation mutation,
  ) async {
    createCalls++;
    if (conflict) throw StateError('technical_conflict');
    if (unknown) throw Exception('technical_unknown');
    revision = 1;
    lastMutationId = mutation.record.idempotencyKey;
    state = mutation.newState;
  }

  @override
  Future<void> applyMutations(
    List<MemoryLifecycleMutation> mutations,
  ) async {
    applyCalls++;
    revision = revision! + 1;
    lastMutationId = mutations.last.record.idempotencyKey;
    state = mutations.last.newState;
  }

  @override
  Future<List<LifeMemoryFact>> findCandidates(
    MemoryProposal proposal, {
    int limit = 25,
  }) async =>
      const [];

  @override
  Future<LifeMemoryFact?> getById(String memoryId) async => revision == null
      ? null
      : LifeMemoryFact(
          id: memoryId,
          text: 'bounded',
          normalizedText: 'bounded',
          semanticType: LifeMemorySemanticType.preference,
          category: 'preference',
          importance: 2,
          sourceType: LifeContextSourceType.memory,
          confirmationStatus: MemoryConfirmationStatus.unconfirmed,
          sensitivity: LifeContextSensitivity.standard,
          evidenceType: LifeContextEvidenceType.explicit,
          lifecycleState: state,
        );

  @override
  Future<MemoryLifecycleTechnicalReceipt?> readTechnicalReceipt(
    String memoryId,
  ) async =>
      revision == null
          ? null
          : MemoryLifecycleTechnicalReceipt(
              revision: revision!,
              lastMutationId: lastMutationId,
              tombstone: state == MemoryLifecycleState.deleted,
            );
}
