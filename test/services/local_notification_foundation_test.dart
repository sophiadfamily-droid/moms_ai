import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/local_notification_models.dart';
import 'package:moms_ai/screens/notification_settings_screen.dart';
import 'package:moms_ai/services/local_notification_registry.dart';
import 'package:moms_ai/services/local_notification_scheduler.dart';
import 'package:moms_ai/services/notification_interaction_coordinator.dart';
import 'package:moms_ai/services/notification_permission_service.dart';
import 'package:moms_ai/services/notification_privacy_sanitizer.dart';
import 'package:moms_ai/services/notification_service.dart';
import 'package:moms_ai/services/notification_settings_controller.dart';
import 'package:moms_ai/services/notification_settings_service.dart';
import 'package:timezone/data/latest.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();

  group('N.1 permission and settings', () {
    test('reading never requests and explicit request is enforced', () async {
      final gateway = _PermissionGateway(false);
      final service = NotificationPermissionService(gateway);
      expect((await service.readCurrent()).state,
          NotificationPermissionStatus.notDetermined);
      expect(gateway.requests, 0);
      expect(
        () => service.requestAfterExplicitExplanation(
          userInitiated: false,
          explanationShown: true,
        ),
        throwsFormatException,
      );
      await service.requestAfterExplicitExplanation(
        userInitiated: true,
        explanationShown: true,
      );
      expect(gateway.requests, 1);
    });

    test('restrictive defaults, account isolation and revisioned saves',
        () async {
      final repository = _SettingsRepository();
      var scope = 'account-a';
      final service = NotificationSettingsService(
        repository: repository,
        currentAccountScopeId: () => scope,
        currentTimezoneId: () async => 'Europe/Paris',
        now: () => DateTime.utc(2026, 7, 24),
      );
      final initial = await service.load();
      expect(initial.enabled, isFalse);
      expect(initial.privacyMode, NotificationPrivacyMode.genericOnly);
      expect(initial.policyRevision, 0);
      final saved = await service.save(
        enabled: true,
        permissionPromptExplained: true,
        soundEnabled: true,
        vibrationEnabled: false,
        badgeEnabled: false,
      );
      expect(saved.policyRevision, 1);
      scope = 'account-b';
      expect((await service.load()).enabled, isFalse);
    });

    test(
        'future versions, unknown fields and unsupported critical category fail',
        () {
      final request = _request();
      final future = request.toJson()..['schemaVersion'] = 2;
      final unknown = request.toJson()..['personalTitle'] = 'secret';
      expect(
        () => LocalNotificationRequest.fromJson(
          future,
          expectedAccountScopeId: 'account-a',
        ),
        throwsFormatException,
      );
      expect(
        () => LocalNotificationRequest.fromJson(
          unknown,
          expectedAccountScopeId: 'account-a',
        ),
        throwsFormatException,
      );
      _request(category: LocalNotificationCategory.dailySummary).validate();
      expect(
        () => _request(category: LocalNotificationCategory.criticalAlert)
            .validate(),
        throwsFormatException,
      );
    });
  });

  group('N.1 privacy and registry', () {
    test('system content and payload remain generic and minimal', () {
      final request = _request();
      final content = const NotificationPrivacySanitizer().sanitize(
        request: request,
        privacyMode: NotificationPrivacyMode.genericOnly,
        interactionToken: 'opaque-token',
      );
      expect(content.title, 'Zélia');
      expect(content.body, contains('information'));
      expect(content.payload, isNot(contains('account-a')));
      expect(content.payload, isNot(contains('Task')));
      expect(content.payload, isNot(contains('Event')));
      final payload = jsonDecode(content.payload) as Map<String, dynamic>;
      expect(
        payload.keys.toSet(),
        {
          'schemaVersion',
          'notificationId',
          'destinationType',
          'interactionToken',
        },
      );
    });

    test('registry is bounded and rejects platform id collisions', () {
      expect(
        () => NotificationRegistryState(
          accountScopeId: 'account-a',
          entries: List.generate(
            NotificationRegistryState.maximumEntries + 1,
            (index) => _request(
              id: 'notification-$index',
              platformId: index + 1,
            ),
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => NotificationRegistryState(
          accountScopeId: 'account-a',
          entries: [
            _request(id: 'one', platformId: 8),
            _request(id: 'two', platformId: 8),
          ],
        ),
        throwsFormatException,
      );
    });

    test('platform ids are deterministic and positive', () {
      expect(NotificationService.platformId('same'),
          NotificationService.platformId('same'));
      expect(NotificationService.platformId('same'), greaterThan(0));
    });
  });

  group('N.1 scheduler', () {
    late _Registry registry;
    late _PlatformGateway platform;
    late _PermissionGateway permissions;
    late _SettingsRepository settingsRepository;
    late LocalNotificationScheduler scheduler;

    setUp(() async {
      registry = _Registry();
      platform = _PlatformGateway();
      permissions = _PermissionGateway(true);
      settingsRepository = _SettingsRepository();
      final settings = NotificationSettingsService(
        repository: settingsRepository,
        currentAccountScopeId: () => 'account-a',
        currentTimezoneId: () async => 'Europe/Paris',
        now: () => DateTime.utc(2026, 7, 24, 10),
      );
      await settings.save(
        enabled: true,
        permissionPromptExplained: true,
        soundEnabled: false,
        vibrationEnabled: false,
        badgeEnabled: false,
      );
      scheduler = LocalNotificationScheduler(
        platform: platform,
        permissionService: NotificationPermissionService(permissions),
        settingsService: settings,
        registry: registry,
        currentAccountScopeId: () => 'account-a',
        now: () => DateTime.utc(2026, 7, 24, 10),
      );
    });

    test('schedule is idempotent and records only platform-confirmed success',
        () async {
      final request = _request();
      expect((await scheduler.schedule(request)).type,
          NotificationScheduleResultType.scheduled);
      expect(platform.schedules, 1);
      expect((await scheduler.schedule(request)).type,
          NotificationScheduleResultType.idempotent);
      expect(platform.schedules, 1);
      expect((await scheduler.listPending()), hasLength(1));
    });

    test('failure is honest and cancellation is idempotent', () async {
      platform.fail = true;
      expect((await scheduler.schedule(_request())).type,
          NotificationScheduleResultType.platformFailure);
      expect((await scheduler.listPending()), isEmpty);
      platform.fail = false;
      expect((await scheduler.cancel('missing')).type,
          NotificationScheduleResultType.idempotent);
    });

    test('replacement and reschedule leave one platform notification',
        () async {
      await scheduler.schedule(_request(replacementKey: 'reminder'));
      final replacement = _request(
        id: 'notification-2',
        platformId: 43,
        replacementKey: 'reminder',
      );
      expect((await scheduler.schedule(replacement)).type,
          NotificationScheduleResultType.replaced);
      expect(platform.cancelled, contains(42));
      final moved = _request(
        id: 'notification-2',
        platformId: 43,
        replacementKey: 'reminder',
        scheduledAt: DateTime.utc(2026, 7, 24, 13),
      );
      expect((await scheduler.reschedule(moved)).type,
          NotificationScheduleResultType.replaced);
      expect(await scheduler.listPending(), hasLength(1));
    });

    test('disabled, missing permission, past and expiration are explicit',
        () async {
      permissions.enabled = false;
      expect((await scheduler.schedule(_request())).type,
          NotificationScheduleResultType.permissionRequired);
      permissions.enabled = true;
      platform.channelEnabled = false;
      expect((await scheduler.schedule(_request())).type,
          NotificationScheduleResultType.channelDisabled);
      platform.channelEnabled = true;
      expect(
        (await scheduler.schedule(
          _request(scheduledAt: DateTime.utc(2026, 7, 24, 9)),
        ))
            .type,
        NotificationScheduleResultType.invalidTime,
      );
      expect(
        (await scheduler.schedule(
          _request(
            createdAt: DateTime.utc(2026, 7, 24, 8),
            scheduledAt: DateTime.utc(2026, 7, 24, 8, 30),
            expiresAt: DateTime.utc(2026, 7, 24, 9),
          ),
        ))
            .type,
        NotificationScheduleResultType.expired,
      );
    });

    test('reconciliation expires entries and never dispatches an action',
        () async {
      await scheduler.schedule(_request());
      platform.pending.clear();
      await scheduler.reconcileWithPlatform();
      expect((await scheduler.listPending()), isEmpty);
      expect(platform.schedules, 1);
    });
  });

  group('N.1 timezone and interaction', () {
    test('absolute time is stable and nonexistent DST time is rejected', () {
      const resolver = NotificationTimeResolver();
      final absolute = _request(
        scheduledAt: DateTime.utc(2026, 10, 25, 1, 30),
      );
      expect(resolver.resolve(absolute), DateTime.utc(2026, 10, 25, 1, 30));
      final nonexistent = _request(
        scheduledAt: DateTime.utc(2026, 3, 29, 2, 30),
        meaning: NotificationScheduleMeaning.localWallClock,
      );
      expect(() => resolver.resolve(nonexistent), throwsFormatException);
      final ambiguous = _request(
        scheduledAt: DateTime.utc(2026, 10, 25, 2, 30),
        meaning: NotificationScheduleMeaning.localWallClock,
      );
      expect(resolver.resolve(ambiguous), resolver.resolve(ambiguous));
    });

    test('tap resolves navigation only for current account and live token',
        () async {
      final registry = _Registry();
      final request = _request(status: LocalNotificationStatus.scheduled);
      await registry.save(
        NotificationRegistryState(
          accountScopeId: 'account-a',
          entries: [request],
        ),
      );
      var scope = 'account-a';
      final coordinator = NotificationInteractionCoordinator(
        registry: registry,
        currentAccountScopeId: () => scope,
        now: () => DateTime.utc(2026, 7, 24, 10),
      );
      final payload = const NotificationPrivacySanitizer()
          .sanitize(
            request: request,
            privacyMode: NotificationPrivacyMode.genericOnly,
            interactionToken: request.correlationId,
          )
          .payload;
      expect((await coordinator.resolve(payload)).type,
          NotificationNavigationIntentType.home);
      scope = 'account-b';
      expect((await coordinator.resolve(payload)).type,
          NotificationNavigationIntentType.neutral);
    });
  });

  group('N.1 interface and architecture', () {
    testWidgets('settings UI is responsive at phone, tablet and text 1.6',
        (tester) async {
      for (final size in const [Size(360, 700), Size(820, 1100)]) {
        await tester.binding.setSurfaceSize(size);
        final controller = await _controller();
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: NotificationSettingsScreen(controller: controller),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Notifications'), findsOneWidget);
        expect(find.textContaining('restent discrètes'), findsOneWidget);
        expect(find.textContaining('ouvre seulement'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.binding.setSurfaceSize(null);
    });

    test(
        'native and Dart architecture prohibit automatic permission and actions',
        () {
      final main = File('lib/main.dart').readAsStringSync();
      final appDelegate =
          File('ios/Runner/AppDelegate.swift').readAsStringSync();
      final activity = File(
              'android/app/src/main/kotlin/com/sophiadfamily/zeliaaiapp/MainActivity.kt')
          .readAsStringSync();
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      final chat = File('lib/screens/chat_screen.dart').readAsStringSync();
      final screen = File('lib/screens/notification_settings_screen.dart')
          .readAsStringSync();
      expect(main, isNot(contains('requestAfterExplicitExplanation')));
      expect(appDelegate, isNot(contains('requestAuthorization')));
      expect(activity, isNot(contains('requestPermissions')));
      expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
      expect(manifest, isNot(contains('SCHEDULE_EXACT_ALARM')));
      expect(manifest, isNot(contains('ActionBroadcastReceiver')));
      expect(chat, isNot(contains('NotificationService')));
      expect(screen, isNot(contains('FlutterLocalNotificationsPlugin')));
      expect(screen, isNot(contains('SharedPreferences')));
    });
  });
}

LocalNotificationRequest _request({
  String id = 'notification-1',
  int platformId = 42,
  String? replacementKey,
  DateTime? createdAt,
  DateTime? scheduledAt,
  DateTime? expiresAt,
  NotificationScheduleMeaning meaning =
      NotificationScheduleMeaning.absoluteInstant,
  LocalNotificationCategory category = LocalNotificationCategory.test,
  LocalNotificationStatus status = LocalNotificationStatus.registered,
}) =>
    LocalNotificationRequest(
      logicalNotificationId: id,
      accountScopeId: 'account-a',
      category: category,
      createdAt: createdAt ?? DateTime.utc(2026, 7, 24, 10),
      scheduledAt: scheduledAt ?? DateTime.utc(2026, 7, 24, 12),
      expiresAt: expiresAt,
      timezoneId: 'Europe/Paris',
      scheduleMeaning: meaning,
      privacyLevel: NotificationPrivacyLevel.generic,
      interactionType: NotificationInteractionType.openOnly,
      destinationType: NotificationDestinationType.home,
      destinationReference: 'home',
      replacementKey: replacementKey,
      source: LocalNotificationSource.explicitTest,
      status: status,
      platformNotificationId: platformId,
      correlationId: 'opaque-token',
      policyVersionObserved: 1,
    );

Future<NotificationSettingsController> _controller() async {
  final permission = _PermissionGateway(true);
  final settings = NotificationSettingsService(
    repository: _SettingsRepository(),
    currentAccountScopeId: () => 'account-a',
    currentTimezoneId: () async => 'Europe/Paris',
    now: () => DateTime.utc(2026, 7, 24),
  );
  return NotificationSettingsController(
    settingsService: settings,
    permissionService: NotificationPermissionService(permission),
    sendTest: () async => const NotificationScheduleResult(
      NotificationScheduleResultType.delivered,
      'notification_test_delivered',
    ),
  );
}

final class _PermissionGateway implements NotificationPermissionGateway {
  _PermissionGateway(this.enabled);
  bool enabled;
  int requests = 0;

  @override
  Future<bool> openSettings() async => true;

  @override
  Future<NotificationPermissionState> read() async => _state();

  @override
  Future<NotificationPermissionState> request() async {
    requests += 1;
    return _state();
  }

  NotificationPermissionState _state() => NotificationPermissionState(
        platform: NotificationPlatform.android,
        state: enabled
            ? NotificationPermissionStatus.authorized
            : NotificationPermissionStatus.notDetermined,
        checkedAt: DateTime.utc(2026, 7, 24),
        canRequest: !enabled,
        canOpenSettings: true,
        notificationsEnabled: enabled,
      );
}

final class _SettingsRepository implements NotificationSettingsRepository {
  final values = <String, NotificationSettings>{};

  @override
  Future<NotificationSettings?> load(String accountScopeId) async =>
      values[accountScopeId];

  @override
  Future<void> save(NotificationSettings settings) async {
    values[settings.accountScopeId] = settings;
  }
}

final class _Registry implements LocalNotificationRegistry {
  final values = <String, NotificationRegistryState>{};

  @override
  Future<NotificationRegistryState> load(String accountScopeId) async =>
      values[accountScopeId] ??
      NotificationRegistryState(
        accountScopeId: accountScopeId,
        entries: const [],
      );

  @override
  Future<void> save(NotificationRegistryState state) async {
    values[state.accountScopeId] = state;
  }
}

final class _PlatformGateway implements LocalNotificationPlatformGateway {
  int schedules = 0;
  bool fail = false;
  final pending = <int>{};
  final cancelled = <int>[];
  bool channelEnabled = true;

  @override
  Future<void> cancel(int platformNotificationId) async {
    cancelled.add(platformNotificationId);
    pending.remove(platformNotificationId);
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<bool?> isChannelEnabled(String channelId) async => channelEnabled;

  @override
  Future<Set<int>> pendingIds() async => pending;

  @override
  Future<void> schedule({
    required LocalNotificationRequest request,
    required DateTime platformInstant,
    required SanitizedNotificationContent content,
    required NotificationSettings settings,
  }) async {
    schedules += 1;
    if (fail) throw StateError('native_failure');
    pending.add(request.platformNotificationId);
  }

  @override
  Future<void> showNow({
    required LocalNotificationRequest request,
    required SanitizedNotificationContent content,
    required NotificationSettings settings,
  }) async {
    if (fail) throw StateError('native_failure');
  }
}
