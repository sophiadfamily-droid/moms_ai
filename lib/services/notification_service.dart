import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';

import '../models/local_notification_models.dart';
import 'auth_service.dart';
import 'app_diagnostics.dart';
import 'app_error_classifier.dart';
import 'local_notification_registry.dart';
import 'local_notification_scheduler.dart';
import 'notification_interaction_coordinator.dart';
import 'notification_permission_service.dart';
import 'notification_privacy_sanitizer.dart';
import 'notification_settings_service.dart';
import 'proactive_detection_engine.dart';
import 'proactive_detection_lifecycle.dart';
import 'proactive_detection_production.dart';
import 'proactive_detection_registry.dart';
import 'daily_summary_view_service.dart';
import 'proactive_notification_delivery_registry.dart';
import 'proactive_notification_orchestrator.dart';
import 'proactive_notification_policy_service.dart';
import 'event_service.dart';
import 'task_service.dart';

final class FlutterNotificationPermissionGateway
    implements NotificationPermissionGateway {
  FlutterNotificationPermissionGateway({
    required this.hasRequestedPermission,
    this.now = DateTime.now,
  });

  final Future<bool> Function() hasRequestedPermission;
  final DateTime Function() now;

  @override
  Future<NotificationPermissionState> read() async {
    try {
      final status = await Permission.notification.status;
      return _state(
        status,
        hasRequested: await hasRequestedPermission(),
      );
    } on Object {
      return NotificationPermissionState(
        platform: _platform,
        state: NotificationPermissionStatus.error,
        checkedAt: now().toUtc(),
        canRequest: false,
        canOpenSettings: true,
        notificationsEnabled: false,
        warningCodes: const {NotificationPermissionWarning.checkFailed},
      );
    }
  }

  @override
  Future<NotificationPermissionState> request() async => _state(
        await Permission.notification.request(),
        hasRequested: true,
      );

  @override
  Future<bool> openSettings() => openAppSettings();

  NotificationPermissionState _state(
    PermissionStatus status, {
    required bool hasRequested,
  }) {
    final mapped = switch (status) {
      PermissionStatus.granted => NotificationPermissionStatus.authorized,
      PermissionStatus.denied => hasRequested
          ? NotificationPermissionStatus.denied
          : NotificationPermissionStatus.notDetermined,
      PermissionStatus.restricted => NotificationPermissionStatus.restricted,
      PermissionStatus.limited => NotificationPermissionStatus.provisional,
      PermissionStatus.permanentlyDenied =>
        NotificationPermissionStatus.permanentlyDenied,
      PermissionStatus.provisional => NotificationPermissionStatus.provisional,
    };
    return NotificationPermissionState(
      platform: _platform,
      state: mapped,
      checkedAt: now().toUtc(),
      canRequest: status == PermissionStatus.denied,
      canOpenSettings: status == PermissionStatus.permanentlyDenied ||
          status == PermissionStatus.restricted,
      notificationsEnabled: status == PermissionStatus.granted ||
          status == PermissionStatus.provisional ||
          status == PermissionStatus.limited,
      exactSchedulingCapability:
          _platform == NotificationPlatform.android ? false : null,
    );
  }

  NotificationPlatform get _platform => kIsWeb
      ? NotificationPlatform.unsupported
      : switch (defaultTargetPlatform) {
          TargetPlatform.iOS => NotificationPlatform.ios,
          TargetPlatform.android => NotificationPlatform.android,
          _ => NotificationPlatform.unsupported,
        };
}

final class FlutterLocalNotificationPlatformGateway
    implements LocalNotificationPlatformGateway {
  FlutterLocalNotificationPlatformGateway({
    FlutterLocalNotificationsPlugin? plugin,
    this.onPayload,
  }) : plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin plugin;
  final ValueChanged<String>? onPayload;
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    final timezone = await NotificationService.currentTimezoneId();
    tz.setLocalLocation(tz.getLocation(timezone));
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('zelia_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) onPayload?.call(payload);
      },
    );
    final launch = await plugin.getNotificationAppLaunchDetails();
    final launchPayload = launch?.notificationResponse?.payload;
    if (launch?.didNotificationLaunchApp == true && launchPayload != null) {
      onPayload?.call(launchPayload);
    }
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    for (final channel in _channels) {
      await android?.createNotificationChannel(channel);
    }
    _initialized = true;
  }

  static const _channels = [
    AndroidNotificationChannel(
      'zelia_general_v1',
      'Informations Zélia',
      description: 'Informations locales discrètes de Zélia.',
    ),
    AndroidNotificationChannel(
      'zelia_reminders_v1',
      'Rappels demandés',
      description: 'Rappels locaux explicitement demandés.',
    ),
    AndroidNotificationChannel(
      'zelia_action_attention_v1',
      'Actions à consulter',
      description: 'Actions à consulter dans Zélia.',
    ),
  ];

  @override
  Future<void> schedule({
    required LocalNotificationRequest request,
    required DateTime platformInstant,
    required SanitizedNotificationContent content,
    required NotificationSettings settings,
  }) async {
    await initialize();
    await plugin.zonedSchedule(
      id: request.platformNotificationId,
      title: content.title,
      body: content.body,
      scheduledDate: tz.TZDateTime.from(
        platformInstant,
        tz.getLocation(request.timezoneId),
      ),
      notificationDetails: _details(content, settings),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: content.payload,
    );
  }

  @override
  Future<void> showNow({
    required LocalNotificationRequest request,
    required SanitizedNotificationContent content,
    required NotificationSettings settings,
  }) async {
    await initialize();
    await plugin.show(
      id: request.platformNotificationId,
      title: content.title,
      body: content.body,
      notificationDetails: _details(content, settings),
      payload: content.payload,
    );
  }

  NotificationDetails _details(
    SanitizedNotificationContent content,
    NotificationSettings settings,
  ) =>
      NotificationDetails(
        android: AndroidNotificationDetails(
          content.systemCategory,
          switch (content.systemCategory) {
            'zelia_reminders_v1' => 'Rappels demandés',
            'zelia_action_attention_v1' => 'Actions à consulter',
            _ => 'Informations Zélia',
          },
          visibility: content.visibility == NotificationSystemVisibility.secret
              ? NotificationVisibility.secret
              : NotificationVisibility.private,
          silent: !settings.soundEnabled,
          playSound: settings.soundEnabled,
          enableVibration: settings.vibrationEnabled,
          channelShowBadge: settings.badgeEnabled,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: settings.soundEnabled,
          presentBadge: settings.badgeEnabled,
        ),
      );

  @override
  Future<void> cancel(int platformNotificationId) =>
      plugin.cancel(id: platformNotificationId);

  @override
  Future<Set<int>> pendingIds() async =>
      (await plugin.pendingNotificationRequests())
          .map((item) => item.id)
          .toSet();

  @override
  Future<bool?> isChannelEnabled(String channelId) async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final channels = await android?.getNotificationChannels();
    final matches = channels?.where((channel) => channel.id == channelId);
    if (matches == null || matches.isEmpty) return true;
    return matches.first.importance != Importance.none;
  }
}

class NotificationService {
  static LocalNotificationScheduler? _scheduler;
  static NotificationSettingsService? _settings;
  static NotificationPermissionService? _permissions;
  static NotificationInteractionCoordinator? _interactions;
  static LocalNotificationRegistry? _registry;
  static LocalNotificationPlatformGateway? _platform;
  static ProactiveDetectionLifecycle? _detectionLifecycle;
  static ProactiveDetectionRegistry? _proactiveDetectionRegistry;
  static ProactiveNotificationPolicyService? _proactivePolicy;
  static StreamSubscription<Object?>? _authSubscription;
  static String? _pendingPayload;
  static String? _observedScope;
  static bool _detectionEvaluationRunning = false;
  static DetectionEvaluationTrigger? _queuedDetectionTrigger;

  static Future<void> init() async {
    final preferences = await SharedPreferences.getInstance();
    final registry = SharedPreferencesLocalNotificationRegistry(preferences);
    _registry = registry;
    _settings = NotificationSettingsService(
      repository: SharedPreferencesNotificationSettingsRepository(preferences),
      currentAccountScopeId: () => AuthService.currentUserId,
      currentTimezoneId: currentTimezoneId,
    );
    _permissions = NotificationPermissionService(
      FlutterNotificationPermissionGateway(
        hasRequestedPermission: () async =>
            (await _settings!.load()).permissionPromptExplained,
      ),
    );
    final platform = FlutterLocalNotificationPlatformGateway(
      onPayload: (payload) => _pendingPayload = payload,
    );
    _platform = platform;
    _scheduler = LocalNotificationScheduler(
      platform: platform,
      permissionService: _permissions!,
      settingsService: _settings!,
      registry: registry,
      currentAccountScopeId: () => AuthService.currentUserId,
    );
    _interactions = NotificationInteractionCoordinator(
      registry: registry,
      currentAccountScopeId: () => AuthService.currentUserId,
    );
    final detectionRegistry =
        SharedPreferencesProactiveDetectionRegistry(preferences);
    _proactiveDetectionRegistry = detectionRegistry;
    _proactivePolicy = ProactiveNotificationPolicyService(
      repository:
          SharedPreferencesProactiveNotificationPolicyRepository(preferences),
      currentAccountScopeId: () => AuthService.currentUserId,
      currentTimezoneId: currentTimezoneId,
    );
    final detectionCoordinator = ProactiveNotificationOrchestrator(
      scheduler: _scheduler!,
      signalRegistry: detectionRegistry,
      deliveryRegistry:
          SharedPreferencesProactiveNotificationDeliveryRegistry(preferences),
      policyService: _proactivePolicy!,
      permissionService: _permissions!,
      notificationSettingsService: _settings!,
      currentAccountScopeId: () => AuthService.currentUserId,
    );
    _detectionLifecycle = ProactiveDetectionLifecycle(
      engine: const ProactiveDetectionEngine(),
      inputProvider: ProductionProactiveDetectionInputProvider(
        currentTimezoneId: currentTimezoneId,
      ),
      registry: detectionRegistry,
      notificationCoordinator: detectionCoordinator,
      currentAccountScopeId: () => AuthService.currentUserId,
      timezoneId: () => tz.local.name,
    );
    await _scheduler!.initialize();
    EventService.eventsVersion.removeListener(_eventChanged);
    TaskService.tasksVersion.removeListener(_taskChanged);
    EventService.eventsVersion.addListener(_eventChanged);
    TaskService.tasksVersion.addListener(_taskChanged);
    _observedScope = AuthService.currentUserId;
    await _authSubscription?.cancel();
    _authSubscription = AuthService.authStateChanges.listen((_) async {
      final nextScope = AuthService.currentUserId;
      final previousScope = _observedScope;
      _observedScope = nextScope;
      if (previousScope != null && previousScope != nextScope) {
        try {
          await _invalidateAccount(previousScope);
        } on Object {
          _pendingPayload = null;
        }
      }
      if (nextScope != null && previousScope != nextScope) {
        try {
          await evaluateDetections(
            DetectionEvaluationTrigger.authenticatedBootstrap,
          );
        } on Object {
          // Detection remains optional and fail-closed. No permission prompt
          // or domain mutation is triggered by an unavailable context.
        }
      }
    });
  }

  static Future<void> _invalidateAccount(String accountScopeId) async {
    _pendingPayload = null;
    final registry = _registry;
    final platform = _platform;
    if (registry == null || platform == null) return;
    final state = await registry.load(accountScopeId);
    for (final entry in state.entries) {
      await platform.cancel(entry.platformNotificationId);
    }
    await registry.save(
      NotificationRegistryState(
        accountScopeId: accountScopeId,
        entries: state.entries.map(
            (entry) => entry.withStatus(LocalNotificationStatus.cancelled)),
      ),
    );
  }

  static NotificationSettingsService get settingsService =>
      _settings ?? (throw StateError('notification_service_not_initialized'));
  static NotificationPermissionService get permissionService =>
      _permissions ??
      (throw StateError('notification_service_not_initialized'));
  static LocalNotificationScheduler get scheduler =>
      _scheduler ?? (throw StateError('notification_service_not_initialized'));
  static ProactiveNotificationPolicyService get proactivePolicyService =>
      _proactivePolicy ??
      (throw StateError('notification_service_not_initialized'));

  static Future<DailySummaryViewData?> loadDailySummary() =>
      DailySummaryViewService(
        registry: _proactiveDetectionRegistry ??
            (throw StateError('notification_service_not_initialized')),
        policyService: proactivePolicyService,
        currentAccountScopeId: () => AuthService.currentUserId,
      ).load();

  static Future<void> evaluateDetections(
    DetectionEvaluationTrigger trigger,
  ) async {
    if (AuthService.currentUserId == null) return;
    if (_detectionEvaluationRunning) {
      _queuedDetectionTrigger = trigger;
      return;
    }
    _detectionEvaluationRunning = true;
    try {
      await _detectionLifecycle?.evaluate(trigger);
      final queued = _queuedDetectionTrigger;
      _queuedDetectionTrigger = null;
      if (queued != null && AuthService.currentUserId != null) {
        await _detectionLifecycle?.evaluate(queued);
      }
    } finally {
      _detectionEvaluationRunning = false;
    }
  }

  static void _eventChanged() {
    unawaited(
      _evaluateDetectionsSafely(
        DetectionEvaluationTrigger.eventChanged,
        'event_changed',
      ),
    );
  }

  static void _taskChanged() {
    unawaited(
      _evaluateDetectionsSafely(
        DetectionEvaluationTrigger.taskChanged,
        'task_changed',
      ),
    );
  }

  static Future<void> _evaluateDetectionsSafely(
    DetectionEvaluationTrigger trigger,
    String step,
  ) async {
    try {
      await evaluateDetections(trigger);
    } catch (error) {
      final descriptor = AppErrorClassifier.classify(error);
      AppDiagnostics.record(
        component: 'notification_detection',
        domain: 'notification',
        operation: 'evaluate',
        step: step,
        code: descriptor.code,
        severity: descriptor.severity,
        retryStrategy: descriptor.retryStrategy,
        correlationId: descriptor.correlationId,
        sourceExceptionType: AppErrorClassifier.safeExceptionType(error),
      );
    }
  }

  static Future<NotificationNavigationIntent?>
      consumePendingInteraction() async {
    final payload = _pendingPayload;
    _pendingPayload = null;
    if (payload == null) return null;
    return _interactions!.resolve(payload);
  }

  static Future<String> currentTimezoneId() async {
    try {
      final identifier = (await FlutterTimezone.getLocalTimezone()).identifier;
      tz_data.initializeTimeZones();
      tz.getLocation(identifier);
      return identifier;
    } on Object {
      return 'Etc/UTC';
    }
  }

  static int platformId(String logicalId) {
    var hash = 0x811c9dc5;
    for (final unit in logicalId.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  static Future<void> showNotification({
    required String title,
    required String body,
  }) async {
    // Legacy callers may pass personal content. It is deliberately discarded.
    // N.1 never turns an unrelated domain success into a proactive alert.
  }

  static Future<NotificationScheduleResult> sendExplicitTest() async {
    final scope = AuthService.requireUserId();
    const uuid = Uuid();
    final instant = DateTime.now().toUtc();
    final logicalId = uuid.v7();
    return scheduler.deliverImmediateTestNotification(
      LocalNotificationRequest(
        logicalNotificationId: logicalId,
        accountScopeId: scope,
        category: LocalNotificationCategory.test,
        createdAt: instant,
        scheduledAt: instant,
        timezoneId: await currentTimezoneId(),
        scheduleMeaning: NotificationScheduleMeaning.absoluteInstant,
        privacyLevel: NotificationPrivacyLevel.generic,
        interactionType: NotificationInteractionType.openOnly,
        destinationType: NotificationDestinationType.home,
        destinationReference: 'home',
        source: LocalNotificationSource.explicitTest,
        status: LocalNotificationStatus.registered,
        platformNotificationId: platformId(logicalId),
        correlationId: uuid.v7(),
        policyVersionObserved: 1,
      ),
    );
  }
}
