import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('obsolete unscoped application storage cannot return', () {
    expect(File('lib/services/app_data_service.dart').existsSync(), isFalse);

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      expect(source, isNot(contains('AppDataService')), reason: entity.path);
      expect(
        source,
        isNot(contains("import 'services/app_data_service.dart'")),
        reason: entity.path,
      );
    }
  });

  test('account changes rebuild visible state and invalidate session state',
      () {
    final app = File('lib/main.dart').readAsStringSync();
    final navigation =
        File('lib/screens/main_navigation.dart').readAsStringSync();
    final conversation = File(
      'lib/services/conversation_session_controller.dart',
    ).readAsStringSync();

    expect(app, contains('AuthService.authStateChanges.listen'));
    expect(app, contains('EventService.handleAccountScopeChanged(nextScope)'));
    expect(app, contains('_reloadForAccountChange'));
    expect(app, contains("ValueKey('main-navigation:"));
    expect(app, contains('accountScopeId: _activeAccountScopeId'));
    expect(navigation, contains('_conversationSessionController?.dispose()'));
    expect(conversation, contains('void changeAccount(UserProfile profile)'));
    expect(conversation, contains('messages: const []'));
  });

  test('signing in never copies the previously visible profile', () {
    final auth = File('lib/screens/auth/auth_screen.dart').readAsStringSync();
    final profile = File('lib/screens/profile_screen.dart').readAsStringSync();

    expect(auth, isNot(contains('onAuthenticated')));
    expect(profile, contains('child: const AuthScreen()'));
    expect(
      profile,
      isNot(contains('onAuthenticated: () async')),
    );
  });

  test('the account sheet closes before signing out', () {
    final profile = File('lib/screens/profile_screen.dart').readAsStringSync();
    final closeSheet = profile.indexOf('Navigator.of(sheetContext).pop();');
    final signOut = profile.indexOf(
      'await AuthService.signOut();',
      closeSheet,
    );

    expect(closeSheet, greaterThanOrEqualTo(0));
    expect(signOut, greaterThan(closeSheet));
  });

  test('private compatibility caches use account-scoped keys', () {
    final profile =
        File('lib/services/storage_service.dart').readAsStringSync();
    final events = File('lib/services/event_service.dart').readAsStringSync();
    final journal =
        File('lib/services/event_sync_journal.dart').readAsStringSync();
    final dashboard = File('lib/screens/home_screen.dart').readAsStringSync();

    expect(profile, contains('_scopedCompatibilityKey(scope!)'));
    expect(events, contains('guestEventsKey'));
    expect(events, contains('localEventsKeyForAccountScope'));
    expect(events, isNot(contains('scope == null ? eventsKey')));
    expect(journal, contains("scope ?? guestScopeKey"));
    expect(journal, contains('event_sync_account_scope_mismatch'));
    expect(dashboard, contains(r"'$familyPhotosKey:"));
  });

  test('authenticated Task and Shopping never read the guest cache', () {
    final tasks = File('lib/services/task_service.dart').readAsStringSync();
    final shopping =
        File('lib/services/shopping_service.dart').readAsStringSync();

    expect(
      tasks,
      contains('scope == null ? prefs.getStringList(tasksKey) : null'),
    );
    expect(
      shopping,
      contains(
        'scope == null ? shoppingKey : shoppingCacheKeyForAccountScope(scope)',
      ),
    );
    expect(tasks, contains('await _sync.bootstrap(scope)'));
    expect(shopping, contains('await _sync.bootstrap(scope)'));
  });

  test('Firestore has no permissive user-descendant fallback', () {
    final rules = File('firestore.rules').readAsStringSync();
    expect(
      rules,
      isNot(contains(
        "collection != 'identities'",
      )),
    );
    expect(rules, contains('match /conversations/{conversationId}'));
    expect(rules, contains('match /memoryReplacementActions/{actionId}'));
    expect(rules, contains("'contradictionId', 'replacementActionId'"));
    expect(rules, contains("'supersededByMemoryId', 'supersedesMemoryId'"));
    expect(
      rules,
      contains("data.logicalRequestFingerprint.size() == 64"),
    );
    expect(
      rules,
      contains('match /{document=**} {\n        allow read, write: if false;'),
    );
  });
}
