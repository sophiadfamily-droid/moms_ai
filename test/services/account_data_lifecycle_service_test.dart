import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/services/account_data_lifecycle_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('export creates a readable PDF and keeps the complete JSON', () async {
    Map<String, dynamic>? request;
    var authenticated = 0;
    final service = CallableAccountDataLifecycleService.withInvoker(
      (data) async {
        request = data;
        return {
          'operation': 'export',
          'export': {
            'schemaVersion': 1,
            'account': {'id': 'verified-account'},
            'documents': [
              {
                'path': 'tasks/one',
                'data': {'title': 'Valise'},
              },
            ],
          },
        };
      },
      ensureAuthenticatedUid: () async {
        authenticated += 1;
        return 'verified-account';
      },
    );

    final file = await service.prepareExport();

    expect(authenticated, 1);
    expect(request, {'schemaVersion': 1, 'operation': 'export'});
    expect(request!.containsKey('uid'), isFalse);
    expect(file.fileName, startsWith('zelia-mes-informations-'));
    expect(file.fileName, endsWith('.pdf'));
    expect(file.mimeType, 'application/pdf');
    expect(utf8.decode(file.bytes.take(4).toList()), '%PDF');
    expect(file.additionalFiles, hasLength(1));
    final jsonFile = file.additionalFiles.single;
    expect(jsonFile.fileName, startsWith('zelia-donnees-completes-'));
    expect(jsonFile.mimeType, 'application/json');
    final decoded = jsonDecode(utf8.decode(jsonFile.bytes));
    expect(decoded['account']['id'], 'verified-account');
    expect(decoded['documents'], hasLength(1));
  });

  test('malformed export response is rejected', () async {
    final service = CallableAccountDataLifecycleService.withInvoker(
      (_) async => {'operation': 'export', 'export': 'invalid'},
    );

    await expectLater(
      service.prepareExport(),
      throwsA(
        isA<AccountDataLifecycleException>().having(
          (error) => error.code,
          'code',
          'invalid_export_response',
        ),
      ),
    );
  });

  test('local cleanup happens only after a verified server deletion', () async {
    final cleanedScopes = <String>[];
    final requests = <Map<String, dynamic>>[];
    final service = CallableAccountDataLifecycleService.withInvoker(
      (data) async {
        requests.add(data);
        return {'operation': 'delete', 'deleted': true};
      },
      ensureAuthenticatedUid: () async => 'verified-account',
      clearLocalData: (scope) async => cleanedScopes.add(scope),
    );

    await service.deleteAllData();

    expect(requests.single, {
      'schemaVersion': 1,
      'operation': 'delete',
      'confirmation': 'SUPPRIMER',
    });
    expect(requests.single.containsKey('uid'), isFalse);
    expect(cleanedScopes, ['verified-account']);
  });

  test('failed server deletion preserves every local cache', () async {
    final cleanedScopes = <String>[];
    final service = CallableAccountDataLifecycleService.withInvoker(
      (_) async => {'operation': 'delete', 'deleted': false},
      ensureAuthenticatedUid: () async => 'verified-account',
      clearLocalData: (scope) async => cleanedScopes.add(scope),
    );

    await expectLater(
      service.deleteAllData(),
      throwsA(isA<AccountDataLifecycleException>()),
    );
    expect(cleanedScopes, isEmpty);
  });

  test('scoped cleaner preserves guest, global and another account', () async {
    final clearedRuntimeScopes = <String>[];
    SharedPreferences.setMockInitialValues({
      'app_settings_v1:alice': 'alice-settings',
      'human_model_v1:alice:previous': 'alice-backup',
      'zelia_y1_task_journal_v1:alice:backup': 'alice-journal',
      'shopping_items.current.alice': <String>['alice-shopping'],
      'app_settings_v1:bob': 'bob-settings',
      'shopping_items.current.bob': <String>['bob-shopping'],
      'human_model_v1:guest': 'guest-model',
      'shopping_items': <String>['guest-shopping'],
      'onboarding_done': true,
    });

    await AccountScopedLocalDataCleaner(
      clearRuntimeData: (scope) async => clearedRuntimeScopes.add(scope),
    ).clear('alice');

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.containsKey('app_settings_v1:alice'), isFalse);
    expect(preferences.containsKey('human_model_v1:alice:previous'), isFalse);
    expect(
      preferences.containsKey('zelia_y1_task_journal_v1:alice:backup'),
      isFalse,
    );
    expect(
      preferences.containsKey('shopping_items.current.alice'),
      isFalse,
    );
    expect(clearedRuntimeScopes, ['alice']);
    expect(preferences.getString('app_settings_v1:bob'), 'bob-settings');
    expect(
      preferences.getStringList('shopping_items.current.bob'),
      ['bob-shopping'],
    );
    expect(preferences.getString('human_model_v1:guest'), 'guest-model');
    expect(preferences.getStringList('shopping_items'), ['guest-shopping']);
    expect(preferences.getBool('onboarding_done'), isTrue);
  });

  test('scoped cleaner rejects empty and guest account scopes', () async {
    const cleaner = AccountScopedLocalDataCleaner();

    await expectLater(
      cleaner.clear(''),
      throwsA(isA<AccountDataLifecycleException>()),
    );
    await expectLater(
      cleaner.clear('guest'),
      throwsA(isA<AccountDataLifecycleException>()),
    );
  });
}
