import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ledger and undo remain outside screens and domain truth', () {
    final chat = File('lib/screens/chat_screen.dart').readAsStringSync();
    expect(chat, isNot(contains('ActionLedgerRepository')));
    expect(chat, isNot(contains('ActionUndoEngine')));
    expect(chat, isNot(contains('ledgerRevision')));
  });

  test('undo engine is pure and contains no replay or infrastructure', () {
    final source =
        File('lib/services/action_undo_engine.dart').readAsStringSync();
    for (final forbidden in [
      'Firebase',
      'SharedPreferences',
      'OpenAI',
      'BuildContext',
      'Widget',
      'Repository',
      'replay(',
    ]) {
      expect(source, isNot(contains(forbidden)));
    }
  });

  test('Routine and Identity automatic undo stay explicitly unsupported', () {
    final model = File('lib/models/action_ledger.dart').readAsStringSync();
    expect(model, contains('identityNotSupported'));
    expect(model, contains('routineNotSupported'));
    expect(model, isNot(contains('deleteIdentity')));
  });

  test('ledger is bounded and physical deletion is denied', () {
    final repository =
        File('lib/services/action_ledger_repository.dart').readAsStringSync();
    final rules = File('firestore.rules').readAsStringSync();
    expect(repository, contains('maxActiveEntries = 100'));
    expect(repository, contains('maxHistoricalEntries = 400'));
    expect(repository, contains('maxPageSize = 50'));
    expect(rules, contains('match /actionLedger/{ledgerEntryId}'));
    expect(rules, contains('allow delete: if false'));
  });

  test('production Memory lifecycle writes use the single ledger decorator',
      () {
    final provider = File('lib/services/conversation_context_service.dart')
        .readAsStringSync();
    final decorator = File(
      'lib/services/ledgered_memory_lifecycle_repository.dart',
    ).readAsStringSync();
    expect(provider, contains('LedgeredMemoryLifecycleRepository('));
    expect(decorator, contains('_ledger.begin('));
    expect(decorator, contains('_ledger.markDispatching('));
    expect(decorator, contains('await dispatch();'));
    expect(
      decorator.indexOf('_ledger.markDispatching('),
      lessThan(decorator.indexOf('await dispatch();')),
    );
    expect(decorator, isNot(contains('print(')));
  });

  test('unsafe Event operations are explicit and never dispatched as undo', () {
    final observer = File('lib/services/event_action_ledger_observer.dart')
        .readAsStringSync();
    final adapter =
        File('lib/services/action_undo_adapters.dart').readAsStringSync();
    expect(observer, contains('undo_event_inverse_unavailable'));
    expect(observer, contains('ActionUndoCapabilityType.unsupportedDomain'));
    expect(adapter, contains('undo_event_strategy_not_supported'));
    expect(
      adapter,
      contains(
        'source.undoCapability.strategy != ActionUndoStrategy.undoCreateEvent',
      ),
    );
    expect(adapter, isNot(contains('deleteIdentity')));
  });
}
